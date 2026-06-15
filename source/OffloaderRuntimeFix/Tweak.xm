#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <mach-o/dyld.h>
#import <string.h>

static NSString *const OffloaderPreferencesDomain =
    @"com.level3tjg.offloaderprefs";

typedef id (*OffloaderVanillaNoArgumentFunction)(id receiver);
typedef id (*OffloaderVanillaOverrideFunction)(id receiver,
                                                id interaction,
                                                id configuration);

static void *OffloaderVanillaCaptureHandle;

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

@interface SBWidgetIcon : NSObject
- (BOOL)isWidgetIcon;
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

static BOOL OffloaderMatchesOffloadAction(NSString *type) {
    return [type isEqualToString:@"com.level3tjg.offloader/offload"];
}

static BOOL OffloaderIconIsPlaceholder(SBIconView *iconView) {
    id icon = [iconView icon];
    return [icon isKindOfClass:NSClassFromString(@"SBApplicationIcon")] &&
        [icon respondsToSelector:@selector(hasApplicationPlaceholder)] &&
        [(SBApplicationIcon *)icon hasApplicationPlaceholder];
}

static BOOL OffloaderIconIsFolder(SBIconView *iconView) {
    return [[iconView icon] isKindOfClass:NSClassFromString(@"SBFolderIcon")];
}

static BOOL OffloaderIconIsWidget(SBIconView *iconView) {
    id icon = [iconView icon];
    return [icon isKindOfClass:NSClassFromString(@"SBWidgetIcon")] ||
        ([icon respondsToSelector:@selector(isWidgetIcon)] &&
         [(SBWidgetIcon *)icon isWidgetIcon]);
}

static BOOL OffloaderIconNeedsVanillaMenu(SBIconView *iconView) {
    return OffloaderIconIsFolder(iconView) ||
        OffloaderIconIsPlaceholder(iconView) ||
        OffloaderIconIsWidget(iconView);
}

static void *OffloaderVanillaCaptureSymbol(const char *name) {
    if (!OffloaderVanillaCaptureHandle) {
        uint32_t imageCount = _dyld_image_count();
        for (uint32_t index = 0; index < imageCount; index++) {
            const char *path = _dyld_get_image_name(index);
            if (path && strstr(path, "/AOffloaderVanillaCapture.dylib")) {
                OffloaderVanillaCaptureHandle =
                    dlopen(path, RTLD_NOW | RTLD_GLOBAL);
                break;
            }
        }
    }

    return OffloaderVanillaCaptureHandle
        ? dlsym(OffloaderVanillaCaptureHandle, name)
        : NULL;
}

static OffloaderVanillaNoArgumentFunction
OffloaderVanillaNoArgumentSymbol(const char *name) {
    return (OffloaderVanillaNoArgumentFunction)
        OffloaderVanillaCaptureSymbol(name);
}

static OffloaderVanillaOverrideFunction
OffloaderVanillaOverrideSymbol(void) {
    return (OffloaderVanillaOverrideFunction)
        OffloaderVanillaCaptureSymbol(
            "OffloaderCallVanillaOverrideSuggestedActions");
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

    BOOL showOffload = OffloaderPreferenceEnabled(@"3doffload");
    BOOL showDelete = OffloaderPreferenceEnabled(@"3ddelete");
    BOOL showEdit = OffloaderPreferenceEnabled(@"3dedit");
    if (showOffload && showDelete && showEdit) {
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
            (!showOffload && OffloaderMatchesOffloadAction(type)) ||
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
    if (OffloaderIconNeedsVanillaMenu(self)) {
        OffloaderVanillaNoArgumentFunction function =
            OffloaderVanillaNoArgumentSymbol(
                "OffloaderCallVanillaApplicationShortcutItems");
        if (function) {
            return function(self);
        }
        return OffloaderIconIsPlaceholder(self)
            ? OffloaderRemoveOffloadAction(
                [self fetchedApplicationShortcutItems] ?: @[])
            : @[];
    }
    return OffloaderFilteredItems(%orig);
}

- (NSArray *)effectiveApplicationShortcutItems {
    if (OffloaderIconNeedsVanillaMenu(self)) {
        OffloaderVanillaNoArgumentFunction function =
            OffloaderVanillaNoArgumentSymbol(
                "OffloaderCallVanillaEffectiveShortcutItems");
        return function ? function(self) : @[];
    }
    NSArray *items = %orig;
    return OffloaderFilteredItems(items);
}

- (id)_contextMenuInteraction:(id)interaction
    overrideSuggestedActionsForConfiguration:(id)configuration {
    if (OffloaderIconNeedsVanillaMenu(self)) {
        OffloaderVanillaOverrideFunction function =
            OffloaderVanillaOverrideSymbol();
        return function
            ? function(self, interaction, configuration)
            : @[];
    }
    id actions = %orig;
    return OffloaderFilteredItems(actions);
}

%end
