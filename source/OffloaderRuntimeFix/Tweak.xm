#import <Foundation/Foundation.h>

static NSString *const OffloaderPreferencesPath =
    @"/var/mobile/Library/Preferences/com.level3tjg.offloaderprefs.plist";

@interface SBIconView : NSObject
- (NSArray *)applicationShortcutItems;
@end

static BOOL OffloaderPreferenceEnabled(NSString *key) {
    NSDictionary *preferences =
        [NSDictionary dictionaryWithContentsOfFile:OffloaderPreferencesPath];
    id value = preferences[key];
    return value ? [value boolValue] : YES;
}

static BOOL OffloaderIsSystemShortcut(id item, NSString *type) {
    SEL selector = @selector(sbh_isSystemShortcut);
    if ([item respondsToSelector:selector]) {
        BOOL (*implementation)(id, SEL) =
            (BOOL (*)(id, SEL))[item methodForSelector:selector];
        return implementation(item, selector);
    }

    return [type hasPrefix:@"com.apple.springboardhome.application-shortcut-item."];
}

static BOOL OffloaderMatchesDeleteShortcut(NSString *type, NSString *title) {
    return [type containsString:@"remove-app"] ||
        [type containsString:@"delete-app"] ||
        [type containsString:@"uninstall"] ||
        [title containsString:@"delete app"] ||
        [title containsString:@"remove app"] ||
        [title containsString:@"удалить приложение"];
}

static BOOL OffloaderMatchesEditShortcut(NSString *type, NSString *title) {
    return [type containsString:@"rearrange-icons"] ||
        [type containsString:@"edit-home-screen"] ||
        [title containsString:@"edit home screen"] ||
        ([title containsString:@"изменить экран"] &&
         [title containsString:@"домой"]);
}

%hook SBIconView

- (NSArray *)applicationShortcutItems {
    NSArray *items = %orig;
    if (items.count == 0) {
        return items;
    }

    BOOL showDelete = OffloaderPreferenceEnabled(@"3ddelete");
    BOOL showEdit = OffloaderPreferenceEnabled(@"3dedit");
    if (showDelete && showEdit) {
        return items;
    }

    NSMutableArray *filteredItems = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        NSString *type = nil;
        NSString *title = nil;

        if ([item respondsToSelector:@selector(type)]) {
            type = [[item performSelector:@selector(type)] lowercaseString];
        }
        if ([item respondsToSelector:@selector(localizedTitle)]) {
            title = [[item performSelector:@selector(localizedTitle)] lowercaseString];
        }

        BOOL isSystemShortcut = OffloaderIsSystemShortcut(item, type ?: @"");
        BOOL shouldHide =
            isSystemShortcut &&
            ((!showDelete && OffloaderMatchesDeleteShortcut(type ?: @"", title ?: @"")) ||
             (!showEdit && OffloaderMatchesEditShortcut(type ?: @"", title ?: @"")));

        if (!shouldHide) {
            [filteredItems addObject:item];
        }
    }

    return filteredItems;
}

%end
