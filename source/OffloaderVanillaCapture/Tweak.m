#import <Foundation/Foundation.h>
#import <objc/runtime.h>

typedef id (*OffloaderNoArgumentIMP)(id, SEL);
typedef id (*OffloaderOverrideActionsIMP)(id, SEL, id, id);

static OffloaderNoArgumentIMP OffloaderApplicationShortcutItemsIMP;
static OffloaderNoArgumentIMP OffloaderEffectiveShortcutItemsIMP;
static OffloaderOverrideActionsIMP OffloaderOverrideSuggestedActionsIMP;

__attribute__((visibility("default")))
id OffloaderCallVanillaApplicationShortcutItems(id receiver) {
    return OffloaderApplicationShortcutItemsIMP
        ? OffloaderApplicationShortcutItemsIMP(
            receiver, @selector(applicationShortcutItems))
        : nil;
}

__attribute__((visibility("default")))
id OffloaderCallVanillaEffectiveShortcutItems(id receiver) {
    return OffloaderEffectiveShortcutItemsIMP
        ? OffloaderEffectiveShortcutItemsIMP(
            receiver, @selector(effectiveApplicationShortcutItems))
        : nil;
}

__attribute__((visibility("default")))
id OffloaderCallVanillaOverrideSuggestedActions(id receiver,
                                                 id interaction,
                                                 id configuration) {
    return OffloaderOverrideSuggestedActionsIMP
        ? OffloaderOverrideSuggestedActionsIMP(
            receiver,
            @selector(_contextMenuInteraction:
                overrideSuggestedActionsForConfiguration:),
            interaction,
            configuration)
        : nil;
}

__attribute__((constructor))
static void OffloaderCaptureVanillaImplementations(void) {
    Class iconViewClass = NSClassFromString(@"SBIconView");
    if (!iconViewClass) {
        return;
    }

    OffloaderApplicationShortcutItemsIMP =
        (OffloaderNoArgumentIMP)class_getMethodImplementation(
            iconViewClass, @selector(applicationShortcutItems));
    OffloaderEffectiveShortcutItemsIMP =
        (OffloaderNoArgumentIMP)class_getMethodImplementation(
            iconViewClass, @selector(effectiveApplicationShortcutItems));
    OffloaderOverrideSuggestedActionsIMP =
        (OffloaderOverrideActionsIMP)class_getMethodImplementation(
            iconViewClass,
            @selector(_contextMenuInteraction:
                overrideSuggestedActionsForConfiguration:));
}
