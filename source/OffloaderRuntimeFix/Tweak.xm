#import <Foundation/Foundation.h>

static NSString *const OffloaderPreferencesPath =
    @"/var/mobile/Library/Preferences/com.level3tjg.offloaderprefs.plist";

@interface SBIconView : NSObject
- (NSArray *)applicationShortcutItems;
- (NSArray *)effectiveApplicationShortcutItems;
- (NSArray *)_contextMenuInteraction:(id)interaction
    overrideSuggestedActionsForConfiguration:(id)configuration;
@end

static BOOL OffloaderPreferenceEnabled(NSString *key) {
    NSDictionary *preferences =
        [NSDictionary dictionaryWithContentsOfFile:OffloaderPreferencesPath];
    id value = preferences[key];
    return value ? [value boolValue] : YES;
}

static BOOL OffloaderBooleanSelector(id item, SEL selector) {
    if ([item respondsToSelector:selector]) {
        BOOL (*implementation)(id, SEL) =
            (BOOL (*)(id, SEL))[item methodForSelector:selector];
        return implementation(item, selector);
    }
    return NO;
}

static NSString *OffloaderStringProperty(id item, SEL selector) {
    if (![item respondsToSelector:selector]) {
        return @"";
    }

    id (*implementation)(id, SEL) =
        (id (*)(id, SEL))[item methodForSelector:selector];
    id value = implementation(item, selector);
    if ([value isKindOfClass:NSString.class]) {
        return [value lowercaseString];
    }
    return value ? [[value description] lowercaseString] : @"";
}

static BOOL OffloaderMatchesDeleteAction(id item,
                                          NSString *type,
                                          NSString *title) {
    return OffloaderBooleanSelector(item, @selector(sbh_isShortcutDeleteOrRemove)) ||
        [type containsString:@"remove-app"] ||
        [type containsString:@"delete-app"] ||
        [type containsString:@"uninstall"] ||
        [type containsString:@"deleteapplication"] ||
        [type containsString:@"removeapplication"] ||
        [title containsString:@"delete app"] ||
        [title containsString:@"remove app"] ||
        [title containsString:@"удалить приложение"];
}

static BOOL OffloaderMatchesEditAction(NSString *type, NSString *title) {
    return [type containsString:@"rearrange-icons"] ||
        [type containsString:@"edit-home-screen"] ||
        [type containsString:@"edithomescreen"] ||
        [type containsString:@"rearrangeicons"] ||
        [title containsString:@"edit home screen"] ||
        ([title containsString:@"изменить экран"] &&
         [title containsString:@"домой"]);
}

static NSArray *OffloaderFilteredItems(NSArray *items) {
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
        NSString *type = OffloaderStringProperty(item, @selector(type));
        if (type.length == 0) {
            type = OffloaderStringProperty(item, @selector(identifier));
        }

        NSString *title = OffloaderStringProperty(item, @selector(localizedTitle));
        if (title.length == 0) {
            title = OffloaderStringProperty(item, @selector(title));
        }

        BOOL shouldHide =
            (!showDelete && OffloaderMatchesDeleteAction(item, type, title)) ||
            (!showEdit && OffloaderMatchesEditAction(type, title));

        if (!shouldHide) {
            [filteredItems addObject:item];
        }
    }

    return filteredItems;
}

%hook SBIconView

- (NSArray *)applicationShortcutItems {
    return OffloaderFilteredItems(%orig);
}

- (NSArray *)effectiveApplicationShortcutItems {
    return OffloaderFilteredItems(%orig);
}

- (NSArray *)_contextMenuInteraction:(id)interaction
    overrideSuggestedActionsForConfiguration:(id)configuration {
    return OffloaderFilteredItems(%orig);
}

%end
