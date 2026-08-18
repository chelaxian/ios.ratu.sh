//
//  ccvpnd.m  —  privileged root daemon for CCVPN-ON-OFF-AUTO
//
//  Runs as a RootHide LaunchDaemon with entitlements the CC host lacks:
//  com.apple.networkextension + memorystatus + no-sandbox. Owns ALL the
//  entitlement-gated work and talks to the CC tile over Darwin notifications.
//
//  Connect mechanism: the UNIVERSAL ne_session_* C API in
//  libsystem_networkextension.dylib — the exact path Settings.app's "VPN
//  Status" toggle and the macOS VPNStatus menu use. We hand nesessionmanager
//  the ACTIVE config's UUID and call ne_session_start / ne_session_stop; the
//  system hosts the provider/personal-VPN itself. No app-specific code.
//
//  Sessions are created LAZILY (only when start/stop is invoked) so a bad
//  ne_session handle can never crash daemon startup. "Is VPN up" is read via
//  ne_session_manager_has_active_sessions (the status-bar rectangle icon).
//
//  Commands (from tile):
//    com.ratush.ccvpnonoffauto.cmd.tap       -> toggle the active VPN
//    com.ratush.ccvpnonoffauto.cmd.longpress -> toggle AUTO (watchdog keep-alive)
//    com.ratush.ccvpnonoffauto.cmd.query     -> re-broadcast current state
//  States (to tile):
//    com.ratush.ccvpnonoffauto.state.off / .vpn / .auto
//

#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#include <mach/mach.h>
#import <dlfcn.h>

// ---- libproc (header absent from this SDK; symbols are in libSystem) ----
extern int proc_listallpids(void *buffer, int buffersize);
extern int proc_name(int pid, void *buffer, uint32_t buffersize);

// ---- memorystatus_control (private) ----
#define MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT 6
extern int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags, void *buffer, size_t buffersize);

// ---- NEVPNStatus (integer values, avoid header dependency) ----
enum { kNEVPNInvalid = 0, kNEVPNDisconnected = 1, kNEVPNConnecting = 2,
       kNEVPNConnected = 3, kNEVPNReasserting = 4, kNEVPNDisconnecting = 5 };

// ---- NESessionType (private enum for ne_session_create) ----
enum { kNESessionTypeVPN = 0, kNESessionTypeAppProxy = 1,
       kNESessionTypeContentFilter = 2, kNESessionTypePacketTunnel = 3,
       kNESessionTypeDNSProxy = 4, kNESessionTypeAppPush = 5 };

#define CMD_TAP    CFSTR("com.ratush.ccvpnonoffauto.cmd.tap")
#define CMD_LONG   CFSTR("com.ratush.ccvpnonoffauto.cmd.longpress")
#define CMD_QUERY  CFSTR("com.ratush.ccvpnonoffauto.cmd.query")
#define ST_OFF     CFSTR("com.ratush.ccvpnonoffauto.state.off")
#define ST_VPN     CFSTR("com.ratush.ccvpnonoffauto.state.vpn")
#define ST_AUTO    CFSTR("com.ratush.ccvpnonoffauto.state.auto")

#define SEL_(n) NSSelectorFromString(@n)

#pragma mark - log

static void DLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void DLog(NSString *fmt, ...) {
    va_list args; va_start(args, fmt);
    NSString *body = [[NSString alloc] initWithFormat:fmt arguments:args];
    va_end(args);
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], body];
    fprintf(stderr, "%s", line.UTF8String);
    @try {
        NSString *p = @"/var/tmp/ccvpnd.log";
        NSData *d = [line dataUsingEncoding:NSUTF8StringEncoding];
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
        if (!fh) [d writeToFile:p atomically:YES];
        else { [fh seekToEndOfFile]; [fh writeData:d]; [fh closeFile]; }
    } @catch (__unused id e) {}
}

#pragma mark - runtime helpers

