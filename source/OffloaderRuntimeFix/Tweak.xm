#import <Foundation/Foundation.h>

static NSString *const OffloaderPreferencesDomain =
    @"com.level3tjg.offloaderprefs";

@interface SBIconView : NSObject
- (NSArray *)applicationShortcutItems;
- (NSArray *)effectiveApplicationShortcutItems;
- (id)_contextMenuInteraction:(id)interaction
    overrideSuggestedActionsForConfiguration:(id)configuration;
- (NSString *)applicationBundleIdentifierForShortcuts;
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
    NSString *bundleIdentifier =
        [iconView applicationBundleIdentifierForShortcuts];
    if (bundleIdentifier.length == 0) {
        return NO;
    }

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultWorkspaceSelector = NSSelectorFromString(@"defaultWorkspace");
    SEL placeholdersSelector = NSSelectorFromString(@"placeholderApplications");
    if (![workspaceClass respondsToSelector:defaultWorkspaceSelector]) {
        return NO;
    }

    id (*sendClassMessage)(id, SEL) =
        (id (*)(id, SEL))[workspaceClass methodForSelector:defaultWorkspaceSelector];
    id workspace = sendClassMessage(workspaceClass, defaultWorkspaceSelector);
    if (![workspace respondsToSelector:placeholdersSelector]) {
        return NO;
    }

    id (*sendMessage)(id, SEL) =
        (id (*)(id, SEL))[workspace methodForSelector:placeholdersSelector];
    NSArray *placeholders = sendMessage(workspace, placeholdersSelector);
    for (id application in placeholders) {
        NSString *candidate =
            OffloaderStringProperty(application, @selector(bundleIdentifier));
        if ([candidate isEqualToString:bundleIdentifier.lowercaseString]) {
            return YES;
        }
    }

    return NO;
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
    NSArray *items = %orig;
    return OffloaderIconIsPlaceholder(self)
        ? OffloaderRemoveOffloadAction(items)
        : OffloaderFilteredItems(items);
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
