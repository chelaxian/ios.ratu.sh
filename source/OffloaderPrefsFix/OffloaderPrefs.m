#import <Foundation/Foundation.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import "ATLApplicationListMultiSelectionController.h"

static NSString *const OffAntiOffloadPath =
    @"/var/mobile/Library/Preferences/com.level3tjg.offloader.anti.plist";
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

- (NSString *)applicationIdentifierForSpecifier:(PSSpecifier *)specifier {
    id value = [specifier propertyForKey:@"applicationID"];
    if (![value isKindOfClass:NSString.class] || [value length] == 0) {
        value = [specifier propertyForKey:@"applicationIdentifier"];
    }
    return [value isKindOfClass:NSString.class] ? value : nil;
}

- (id)readApplicationEnabled:(PSSpecifier *)specifier {
    NSString *applicationID = [self applicationIdentifierForSpecifier:specifier];
    NSDictionary *preferences = [NSDictionary dictionaryWithContentsOfFile:OffAntiOffloadPath];
    return @([preferences[applicationID] boolValue]);
}

- (void)setApplicationEnabled:(NSNumber *)enabled specifier:(PSSpecifier *)specifier {
    NSString *applicationID = [self applicationIdentifierForSpecifier:specifier];
    if (applicationID.length == 0) {
        return;
    }

    NSMutableDictionary *preferences =
        [[NSDictionary dictionaryWithContentsOfFile:OffAntiOffloadPath] mutableCopy];
    if (!preferences) {
        preferences = [NSMutableDictionary dictionary];
    }

    if (enabled.boolValue) {
        preferences[applicationID] = @YES;
    } else {
        [preferences removeObjectForKey:applicationID];
    }

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
