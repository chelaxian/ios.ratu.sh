#import "PolicyEngine.h"
#import "Shared.h"
#import <dlfcn.h>
#import <notify.h>
#import <signal.h>
#import <sys/stat.h>
#import <objc/message.h>
#import <unistd.h>
static ASVPolicyEngine *engine;
static NSDictionary *lastPrefs;
static BOOL lastActive;
static BOOL initialized;
static NSTimeInterval lastRefresh;
static int (*anyVPNActive)(void);
static NSString *lastState;
static NSTimeInterval lastStateWrite;
static NSString *vpnName;
static NSDictionary *lastLoggedPrefs;
static NSString *lastLoggedState;
static NSTimeInterval lastVPNLookup;
static NSString *lastRouteFingerprint;

static void Journal(NSString *line) {
    NSMutableArray *entries=[[NSArray arrayWithContentsOfFile:ASV_LOG] mutableCopy] ?: [NSMutableArray array];
    [entries addObject:[NSString stringWithFormat:@"%@  %@",[NSDate date],line]];
    if (entries.count>250) [entries removeObjectsInRange:NSMakeRange(0,entries.count-250)];
    [entries writeToFile:ASV_LOG atomically:YES];
    chmod(ASV_LOG.fileSystemRepresentation,0644);
}
// Routing journal: one block per applied rule set, listing every selected app and its outcome.
static void RouteJournal(NSString *headline, NSString *route, NSArray<NSString *> *apps, NSArray<NSString *> *skipped) {
    NSString *fingerprint=[NSString stringWithFormat:@"%@|%@|%@|%@",headline,route ?: @"",apps ?: @[],skipped ?: @[]];
    if ([fingerprint isEqualToString:lastRouteFingerprint]) return;
    lastRouteFingerprint=fingerprint;
    NSMutableArray *entries=[[NSArray arrayWithContentsOfFile:ASV_ROUTE_LOG] mutableCopy] ?: [NSMutableArray array];
    NSMutableArray *block=[NSMutableArray arrayWithObject:[NSString stringWithFormat:@"%@  %@",[NSDate date],headline]];
    NSSet *skip=[NSSet setWithArray:skipped ?: @[]];
    for (NSString *app in apps) [block addObject:[NSString stringWithFormat:@"%@ %@",[skip containsObject:app]?@"SKIP":route,app]];
    [entries addObject:block];
    while (entries.count>20) [entries removeObjectAtIndex:0];
    [entries writeToFile:ASV_ROUTE_LOG atomically:YES];
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
    NSString *mode = [raw[@"mode"] isEqual:@"tunnelOnly"] ? @"tunnelOnly" : @"bypass";
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
    return validated;
}
static void State(NSString *status, NSString *error) {
    NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%lu|%@|%@",status,error ?: @"",(unsigned long)engine.count,engine.unresolved,vpnName ?: @""];
    NSTimeInterval now=[NSDate date].timeIntervalSince1970;
    BOOL changed=![lastState isEqual:fingerprint];
    if (!changed && now-lastStateWrite<30) return;
    lastState = fingerprint;
    lastStateWrite=now;
    NSDictionary *state = @{@"status": status, @"error": error ?: @"", @"rules": @(engine.count),
        @"unresolved": engine.unresolved, @"vpnName":vpnName ?: @"", @"updated": @([NSDate date].timeIntervalSince1970), @"version": @"0.2.2"};
    [state writeToFile:ASV_STATE atomically:YES];
    chmod(ASV_STATE.fileSystemRepresentation,0644);
    static int splitToken = -1;
    if (splitToken < 0) notify_register_check(ASV_STATE_NOTIFY, &splitToken);
    if (splitToken >= 0) notify_set_state(splitToken, ([status isEqual:@"active"] || [status isEqual:@"partial"]) ? 1 : 0);
    if (changed) {
        NSString *event=[NSString stringWithFormat:@"status=%@ rules=%lu unavailable=%lu vpn=%@ %@",status,(unsigned long)engine.count,(unsigned long)engine.unresolved.count,vpnName ?: @"?",error ?: @""];
        if (![event isEqual:lastLoggedState]) { Journal(event);lastLoggedState=event; }
        notify_post(ASV_STATE_NOTIFY);
        fprintf(stderr,"AppSplitVPN status=%s rules=%lu error=%s\n", status.UTF8String,(unsigned long)engine.count,(error ?: @"").UTF8String);
    }
}
static void Reconcile(BOOL force) {
    @autoreleasepool { @try {
        NSDictionary *prefs = ReadPreferences();
        BOOL active = anyVPNActive && anyVPNActive() != 0;
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        if (active && now-lastVPNLookup>25) { lastVPNLookup=now;RefreshVPNName(); }
        if (!active) vpnName=nil;
        // Periodic UUID refresh covers application upgrades and newly installed extensions.
        if (!force && initialized && active == lastActive && [prefs isEqual:lastPrefs] && now-lastRefresh < 60) return;
        initialized = YES; lastActive = active; lastPrefs = prefs; lastRefresh = now;
        if (![prefs isEqual:lastLoggedPrefs]) {
            NSString *mode=prefs[@"mode"];
            NSString *key=[mode isEqual:@"tunnelOnly"]?ASV_VPN:ASV_DIRECT;
            Journal([NSString stringWithFormat:@"settings enabled=%@ mode=%@ selected=%lu",[prefs[@"enabled"] boolValue]?@"yes":@"no",mode,(unsigned long)[prefs[key] count]]);
            lastLoggedPrefs=[prefs copy];
        }
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
int main(int argc,char **argv) { @autoreleasepool {
    (void)argc; (void)argv;
    dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension",RTLD_NOW);
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices",RTLD_NOW);
    void *library=dlopen("/usr/lib/system/libsystem_networkextension.dylib",RTLD_NOW);
    anyVPNActive=dlsym(library ?: RTLD_DEFAULT,"ne_session_manager_has_active_sessions");
    engine=[ASVPolicyEngine new];
    int token;
    notify_register_dispatch(ASV_NOTIFY,&token,dispatch_get_main_queue(),^(int t){(void)t;Reconcile(YES);});
    int toggleToken;
    int clearToken;
    notify_register_dispatch(ASV_CMD_CLEAR_LOGS,&clearToken,dispatch_get_main_queue(),^(int t){
        (void)t;
        [@[] writeToFile:ASV_LOG atomically:YES];
        [@[] writeToFile:ASV_ROUTE_LOG atomically:YES];
        chmod(ASV_LOG.fileSystemRepresentation,0644);chmod(ASV_ROUTE_LOG.fileSystemRepresentation,0644);
        lastRouteFingerprint=nil;lastLoggedState=nil;lastLoggedPrefs=nil;
        Reconcile(YES);
        notify_post(ASV_STATE_NOTIFY);
    });
    notify_register_dispatch(ASV_CMD_TOGGLE,&toggleToken,dispatch_get_main_queue(),^(int t){
        (void)t;
        NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];
        prefs[@"enabled"]=@(![prefs[@"enabled"] boolValue]);
        if ([prefs writeToFile:ASV_PREFS atomically:YES]) {
            chown(ASV_PREFS.fileSystemRepresentation,501,501);
            chmod(ASV_PREFS.fileSystemRepresentation,0644);
            Reconcile(YES);
        }
    });
    dispatch_source_t timer=dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER,0,0,dispatch_get_main_queue());
    dispatch_source_set_timer(timer,DISPATCH_TIME_NOW,NSEC_PER_SEC,100*NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer,^{Reconcile(NO);}); dispatch_resume(timer);
    signal(SIGTERM,SIG_IGN); signal(SIGINT,SIG_IGN);
    dispatch_source_t term=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());
    dispatch_source_set_event_handler(term,^{[engine clear];State(@"stopped",nil);exit(0);}); dispatch_resume(term);
    dispatch_source_t interrupt=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGINT,0,dispatch_get_main_queue());
    dispatch_source_set_event_handler(interrupt,^{[engine clear];State(@"stopped",nil);exit(0);}); dispatch_resume(interrupt);
    [[NSRunLoop mainRunLoop] run];
} return 0; }