static id H(id rcv, SEL sel) {
    if (!rcv || !sel || ![rcv respondsToSelector:sel]) return nil;
    return ((id(*)(id, SEL))objc_msgSend)(rcv, sel);
}
static BOOL HB(id rcv, SEL sel) {
    if (!rcv || !sel || ![rcv respondsToSelector:sel]) return NO;
    return ((BOOL(*)(id, SEL))objc_msgSend)(rcv, sel);
}
static id SharedMgr(Class c) {
    if (!c) return nil;
    SEL arr[] = { NSSelectorFromString(@"sharedManager"),
                  NSSelectorFromString(@"defaultManager") };
    for (int i = 0; i < 2; i++)
        if ([c respondsToSelector:arr[i]])
            return ((id(*)(id, SEL))objc_msgSend)((id)c, arr[i]);
    return nil;
}

#pragma mark - ne_session_* (libsystem_networkextension.dylib)

// The universal connect/disconnect path. Settings.app's VPN toggle and the
// macOS VPNStatus menu build a ne_session_t from a configuration UUID and call
// ne_session_start / ne_session_stop; nesessionmanager does the hosting.
typedef void *ne_session_t;
typedef void (^ne_evt_block)(void *);
static ne_session_t (*_ne_create)(const unsigned char *, int);
static int          (*_ne_start)(ne_session_t);
static int          (*_ne_stop)(ne_session_t);
static int          (*_ne_status)(ne_session_t);
static int          (*_ne_any_active)(void);   // ne_session_manager_has_active_sessions
static void         (*_ne_set_event_handler)(ne_session_t, ne_evt_block);
static int          (*_ne_establish_ipc)(ne_session_t);

static void LoadNELib(void) {
    void *h = dlopen("/usr/lib/system/libsystem_networkextension.dylib", RTLD_NOW);
    if (!h) { DLog(@"dlopen ne-lib FAILED: %s", dlerror()); return; }
    _ne_create           = dlsym(h, "ne_session_create");
    _ne_start            = dlsym(h, "ne_session_start");
    _ne_stop             = dlsym(h, "ne_session_stop");
    _ne_status           = dlsym(h, "ne_session_get_status");
    _ne_any_active       = dlsym(h, "ne_session_manager_has_active_sessions");
    _ne_set_event_handler= dlsym(h, "ne_session_set_event_handler");
    _ne_establish_ipc    = dlsym(h, "ne_session_establish_ipc");
    DLog(@"ne-lib syms create=%p start=%p stop=%p status=%p any=%p evth=%p ipc=%p",
         _ne_create, _ne_start, _ne_stop, _ne_status, _ne_any_active,
         _ne_set_event_handler, _ne_establish_ipc);
}

#pragma mark - state

static NSArray  *g_configs   = nil;  // all NEConfiguration objects (with UUIDs)
static id        g_active    = nil;  // the active VPN NEConfiguration
static int       g_activeType = kNESessionTypeVPN;
static int       g_mode      = 0;    // 0 off, 1 vpn, 2 auto
static NSTimer  *g_watchdog  = nil;
static int       g_connected = 0;    // last known connection status

static Class NEConfigMgrClass(void) {
    static Class c = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = NSClassFromString(@"NEConfigurationManager"); });
    return c;
}
static id NEConfigMgr(void) { return SharedMgr(NEConfigMgrClass()); }

static NSString *CfgID(id cfg) {
    id v = H(cfg, SEL_("identifier"));
    if ([v isKindOfClass:[NSString class]]) return v;
    if ([v respondsToSelector:@selector(UUIDString)])
        return [(id)v performSelector:@selector(UUIDString)];
    return [cfg description];
}
static NSString *CfgName(id cfg) {
    id n = H(cfg, SEL_("name"));
    if ([n isKindOfClass:[NSString class]]) return n;
    id d = H(cfg, SEL_("localizedDescription"));
    return [d isKindOfClass:[NSString class]] ? d : @"?";
}
static BOOL CfgEnabled(id cfg) { return HB(cfg, SEL_("isEnabled")); }

