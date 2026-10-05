#import <Foundation/Foundation.h>
#import <notify.h>
#define RPStatus @"/var/mobile/Library/Preferences/com.ratush.daemonpresets.status.plist"
#define RPCatalog @"/var/jb/usr/share/ratu-daemon-presets/catalog.plist"
#define RPPrivate @"/var/jb/var/lib/ratu-daemon-presets/state.plist"
#define RPPrefix @"com.ratush.daemonpresets.cmd."
#define RPRequest @"/var/mobile/Library/Preferences/com.ratush.daemonpresets.request.plist"
static inline NSDictionary *Catalog(void) { return [NSDictionary dictionaryWithContentsOfFile:RPCatalog] ?: @{}; }
static inline NSDictionary *Status(void) { return [NSDictionary dictionaryWithContentsOfFile:RPStatus] ?: @{}; }
static inline void Command(NSString *c) { notify_post([[RPPrefix stringByAppendingString:c] UTF8String]); }
static inline NSArray *Presets(void) {
    NSMutableArray *a=[Catalog()[@"presets"] mutableCopy]?:[NSMutableArray array];
    [a addObjectsFromArray:Status()[@"userPresets"]?:@[]];return a;
}
