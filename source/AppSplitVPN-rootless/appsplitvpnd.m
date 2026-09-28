#import "PolicyEngine.h"
#import "Shared.h"
#import <dlfcn.h>
#import <notify.h>
#import <signal.h>
#import <sys/stat.h>
static ASVPolicyEngine *engine;
static NSDictionary *lastPrefs;
static BOOL lastActive;
static BOOL initialized;
static NSTimeInterval lastRefresh;
static int (*anyVPNActive)(void);
static NSString *lastState;
static NSTimeInterval lastStateWrite;

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
    NSString *fingerprint = [NSString stringWithFormat:@"%@|%@|%lu|%@",status,error ?: @"",(unsigned long)engine.count,engine.unresolved];
    NSTimeInterval now=[NSDate date].timeIntervalSince1970;
    BOOL changed=![lastState isEqual:fingerprint];
    if (!changed && now-lastStateWrite<30) return;
    lastState = fingerprint;
    lastStateWrite=now;
    NSDictionary *state = @{@"status": status, @"error": error ?: @"", @"rules": @(engine.count),
        @"unresolved": engine.unresolved, @"updated": @([NSDate date].timeIntervalSince1970), @"version": @"0.1.0"};
    [state writeToFile:ASV_STATE atomically:YES];
    chmod(ASV_STATE.fileSystemRepresentation,0644);
    if (changed) fprintf(stderr,"AppSplitVPN status=%s rules=%lu error=%s\n", status.UTF8String,(unsigned long)engine.count,(error ?: @"").UTF8String);
}
static void Reconcile(BOOL force) {
    @autoreleasepool { @try {
        NSDictionary *prefs = ReadPreferences();
        BOOL active = anyVPNActive && anyVPNActive() != 0;
        NSTimeInterval now = [NSDate date].timeIntervalSince1970;
        // Periodic UUID refresh covers application upgrades and newly installed extensions.
        if (!force && initialized && active == lastActive && [prefs isEqual:lastPrefs] && now-lastRefresh < 60) return;
        initialized = YES; lastActive = active; lastPrefs = prefs; lastRefresh = now;
        if (![prefs[@"enabled"] boolValue]) { [engine clear]; State(@"disabled",nil); return; }
        if (!anyVPNActive) { [engine clear]; State(@"unsupported",@"System VPN status API unavailable"); return; }
        if (!active) { [engine clear]; State(@"waitingVPN",nil); return; }
        NSString *mode = prefs[@"mode"];
        NSString *error = nil;
        BOOL ok = [engine replaceMode:mode applications:prefs[[mode isEqual:@"tunnelOnly"]?ASV_VPN:ASV_DIRECT] error:&error];
        State(ok ? @"active" : @"error",error);
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
