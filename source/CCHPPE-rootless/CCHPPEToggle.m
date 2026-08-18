#import "CCHPPEToggle.h"

// CCHPPE — a Control Center toggle that enables/disables HPPE, mirroring the
// AlbumManager CC toggle. It writes the HPPE `Enabled` preference and posts the
// Darwin notification the tweak already observes (HPPEPrefsChangedCallback), so
// every injected process reloads its prefs live. No killall is needed: a picker
// reads the fresh state the next time it opens, and the system picker appex
// respawns per use. Runs inside SpringBoard (where Control Center lives).

static NSString * const kHPPEPrefsDomain = @"com.ratush.hppe";
static NSString * const kHPPEPrefsPath =
    @"/var/mobile/Library/Preferences/com.ratush.hppe.plist";
static NSString * const kHPPEPrefsChangedNotification =
    @"com.ratush.hppe.preferenceupdate";
static NSString * const kHPPEEnabledKey = @"Enabled";

@implementation CCHPPEToggle

- (UIImage *)iconGlyph {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:25
                                                        weight:UIImageSymbolWeightMedium
                                                         scale:UIImageSymbolScaleLarge];
    return [UIImage systemImageNamed:@"eye.slash" withConfiguration:cfg];
}

- (UIImage *)selectedIconGlyph {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:25
                                                        weight:UIImageSymbolWeightMedium
                                                         scale:UIImageSymbolScaleLarge];
    return [UIImage systemImageNamed:@"eye" withConfiguration:cfg];
}

- (UIColor *)selectedColor {
    return [UIColor systemPurpleColor];
}

- (BOOL)isHPPEEnabled {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kHPPEPrefsPath];
    id fileValue = prefs[kHPPEEnabledKey];
    if ([fileValue respondsToSelector:@selector(boolValue)]) {
        return [fileValue boolValue];
    }
    BOOL result = YES;   // HPPE's own default for Enabled is YES.
    CFPropertyListRef cf = CFPreferencesCopyAppValue(
        (__bridge CFStringRef)kHPPEEnabledKey, (__bridge CFStringRef)kHPPEPrefsDomain);
    if (cf) {
        if (CFGetTypeID(cf) == CFBooleanGetTypeID()) {
            result = CFBooleanGetValue((CFBooleanRef)cf);
        }
        CFRelease(cf);
    }
    return result;
}

- (BOOL)isSelected {
    return [self isHPPEEnabled];
}

- (void)setSelected:(BOOL)selected {
    NSMutableDictionary *prefs =
        [[NSDictionary dictionaryWithContentsOfFile:kHPPEPrefsPath] mutableCopy] ?:
        [NSMutableDictionary dictionary];
    prefs[kHPPEEnabledKey] = @(selected);
    [prefs writeToFile:kHPPEPrefsPath atomically:YES];
    CFPreferencesSetAppValue((__bridge CFStringRef)kHPPEEnabledKey,
                             (__bridge CFPropertyListRef)@(selected),
                             (__bridge CFStringRef)kHPPEPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kHPPEPrefsDomain);

    // cfprefsd-immune sentinel: the tweak reads ".hppe-Enabled" AUTHORITATIVELY
    // (HPPEReadBoolSentinel) and only falls back to the plist when it is absent.
    // The Settings controller writes this file on every toggle, so if the CC tile
    // wrote ONLY the plist a stale sentinel would override it and the tile would
    // appear to do nothing. Write the same rootless sentinel here.
    NSString *sentinelName = [@".hppe-" stringByAppendingString:kHPPEEnabledKey];
    NSString *sentinelVal = selected ? @"1" : @"0";
    for (NSString *dir in @[@"/var/mobile/Library/Preferences"]) {
        NSString *sp = [dir stringByAppendingPathComponent:sentinelName];
        [sentinelVal writeToFile:sp atomically:YES
                        encoding:NSUTF8StringEncoding error:nil];
    }

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)kHPPEPrefsChangedNotification,
        NULL, NULL, YES);

    [super refreshState];
}

@end
