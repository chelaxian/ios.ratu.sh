#import <Foundation/Foundation.h>
#define ASV_DOMAIN @"com.ratush.appsplitvpn"
#define ASV_PREFS @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.plist"
#define ASV_STATE @"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.state.plist"
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