// UUID bytes for ne_session_create.
static NSUUID *CfgUUID(id cfg) {
    id v = H(cfg, SEL_("identifier"));
    if ([v isKindOfClass:[NSUUID class]]) return v;
    if ([v isKindOfClass:[NSString class]])
        return [[NSUUID alloc] initWithUUIDString:v];
    return nil;
}

// Session type for the config: packet-tunnel providers vs personal VPN.
static int CfgSessionType(id cfg) {
    id vpn = H(cfg, SEL_("VPN"));
    id proto = vpn ? H(vpn, SEL_("protocol")) : nil;
    NSString *cn = NSStringFromClass([proto class]);
    if ([cn containsString:@"TunnelProvider"]) return kNESessionTypePacketTunnel;
    return kNESessionTypeVPN;
}

static BOOL StatusUp(int s) { return s == kNEVPNConnected || s == kNEVPNConnecting || s == kNEVPNReasserting; }

static void Post(CFStringRef n) {
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), n, NULL, NULL, TRUE);
}

#pragma mark - configs

static void LoadConfigs(void (^done)(void)) {
    id mgr = NEConfigMgr();
    if (!mgr) { DLog(@"NEConfigurationManager unavailable"); done(); return; }
    SEL lcq = SEL_("loadConfigurationsWithCompletionQueue:handler:");
    SEL lc  = SEL_("loadConfigurationsWithCompletionHandler:");
    if ([mgr respondsToSelector:lcq]) {
        ((void(*)(id, SEL, id, id))objc_msgSend)(mgr, lcq, dispatch_get_main_queue(), ^(NSArray *a, NSError *e){
            g_configs = [a copy];
            DLog(@"loaded(q) %lu configs err=%@", (unsigned long)g_configs.count, e);
            done();
        });
    } else if ([mgr respondsToSelector:lc]) {
        ((void(*)(id, SEL, id))objc_msgSend)(mgr, lc, ^(NSArray *a, NSError *e) {
            g_configs = [a copy];
            DLog(@"loaded %lu configs err=%@", (unsigned long)g_configs.count, e);
            done();
        });
    } else { DLog(@"no load selector"); done(); }
}

// Skip Apple system configurations (Private Relay, network privacy, etc.) —
// they show up enabled but are not user VPNs.
static BOOL IsAppleSystem(id cfg) {
    NSString *nm = CfgName(cfg).lowercaseString;
    NSString *idstr = CfgID(cfg).lowercaseString;
    NSArray *bad = @[@"com.apple", @"networkprivacy", @"privaterelay", @"private relay",
                     @"icloud", @"nehelper", @"exploitd", @"wifipolicy", @"network extension"];
    for (NSString *b in bad)
        if ([nm containsString:b] || [idstr containsString:b]) return YES;
    return NO;
}

// One-time dump of the enabled-config landscape for diagnostics.
static void DumpEnabled(void) {
    int i = 0;
    for (id c in g_configs) {
        if (!CfgEnabled(c)) continue;
        DLog(@"  enabled[%d] name=%@ id=%@ type=%d apple=%d",
             i++, CfgName(c), CfgID(c), CfgSessionType(c), IsAppleSystem(c));
    }
}

// Pick the active VPN: any enabled non-Apple config (the one iOS would
// connect), else any enabled config. No per-config status probe (it blocks on
// packet-tunnel sessions). Fully generic.
static id PickActive(void) {
    if (!g_configs.count) return nil;
    DumpEnabled();
    for (id c in g_configs) if (CfgEnabled(c) && !IsAppleSystem(c)) { DLog(@"pickActive: enabled %@", CfgName(c)); return c; }
    for (id c in g_configs) if (CfgEnabled(c)) { DLog(@"pickActive: enabled(apple) %@", CfgName(c)); return c; }
    DLog(@"pickActive: firstObject %@", CfgName(g_configs.firstObject));
    return g_configs.firstObject;
}

