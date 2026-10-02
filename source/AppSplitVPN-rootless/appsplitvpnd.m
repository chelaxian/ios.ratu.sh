#import "PolicyEngine.h"
#import "ASVSupervisor.h"
#import "ASVMulti.h"
#import "ASVMemoryBudget.h"
#import "Shared.h"
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <notify.h>
#import <signal.h>
#import <sys/stat.h>
#import <objc/message.h>
#import <unistd.h>
static ASVPolicyEngine *engine;
static ASVMulti *multi;
static NSDictionary *lastPrefs;
static BOOL lastActive;
static BOOL initialized;
static NSTimeInterval lastRefresh;
static int (*anyVPNActive)(void);
static NSString *lastState;
static NSTimeInterval lastStateWrite;
static NSString *vpnName;
static NSTimeInterval lastVPNLookup;
static NSString *lastRouteFingerprint;
static NSString *currentMode;
static BOOL badgeColor=YES;
static BOOL shuttingDown;
static int memoryBudget;

// Current routing table: a single block (no history) listing every selected app and its outcome.
// Rewritten only when the effective rules change.
static void RouteJournal(NSString *headline, NSString *route, NSArray<NSString *> *apps, NSArray<NSString *> *skipped) {
    NSString *fingerprint=[NSString stringWithFormat:@"%@|%@|%@|%@",headline,route ?: @"",apps ?: @[],skipped ?: @[]];
    if ([fingerprint isEqualToString:lastRouteFingerprint]) return;
    lastRouteFingerprint=fingerprint;
    NSMutableArray *block=[NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@  %@",[NSDate date],headline]];
    NSSet *skip=[NSSet setWithArray:skipped ?: @[]];
    for (NSString *app in apps) [block addObject:[NSString stringWithFormat:@"%@ %@",[skip containsObject:app]?@"SKIP":route,app]];
    [@[block] writeToFile:ASV_ROUTE_LOG atomically:YES];
    chmod(ASV_ROUTE_LOG.fileSystemRepresentation,0644);
}
static id CallObject(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return [object respondsToSelector:selector] ? ((id(*)(id,SEL))objc_msgSend)(object,selector):nil;
}
static void RefreshVPNName(void) {
    Class cls=NSClassFromString(@"NEConfigurationManager");
    id manager=CallObject(cls,@"sharedManager") ?: CallObject(cls,@"defaultManager");
    SEL selector=NSSelectorFromString(@"loadConfigurationsWithCompletionQueue:handler:");
    if (!manager || ![manager respondsToSelector:selector]) return;
    ((void(*)(id,SEL,dispatch_queue_t,id))objc_msgSend)(manager,selector,dispatch_get_main_queue(),^(NSArray *configs,__unused NSError *error){
        NSMutableArray *names=[NSMutableArray array];
        for (id cfg in configs) {
            SEL en=NSSelectorFromString(@"isEnabled");
            if (![cfg respondsToSelector:en] || !((BOOL(*)(id,SEL))objc_msgSend)(cfg,en)) continue;
            NSString *name=CallObject(cfg,@"name") ?: CallObject(cfg,@"localizedDescription");
            if (![name isKindOfClass:NSString.class] || !name.length) continue;
            NSString *lower=name.lowercaseString;
            if ([lower containsString:@"com.apple"] || [lower containsString:@"privaterelay"] || [lower containsString:@"networkprivacy"]) continue;
            [names addObject:name];
        }
        // Multiple enabled configurations do not prove which one owns the live tunnel.
        NSString *resolved=names.count==1 ? names.firstObject:nil;
        if (![vpnName isEqualToString:resolved]) { vpnName=resolved;initialized=NO; }
    });
}

static NSDictionary *ReadPreferences(void) {
    NSDictionary *raw = [NSDictionary dictionaryWithContentsOfFile:ASV_PREFS];
    NSString *mode = [@[@"tunnelOnly",@"bypass",@"multiVPN"] containsObject:raw[@"mode"]] ? raw[@"mode"] : @"bypass";
    NSMutableDictionary *validated = [@{@"enabled": @([raw[@"enabled"] isKindOfClass:NSNumber.class] && [raw[@"enabled"] boolValue]), @"mode": mode} mutableCopy];
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"];
    for (NSString *key in @[ASV_VPN, ASV_DIRECT]) {
        NSMutableOrderedSet *apps = [NSMutableOrderedSet orderedSet];
        id values = raw[key];
        if ([values isKindOfClass:NSArray.class] && [values count] <= 2048) {
            for (id value in values)
                if ([value isKindOfClass:NSString.class] && [value length] > 0 && [value length] <= 255 &&
                    [value rangeOfCharacterFromSet:allowed.invertedSet].location == NSNotFound) [apps addObject:value];
        }
        validated[key] = apps.array;
    }
    validated[@"badgeColor"] = @(raw[@"badgeColor"] == nil || [raw[@"badgeColor"] boolValue]);
    NSMutableDictionary *matrix=[NSMutableDictionary dictionary];
    if([raw[ASV_MATRIX] isKindOfClass:NSDictionary.class] && [raw[ASV_MATRIX] count]<=2048){
        for(id bundle in raw[ASV_MATRIX]){id profile=raw[ASV_MATRIX][bundle];
            if([bundle isKindOfClass:NSString.class] && [bundle length]>0 && [bundle length]<=255 && [bundle rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound && [profile isKindOfClass:NSString.class]){NSUUID *uuid=[[NSUUID alloc] initWithUUIDString:profile];if(uuid)matrix[bundle]=uuid.UUIDString;}
        }
    }
    validated[ASV_MATRIX]=matrix;
    return validated;
}
static void State(NSString *status, NSString *error) {
    NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%lu|%@|%@|%@|%d",status,error ?: @"",(unsigned long)engine.count,engine.unresolved,vpnName ?: @"",currentMode ?: @"",badgeColor];
    NSTimeInterval now=[NSDate date].timeIntervalSince1970;
    BOOL changed=![lastState isEqual:fingerprint];
    if (!changed && now-lastStateWrite<30) return;
    lastState = fingerprint;
    lastStateWrite=now;
    NSDictionary *state = @{@"status": status, @"error": error ?: @"", @"rules": @(engine.count),
        @"unresolved": engine.unresolved, @"vpnName":vpnName ?: @"", @"mode":currentMode ?: @"bypass", @"memoryBudgetMB":@(memoryBudget), @"updated": @([NSDate date].timeIntervalSince1970), @"version": @"0.4.0~beta4"};
    [state writeToFile:ASV_STATE atomically:YES];
    chmod(ASV_STATE.fileSystemRepresentation,0644);
    static int splitToken = -1;
    if (splitToken < 0) notify_register_check(ASV_STATE_NOTIFY, &splitToken);
    // Bits 0-1: 0 inactive, 1 BYPASS, 2 TUNNEL ONLY. Bit 2: badge coloring switched off.
    uint64_t split=([status isEqual:@"active"] || [status isEqual:@"partial"]) ? (ASVIsMultiMode(@{@"mode":currentMode ?: @""}) ? 3 : ([currentMode isEqual:@"tunnelOnly"] ? 2 : 1)) : 0;
    if (split && !badgeColor) split|=4;
    if (splitToken >= 0) notify_set_state(splitToken, split);
    if (changed) {
        notify_post(ASV_STATE_NOTIFY);
        fprintf(stderr,"AppSplitVPN status=%s rules=%lu error=%s\n", status.UTF8String,(unsigned long)engine.count,(error ?: @"").UTF8String);
    }
}
static void Reconcile(BOOL force) {
    if(shuttingDown)return;
    @autoreleasepool { @try {
        NSDictionary *prefs = ReadPreferences();
        currentMode=prefs[@"mode"];
        badgeColor=[prefs[@"badgeColor"] boolValue];
        BOOL multiMode=ASVIsMultiMode(prefs);
        [multi tickMatrix:prefs[ASV_MATRIX] enabled:multiMode && [prefs[@"enabled"] boolValue]];
        ASVSupervisorSetTransactionPaused(multiMode || multi.ownsProfiles || multi.busy);
        if(multiMode || multi.ownsProfiles || multi.busy){
            vpnName=multi.names;
            State(multiMode?multi.status:@"recovering",multi.error);
            NSMutableArray *lines=[NSMutableArray array];
            for(NSString *bundle in [prefs[ASV_MATRIX] allKeys]){NSString *uuid=prefs[ASV_MATRIX][bundle];[lines addObject:[NSString stringWithFormat:@"VPN %@ -> %@",bundle,uuid]];}
            RouteJournal([NSString stringWithFormat:@"MULTI VPN: %@",multi.status],@"MATRIX",lines,engine.unresolved);
            initialized=NO;return;
        }
        BOOL active = anyVPNActive && anyVPNActive() != 0;
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (active && now-lastVPNLookup>25) { lastVPNLookup=now;RefreshVPNName(); }
        if (!active) vpnName=nil;
        // Periodic UUID refresh covers application upgrades and newly installed extensions.
        if (!force && initialized && active == lastActive && [prefs isEqual:lastPrefs] && now-lastRefresh < 60) return;
        initialized = YES; lastActive = active; lastPrefs = prefs; lastRefresh = now;
        if (![prefs[@"enabled"] boolValue]) { [engine clear]; State(@"disabled",nil); RouteJournal(@"disabled: all apps use the system VPN",nil,nil,nil); return; }
        if (!anyVPNActive) { [engine clear]; State(@"unsupported",@"System VPN status API unavailable"); return; }
        if (!active) { [engine clear]; State(@"waitingVPN",nil); RouteJournal(@"no active VPN: rules removed",nil,nil,nil); return; }
        NSString *mode = prefs[@"mode"];
        NSString *error = nil;
        NSArray *apps = prefs[[mode isEqual:@"tunnelOnly"]?ASV_VPN:ASV_DIRECT];
        BOOL ok = [engine replaceMode:mode applications:apps error:&error];
        State(ok ? (engine.unresolved.count ? @"partial" : @"active") : @"error",error);
        if (ok) {
            BOOL tunnel=[mode isEqual:@"tunnelOnly"];
            RouteJournal([NSString stringWithFormat:@"%@: other apps -> %@",tunnel?@"TUNNEL ONLY":@"BYPASS",tunnel?@"DIRECT":@"VPN"],tunnel?@"VPN   ":@"DIRECT",apps,engine.unresolved);
        }
        if (!ok) lastRefresh = now-55; // bounded retry after five seconds, not a busy loop
    } @catch (NSException *exception) {
        [engine clear]; State(@"error",exception.name); initialized=NO;
    } }
}
static void SetEnabled(BOOL enabled) {
    NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];
    if ([prefs[@"enabled"] boolValue]==enabled) { Reconcile(YES); return; }
    prefs[@"enabled"]=@(enabled);
    if ([prefs writeToFile:ASV_PREFS atomically:YES]) {
        chown(ASV_PREFS.fileSystemRepresentation,501,501);
        chmod(ASV_PREFS.fileSystemRepresentation,0644);
    }
    Reconcile(YES);
}
int main(int argc,char **argv) { @autoreleasepool {
    (void)argc; (void)argv;
    memoryBudget=ASVConfigureOwnMemoryBudget();
    dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension",RTLD_NOW);
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices",RTLD_NOW);
    void *library=dlopen("/usr/lib/system/libsystem_networkextension.dylib",RTLD_NOW);
    anyVPNActive=dlsym(library ?: RTLD_DEFAULT,"ne_session_manager_has_active_sessions");
    engine=[ASVPolicyEngine new];
    multi=[[ASVMulti alloc] initWithEngine:engine];
    // TUNNEL ONLY sends unlisted processes direct; the health check of this
    // service must still reach the tunnel it binds to.
    char executable[PATH_MAX]={0};
    uint32_t size=sizeof executable;
    if (_NSGetExecutablePath(executable,&size)==0) {
        NSArray *uuids=[NSClassFromString(@"NEProcessInfo") copyUUIDsForExecutable:@(executable)];
        engine.selfUUIDs=[uuids isKindOfClass:NSArray.class] ? uuids : @[];
    }
    ASVSupervisorStart();
    int token;
    notify_register_dispatch(ASV_NOTIFY,&token,dispatch_get_main_queue(),^(int t){(void)t;Reconcile(YES);ASVSupervisorTick();});
    int toggleToken;
    unlink(ASV_LOG.fileSystemRepresentation); // change log removed in 0.2.3
    notify_register_dispatch(ASV_CMD_TOGGLE,&toggleToken,dispatch_get_main_queue(),^(int t){
        (void)t;
        SetEnabled(![[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][@"enabled"] boolValue]);
    });
    int setToken;
    notify_register_dispatch(ASV_CMD_SET,&setToken,dispatch_get_main_queue(),^(int t){
        uint64_t wanted=0;
        notify_get_state(t,&wanted);
        if (wanted==1 || wanted==2) SetEnabled(wanted==1);
    });
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{if(!shuttingDown){Reconcile(NO);ASVSupervisorTick();}}); dispatch_resume(timer);
    signal(SIGTERM,SIG_IGN); signal(SIGINT,SIG_IGN);
    dispatch_source_t term=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());
    dispatch_source_set_event_handler(term,^{if(shuttingDown)return;shuttingDown=YES;ASVSupervisorSetTransactionPaused(YES);[multi restoreWithCompletion:^(BOOL ok){[engine clear];State(@"stopped",ok?nil:@"MULTI recovery pending");exit(ok?0:1);}];}); dispatch_resume(term);
    dispatch_source_t interrupt=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGINT,0,dispatch_get_main_queue());
    dispatch_source_set_event_handler(interrupt,^{if(shuttingDown)return;shuttingDown=YES;ASVSupervisorSetTransactionPaused(YES);[multi restoreWithCompletion:^(BOOL ok){[engine clear];State(@"stopped",ok?nil:@"MULTI recovery pending");exit(ok?0:1);}];}); dispatch_resume(interrupt);
    [[NSRunLoop mainRunLoop] run];
} return 0; }
