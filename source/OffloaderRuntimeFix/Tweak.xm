#import <Foundation/Foundation.h>

static NSString *const OffloaderPreferencesDomain =
    @"com.level3tjg.offloaderprefs";

@interface SBIconView : NSObject
- (NSArray *)applicationShortcutItems;
- (NSArray *)effectiveApplicationShortcutItems;
- (NSArray *)fetchedApplicationShortcutItems;
- (id)_contextMenuInteraction:(id)interaction
    overrideSuggestedActionsForConfiguration:(id)configuration;
- (id)icon;
@end

@interface SBApplicationIcon : NSObject
- (BOOL)hasApplicationPlaceholder;
@end

static BOOL OffloaderPreferenceEnabled(NSString *key) {
    NSUserDefaults *preferences =
        [[NSUserDefaults alloc] initWithSuiteName:OffloaderPreferencesDomain];
    id value = [preferences objectForKey:key];
    return value ? [preferences boolForKey:key] : YES;
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

static BOOL OffloaderIconIsPlaceholder(SBIconView *iconView) {
    id icon = [iconView icon];
    return [icon isKindOfClass:NSClassFromString(@"SBApplicationIcon")] &&
        [icon respondsToSelector:@selector(hasApplicationPlaceholder)] &&
        [(SBApplicationIcon *)icon hasApplicationPlaceholder];
}

static NSArray *OffloaderRemoveOffloadAction(NSArray *items) {
    if (![items isKindOfClass:NSArray.class] || items.count == 0) {
        return items;
    }

    NSMutableArray *filteredItems = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        NSString *type = OffloaderStringProperty(item, @selector(type));
        if (![type isEqualToString:@"com.level3tjg.offloader/offload"]) {
            [filteredItems addObject:item];
        }
    }
    return filteredItems;
}

static NSArray *OffloaderFilteredItems(id items) {
    if (![items isKindOfClass:NSArray.class] || [items count] == 0) {
        return items;
    }
    NSArray *array = items;

    BOOL showDelete = OffloaderPreferenceEnabled(@"3ddelete");
    BOOL showEdit = OffloaderPreferenceEnabled(@"3dedit");
    if (showDelete && showEdit) {
        return array;
    }

    NSMutableArray *filteredItems = [NSMutableArray arrayWithCapacity:array.count];
    for (id item in array) {
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
    if (OffloaderIconIsPlaceholder(self)) {
        return OffloaderRemoveOffloadAction(
            [self fetchedApplicationShortcutItems] ?: @[]);
    }
    return OffloaderFilteredItems(%orig);
}

- (NSArray *)effectiveApplicationShortcutItems {
    NSArray *items = %orig;
    return OffloaderIconIsPlaceholder(self)
        ? OffloaderRemoveOffloadAction(items)
        : OffloaderFilteredItems(items);
}

- (id)_contextMenuInteraction:(id)interaction
    overrideSuggestedActionsForConfiguration:(id)configuration {
    id actions = %orig;
    return OffloaderIconIsPlaceholder(self)
        ? actions
        : OffloaderFilteredItems(actions);
}

%end