static void SetActive(id cfg) {
    if (cfg == g_active) return;
    g_active = cfg;
    if (g_active) {
        g_activeType = CfgSessionType(g_active);
        DLog(@"active=%@ (%@) type=%d", CfgName(g_active), CfgID(g_active), g_activeType);
    }
}

#pragma mark - session control via NEVPNConnection (framework handles IPC)

static BOOL AnyVPNActive(void);     // forward
static void BroadcastState(void);   // forward

static Class NEVPNConnClass(void) {
    static Class c = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ c = NSClassFromString(@"NEVPNConnection"); });
    return c;
}

// Start/stop one NEVPNConnection via its owning manager.
static void RunConn(id conn, int start) {
    SEL startS = NSSelectorFromString(@"startVPNTunnelAndReturnError:");
    SEL stopS  = NSSelectorFromString(@"stopVPNTunnel");
    SEL statS  = NSSelectorFromString(@"status");
    if (start && [conn respondsToSelector:startS]) {
        NSError *err = nil;
        BOOL ok = ((BOOL(*)(id, SEL, NSError**))objc_msgSend)(conn, startS, &err);
        DLog(@"startVPNTunnel ok=%d err=%@", ok, err);
    } else if (!start && [conn respondsToSelector:stopS]) {
        ((void(*)(id, SEL))objc_msgSend)(conn, stopS);
        DLog(@"stopVPNTunnel sent");
    }
    // The session object's .status does NOT get KVO updates for an externally
    // created manager, so it is unreliable (stays "disconnected" even when the
    // tunnel is up). Use AnyVPNActive() (ne_session_manager_has_active_sessions)
    // as the real "VPN icon present / tunnel up" signal instead.
    BOOL wantUp = start;
    for (int i = 0; i < 10; i++) {
        BOOL any = AnyVPNActive();
        NSInteger st = [conn respondsToSelector:statS] ? ((NSInteger(*)(id, SEL))objc_msgSend)(conn, statS) : -1;
        DLog(@"conn wait[%d] sessStatus=%ld anyActive=%d wantUp=%d", i, (long)st, any, wantUp);
        if (wantUp == any) break;
        sleep(start ? 2 : 1);
    }
    // Fetch why it failed to come up (async; logged when it returns).
    SEL lastErr = NSSelectorFromString(@"fetchLastDisconnectErrorWithCompletionHandler:");
    if ([conn respondsToSelector:lastErr]) {
        ((void(*)(id, SEL, id))objc_msgSend)(conn, lastErr, [(void(^)(NSError*))^(NSError *le){
            DLog(@"lastDisconnectError=%@", le);
        } copy]);
    }
    g_connected = AnyVPNActive() ? kNEVPNConnected : kNEVPNDisconnected;
    BroadcastState();
}

// Canonical path: NETunnelProviderManager.loadAllFromPreferences returns full
// managers (with working .connection). With our networkextension + private
// configuration entitlements a root daemon should see the enterprise VPN.
static void DoSession(int start) {
    if (!g_active) SetActive(PickActive());
    if (!g_active) { DLog(@"no active VPN config"); return; }
    NSString *target = CfgName(g_active);
    Class mgrCls = NSClassFromString(@"NETunnelProviderManager");
    SEL loadAll = NSSelectorFromString(@"loadAllFromPreferencesWithCompletionHandler:");
    if (!mgrCls || ![mgrCls respondsToSelector:loadAll]) { DLog(@"NETunnelProviderManager unavailable"); return; }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
        ((void(*)(id, SEL, id))objc_msgSend)((id)mgrCls, loadAll, ^(NSArray *mgrs, NSError *e){
            DLog(@"loadAllFromPreferences: %lu managers err=%@", (unsigned long)mgrs.count, e);
            id found = nil;
            for (id m in mgrs) {
                NSString *d = H(m, NSSelectorFromString(@"localizedDescription"));
                BOOL en = HB(m, NSSelectorFromString(@"isEnabled"));
                NSString *pid = H(m, NSSelectorFromString(@"identifier"));
                DLog(@"  mgr desc=%@ id=%@ enabled=%d", d, pid, en);
                if (d && [target isEqualToString:d]) found = m;
            }
            id conn = found ? H(found, NSSelectorFromString(@"connection")) : nil;
            DLog(@"DoSession target=%@ found=%@ conn=%@", target, found, conn);
            if (conn) {
                RunConn(conn, start);
                return;
            }
            // Fallback: bare privileged connection (manager=nil, often Code=1).
            Class c = NEVPNConnClass();
            SEL wn = NSSelectorFromString(@"createConnectionForEnabledEnterpriseConfigurationWithName:");
            if (c && [c respondsToSelector:wn]) {
                id cc = ((id(*)(id, SEL, id))objc_msgSend)((id)c, wn, target);
                DLog(@"fallback conn=%@", cc);
                if (cc) { RunConn(cc, start); return; }
            }
            DLog(@"no usable connection for %@", target);
            BroadcastState();
        });
    });
}

