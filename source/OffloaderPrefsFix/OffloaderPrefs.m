#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "ATLApplicationListMultiSelectionController.h"

static NSString *const OffAntiOffloadPath =
    @"/var/mobile/Library/Preferences/com.level3tjg.offloader.anti.plist";
static NSString *const OffAntiOffloadDomain =
    @"com.level3tjg.offloader.anti";
static CFStringRef const OffSettingsChanged =
    CFSTR("com.level3tjg.offloader/settings.changed");

@interface OffRootListController : PSListController
@end

@implementation OffRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

@end

@interface OffAntiOffloadListController : ATLApplicationListMultiSelectionController
@end

@implementation OffAntiOffloadListController

- (void)loadPreferences {
    NSDictionary *preferences = CFBridgingRelease(CFPreferencesCopyMultiple(
        NULL,
        (__bridge CFStringRef)OffAntiOffloadDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    ));
    NSMutableSet *selectedApplications = [NSMutableSet set];

    [preferences enumerateKeysAndObjectsUsingBlock:
        ^(id key, id value, BOOL *stop) {
        if ([key isKindOfClass:NSString.class] && [value boolValue]) {
            [selectedApplications addObject:key];
        }
    }];

    _selectedApplications = selectedApplications;
}

- (void)savePreferences {
    NSMutableDictionary *preferences = [NSMutableDictionary dictionary];
    for (id applicationID in _selectedApplications) {
        if ([applicationID isKindOfClass:NSString.class]) {
            preferences[applicationID] = @YES;
        }
    }

    NSDictionary *existingPreferences =
        CFBridgingRelease(CFPreferencesCopyMultiple(
            NULL,
            (__bridge CFStringRef)OffAntiOffloadDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        ));
    NSMutableArray *keysToRemove =
        [NSMutableArray arrayWithArray:existingPreferences.allKeys ?: @[]];
    [keysToRemove removeObjectsInArray:preferences.allKeys];

    CFPreferencesSetMultiple(
        (__bridge CFDictionaryRef)preferences,
        (__bridge CFArrayRef)keysToRemove,
        (__bridge CFStringRef)OffAntiOffloadDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    CFPreferencesSynchronize(
        (__bridge CFStringRef)OffAntiOffloadDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesAnyHost
    );
    [preferences writeToFile:OffAntiOffloadPath atomically:YES];

    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        OffSettingsChanged,
        NULL,
        NULL,
        true
    );
}

@end
