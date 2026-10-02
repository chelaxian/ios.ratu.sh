#import <Foundation/Foundation.h>
#define ASV_DOMAIN @"com.ratush.appsplitvpn"
#define ASV_PREFS @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.plist"
#define ASV_STATE @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.state.plist"
#define ASV_IP_REFRESH_NOTIFY "com.ratush.appsplitvpn.refresh-ip"
#define ASV_LOG @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.log.plist"
#define ASV_ROUTE_LOG @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.routes.plist"
#define ASV_NOTIFY "com.ratush.appsplitvpn.changed"
#define ASV_CMD_TOGGLE "com.ratush.appsplitvpn.toggle"
// Explicit enable/disable from Control Center: notify state 1 = on, 2 = off.
// Unlike a toggle, repeated or coalesced posts cannot flip the switch twice.
#define ASV_CMD_SET "com.ratush.appsplitvpn.set"
#define ASV_STATE_NOTIFY "com.ratush.appsplitvpn.state.changed"
// The two selection arrays persist independently. Only the current mode is evaluated.
#define ASV_VPN @"vpnApps"
#define ASV_DIRECT @"directApps"
#define ASV_MATRIX @"vpnMatrix"
#define ASV_PROFILE_CATALOG @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.profiles.plist"
#define ASV_PROFILES_NOTIFY "com.ratush.appsplitvpn.profiles.changed"
#define ASV_REDUNDANCY @"redundancy"
#define ASV_RESERVES @"reserveProfiles"
#define ASV_RED_ALGORITHM @"redundancyAlgorithm"
#define ASV_HC_TIMEOUT @"hcTimeout"
#define ASV_DEFAULT_HC_TIMEOUT 15

// The single-profile supervisor must never act on MULTI VPN sessions.
// Keep inactive preferences intact so returning to a mode restores its setup.
static inline BOOL ASVIsMultiMode(NSDictionary *prefs) {
    return [prefs[@"mode"] isEqual:@"multiVPN"];
}
static inline BOOL ASVExtraOptionActive(NSDictionary *prefs, NSString *key) {
    return [prefs[@"enabled"] boolValue] && !ASVIsMultiMode(prefs) && [prefs[key] boolValue];
}

// Extra options (0.3.0). They act on the system VPN selected in iOS Settings and
// are all gated by the global Enable switch; their preferences remain saved.
#define ASV_EXTRA_STATE @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.extra.plist"
#define ASV_EXTRA_NOTIFY "com.ratush.appsplitvpn.extra.changed"
// Event journal of the extra options (newest last) and the request to clear it.
#define ASV_EXTRA_LOG @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.events.plist"
#define ASV_EXTRA_CLEAR "com.ratush.appsplitvpn.events.clear"
#define ASV_EXTRA_LOG_LIMIT 300
#define ASV_LS_DISCONNECT @"lsDisconnect"
#define ASV_ALWAYS_ON @"alwaysOn"
#define ASV_HEALTH @"healthCheck"
#define ASV_LS_DELAY @"lsDelay"
#define ASV_LS_MEDIA @"lsKeepMedia"
// SpringBoard's UI lock state: bit 1 valid, bit 0 locked. No control commands.
#define ASV_UI_LOCK_NOTIFY "com.ratush.appsplitvpn.ui-lock"
#define ASV_MULTI_DIR @"/var/jb/var/lib/appsplitvpn"
#define ASV_MULTI_MANIFEST @"/var/jb/var/lib/appsplitvpn/multi-manifest.plist"
#define ASV_MULTI_COMPAT_READY "com.ratush.appsplitvpn.multi-compat.ready"
#define ASV_HC_METHOD @"hcMethod"
#define ASV_HC_TARGET @"hcTarget"
#define ASV_HC_PORT @"hcPort"
#define ASV_HC_INTERVAL @"hcInterval"
#define ASV_HC_FAILURES @"hcFailures"
#define ASV_IP_SERVICE @"ipService"
#define ASV_DEFAULT_LS_DELAY 5
#define ASV_DEFAULT_HC_METHOD @"https"
#define ASV_DEFAULT_HC_TARGET @"cp.cloudflare.com"
#define ASV_DEFAULT_HC_INTERVAL 60
#define ASV_DEFAULT_HC_FAILURES 3
#define ASV_DEFAULT_IP_SERVICE @"https://www.cloudflare.com/cdn-cgi/trace"
#define ASV_FALLBACK_IP_SERVICE @"https://ipv4-internet.yandex.net/api/v0/ip"

// Clamped integer setting shared by the service and the settings page.
static inline NSInteger ASVIntSetting(NSDictionary *prefs, NSString *key, NSInteger fallback, NSInteger low, NSInteger high) {
    id value=prefs[key];
    if (![value respondsToSelector:@selector(integerValue)] || ([value isKindOfClass:NSString.class] && ![value length])) return fallback;
    return MIN(high,MAX(low,[value integerValue]));
}
static inline NSString *ASVHealthMethod(NSDictionary *prefs) {
    NSString *method=prefs[ASV_HC_METHOD];
    return [@[@"https",@"http",@"tcp",@"ping"] containsObject:method] ? method : ASV_DEFAULT_HC_METHOD;
}
static inline BOOL ASVValidHost(NSString *host) {
    if (![host isKindOfClass:NSString.class] || !host.length || host.length>253) return NO;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:"];
    return [host rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound;
}
static inline NSString *ASVHealthTarget(NSDictionary *prefs) {
    NSString *host=[prefs[ASV_HC_TARGET] isKindOfClass:NSString.class] ? [prefs[ASV_HC_TARGET] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : nil;
    return ASVValidHost(host) ? host : ASV_DEFAULT_HC_TARGET;
}
static inline NSInteger ASVHealthPort(NSDictionary *prefs) {
    NSInteger port=ASVIntSetting(prefs,ASV_HC_PORT,0,0,65535);
    if (port>0) return port;
    return [ASVHealthMethod(prefs) isEqual:@"http"] ? 80 : 443;
}
static inline NSString *ASVIPService(NSDictionary *prefs) {
    NSString *url=[prefs[ASV_IP_SERVICE] isKindOfClass:NSString.class] ? [prefs[ASV_IP_SERVICE] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] : nil;
    NSURL *parsed=url.length ? [NSURL URLWithString:url] : nil;
    return ([parsed.scheme isEqual:@"https"] || [parsed.scheme isEqual:@"http"]) && parsed.host.length ? url : ASV_DEFAULT_IP_SERVICE;
}