static void ConnectTunnel(void)    { DoSession(1); }
static void DisconnectTunnel(void) { DoSession(0); }

// Universal "is any VPN active right now" (the status-bar rectangle icon).
static BOOL AnyVPNActive(void) {
    if (_ne_any_active) return _ne_any_active() != 0;
    return NO;
}

static void BroadcastState(void) {
    if (g_mode == 2) Post(ST_AUTO);
    else if (StatusUp(g_connected)) Post(ST_VPN);
    else Post(ST_OFF);
}

#pragma mark - memorystatus / AUTO

// Generic name heuristic to protect any VPN-related process from jetsam.
static BOOL VPNishName(const char *n) {
    if (!n || !*n) return NO;
    NSString *s = [NSString stringWithUTF8String:n];
    NSArray *kw = @[@"nesessionmanager", @"neagent", @"networkextension",
                    @"packettunnel", @"nepackettunnel", @"vpn", @"tunnel",
                    @"ipsec", @"racoon", @"quantumult", @"wireguard", @"openvpn",
                    @"amnezia", @"adguard", @"shadowsocks", @"trojan",
                    @"sing-box", @"xray", @"surge", @"shadowrocket", @"passepartout"];
    NSString *low = s.lowercaseString;
    for (NSString *k in kw) if ([low containsString:k]) return YES;
    return NO;
}

// Raise (remove) the jetsam task limit on VPN processes so they survive memory
// pressure. Never kills an active VPN — only protects it.
static void LiftVPNPriorities(void) {
    int n = proc_listallpids(NULL, 0);
    if (n <= 0) return;
    int *pids = (int *)malloc(sizeof(int) * n);
    int got = proc_listallpids(pids, n);
    int lifted = 0;
    for (int i = 0; i < got; i++) {
        char name[64] = {0};
        proc_name(pids[i], name, sizeof(name));
        if (VPNishName(name)) {
            int r = memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT, pids[i], 0, NULL, 0);
            DLog(@"lift jetsam pid=%d name=%s r=%d", pids[i], name, r);
            lifted++;
        }
    }
    free(pids);
    if (lifted) DLog(@"lifted %d vpn-related processes", lifted);
}

// Periodic status sync. Runs ALWAYS so the tile tracks the real VPN state
// even when toggled from outside this tweak. The keep-alive actions (jetsam
// lift + auto-reconnect) only fire in AUTO mode (g_mode == 2).
static void StatusTick(void) {
    BOOL any = AnyVPNActive();
    g_connected = any ? kNEVPNConnected : kNEVPNDisconnected;
    DLog(@"status tick mode=%d anyActive=%d", g_mode, any);
    if (g_mode == 2) {
        LiftVPNPriorities();
        if (!any) {
            DLog(@"auto: VPN down -> reconnect");
            LoadConfigs(^{
                SetActive(PickActive());
                if (g_active && !AnyVPNActive()) ConnectTunnel();
                g_connected = kNEVPNConnecting;
                BroadcastState();
            });
            return;
        }
    }
    BroadcastState();
}

static void StartStatusSync(void) {
    if (g_watchdog) [g_watchdog invalidate];
    g_watchdog = [NSTimer scheduledTimerWithTimeInterval:20.0 repeats:YES block:^(NSTimer *t) {
        StatusTick();
    }];
}

static void HandleTap(void) {
    DLog(@"cmd.tap");
    void (^work)(void) = ^{
        SetActive(PickActive());
        if (!g_active) { DLog(@"NO VPN CONFIG - nothing to toggle"); Post(ST_OFF); return; }
        BOOL up = AnyVPNActive();
        DLog(@"active=%@ up=%d", CfgName(g_active), up);
        if (g_mode == 2) {
            g_mode = 0;
            DisconnectTunnel();
            g_connected = kNEVPNDisconnected;
        } else if (up) {
            DisconnectTunnel();
            g_connected = kNEVPNDisconnected;
            g_mode = 0;
        } else {
            ConnectTunnel();
            g_connected = kNEVPNConnecting;
            g_mode = 1;
        }
        BroadcastState();
    };
    LoadConfigs(work);
}

static void HandleLongPress(void) {
    DLog(@"cmd.longpress");
    if (g_mode == 2) {
        g_mode = (AnyVPNActive() ? 1 : 0);
        DLog(@"AUTO off, mode=%d", g_mode);
        LoadConfigs(^{ SetActive(PickActive()); g_connected = AnyVPNActive() ? kNEVPNConnected : kNEVPNDisconnected; BroadcastState(); });
    } else {
        g_mode = 2;
        LoadConfigs(^{
            SetActive(PickActive());
            if (g_active) {
                if (!AnyVPNActive()) ConnectTunnel();
                g_connected = AnyVPNActive() ? kNEVPNConnected : kNEVPNConnecting;
            }
            LiftVPNPriorities();
            BroadcastState();
        });
        DLog(@"AUTO on (keep-alive active)");
    }
}

#pragma mark - Darwin dispatch

static void OnCmd(CFNotificationCenterRef center, void *observer,
                  CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    if (CFEqual(name, CMD_TAP)) HandleTap();
    else if (CFEqual(name, CMD_LONG)) HandleLongPress();
    else if (CFEqual(name, CMD_QUERY)) {
        LoadConfigs(^{ SetActive(PickActive()); g_connected = AnyVPNActive() ? kNEVPNConnected : kNEVPNDisconnected; BroadcastState(); });
    }
}

#pragma mark - main

int main(int argc, char **argv) {
    @autoreleasepool {
        int r = memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT, getpid(), 0, NULL, 0);
        DLog(@"ccvpnd start pid=%d self-lift=%d", getpid(), r);

        LoadNELib();

        CFNotificationCenterRef dc = CFNotificationCenterGetDarwinNotifyCenter();
        CFNotificationCenterAddObserver(dc, NULL, OnCmd, CMD_TAP, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(dc, NULL, OnCmd, CMD_LONG, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(dc, NULL, OnCmd, CMD_QUERY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);

        LoadConfigs(^{
            DLog(@"completion A: configs=%lu", (unsigned long)g_configs.count);
            id a = nil;
            @try {
                DLog(@"completion A1: probing status...");
                a = PickActive();
                DLog(@"completion A2: pick done");
            } @catch (id e) { DLog(@"completion: PickActive threw %@", e); }
            DLog(@"completion B: picked %@", a ? CfgName(a) : @"(nil)");
            @try { SetActive(a); } @catch (id e) { DLog(@"completion: SetActive threw %@", e); }
            DLog(@"completion C: setactive done, calling anyvpn");
            BOOL any = NO;
            @try { any = AnyVPNActive(); } @catch (id e) { DLog(@"completion: AnyVPNActive threw %@", e); }
            DLog(@"completion D: any=%d", any);
            g_connected = any ? kNEVPNConnected : kNEVPNDisconnected;
            BroadcastState();
            DLog(@"completion E: broadcast done");
        });

        StartStatusSync();
        DLog(@"ccvpnd running, status sync started");
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
