// Independent compatibility layer. No original AddToFolder code or binaries.
#import <UIKit/UIKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>

static NSString *const AFShortcutType = @"CustomAddToFolderItem";
static BOOL AFShowing, AFMoving;
static UIWindow *AFWindow;
static __weak UIWindow *AFPreviousKeyWindow;
static NSString *AFRecovery;

static void AFFail(NSString *message) {
    @throw [NSException exceptionWithName:@"AddToFolderFix" reason:message userInfo:nil];
}
static const char *AFType(const char *type) {
    while (*type && strchr("rnNoORV", *type)) type++;
    return type;
}
static id AFGet(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || sig.numberOfArguments != 2 ||
        !strchr("@#", *AFType(sig.methodReturnType))) return nil;
    return ((id (*)(id, SEL))objc_msgSend)(object, selector);
}
static id AFGet1(id object, NSString *name, id arg) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || sig.numberOfArguments != 3 ||
        *AFType([sig getArgumentTypeAtIndex:2]) != '@' ||
        !strchr("@#", *AFType(sig.methodReturnType))) return nil;
    return ((id (*)(id, SEL, id))objc_msgSend)(object, selector, arg);
}
static BOOL AFBoolean(id object, NSString *name) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    if (![object respondsToSelector:selector] || sig.numberOfArguments != 2 ||
        !strchr("Bc", *AFType(sig.methodReturnType))) return NO;
    return ((BOOL (*)(id, SEL))objc_msgSend)(object, selector);
}
static void AFInvoke(id object, NSString *name, NSArray *objects, BOOL options) {
    SEL selector = NSSelectorFromString(name);
    NSMethodSignature *sig = [object methodSignatureForSelector:selector];
    NSUInteger count = objects.count + (options ? 1 : 0) + 2;
    if (![object respondsToSelector:selector] || sig.numberOfArguments != count)
        AFFail([@"Unavailable SpringBoard API: " stringByAppendingString:name]);
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:sig];
    call.target = object; call.selector = selector;
    for (NSUInteger i = 0; i < objects.count; i++) {
        if (*AFType([sig getArgumentTypeAtIndex:i+2]) != '@') AFFail(@"Unexpected object argument ABI");
        id arg = objects[i] == NSNull.null ? nil : objects[i];
        [call setArgument:&arg atIndex:i+2];
    }
    if (options) {
        NSUInteger index = count - 1;
        const char *type = AFType([sig getArgumentTypeAtIndex:index]);
        if (!strchr("QqILilBc", *type)) AFFail(@"Unexpected options argument ABI");
        uint64_t zero = 0; [call setArgument:&zero atIndex:index];
    }
    [call invoke];
}
// insertIcon takes an IN/OUT index-path pointer on iOS 17. Never pass the
// NSIndexPath object as if this parameter were an ordinary object argument.
static void AFInsert(id folder, id icon, NSIndexPath *path) {
    SEL selector = NSSelectorFromString(@"insertIcon:atIndexPath:options:");
    NSMethodSignature *sig = [folder methodSignatureForSelector:selector];
    if (![folder respondsToSelector:selector] || sig.numberOfArguments != 5 ||
        *AFType([sig getArgumentTypeAtIndex:2]) != '@' ||
        !strchr("QqILil", *AFType([sig getArgumentTypeAtIndex:4]))) AFFail(@"Insertion API unavailable");
    NSInvocation *call = [NSInvocation invocationWithMethodSignature:sig];
    call.target = folder; call.selector = selector;
    [call setArgument:&icon atIndex:2];
    id __autoreleasing mutablePath = path;
    id __autoreleasing *pointer = &mutablePath;
    const char *type = AFType([sig getArgumentTypeAtIndex:3]);
    if (!strcmp(type, "^@")) [call setArgument:&pointer atIndex:3];
    else if (*type == '@') [call setArgument:&path atIndex:3];
    else AFFail(@"Unexpected index-path argument ABI");
    NSUInteger options = 0; [call setArgument:&options atIndex:4];
    [call invoke];
}
static id AFController(void) { return AFGet(NSClassFromString(@"SBIconController"), @"sharedInstance"); }
static id AFManager(void) { return AFGet(AFController(), @"iconManager"); }
static id AFModel(void) { return AFGet(AFController(), @"model"); }
static id AFRoot(void) { return AFGet(AFModel(), @"rootFolder"); }
static NSArray *AFArray(id value) { return [value isKindOfClass:NSArray.class] ? value : @[]; }
static NSString *AFIdentity(id icon) {
    id value = AFGet(icon, @"nodeIdentifier") ?: AFGet(icon, @"uniqueIdentifier");
    return [value isKindOfClass:NSString.class] && [value length] ? value : [NSString stringWithFormat:@"object:%p", icon];
}
static NSString *AFFolderID(id folder) {
    id value = AFGet(folder, @"uniqueIdentifier");
    return [value isKindOfClass:NSString.class] && [value length] ? value : AFIdentity(folder);
}
// Only folders reachable through actual Home Screen and dock icons belong in
// this picker. _folders includes archived/cached root-folder hierarchies.
static void AFWalk(id folder, NSArray *lists, NSString *location, NSMutableArray *slots,
                   NSMutableArray *folders, NSMutableSet *seen, NSUInteger depth) {
    if (!folder || depth > 32) return;
    NSValue *objectKey = [NSValue valueWithNonretainedObject:folder];
    if ([seen containsObject:objectKey]) return;
    [seen addObject:objectKey];
    NSUInteger page = 0;
    for (id list in lists) {
        NSString *where = [NSString stringWithFormat:@"%@ · %lu", location, (unsigned long)++page];
        for (id icon in [AFArray(AFGet(list, @"icons")) copy]) {
            [slots addObject:@{@"icon":icon, @"folder":folder, @"list":list, @"location":where}];
            if (AFBoolean(icon, @"isFolderIcon")) {
                id child = AFGet(icon, @"folder");
                if (!child) continue;
                NSString *identity = AFFolderID(child);
                BOOL existing = NO;
                for (NSDictionary *record in folders) if ([record[@"id"] isEqual:identity]) { existing = YES; break; }
                NSString *name = AFGet(child, @"displayName") ?: AFGet(icon, @"displayName") ?: @"Folder";
                if (!existing) [folders addObject:@{@"id":identity, @"name":name, @"icon":icon, @"folder":child, @"location":where}];
                AFWalk(child, AFArray(AFGet(child, @"lists")), name, slots, folders, seen, depth+1);
            }
        }
    }
}
static NSDictionary *AFLayout(void) {
    NSMutableArray *slots = NSMutableArray.array, *folders = NSMutableArray.array;
    NSMutableSet *seen = NSMutableSet.set;
    id root = AFRoot();
    if (!root) AFFail(@"Home Screen model is unavailable");
    AFWalk(root, AFArray(AFGet(root, @"lists")), @"Home", slots, folders, seen, 0);
    id dock = AFGet(AFGet(AFManager(), @"dockListView"), @"model");
    if (dock) AFWalk(root, @[dock], @"Dock", slots, folders, NSMutableSet.set, 0);
    return @{@"slots":slots, @"folders":folders};
}
static NSArray *AFPositions(NSDictionary *layout, id icon) {
    NSMutableArray *exact = NSMutableArray.array, *matches = NSMutableArray.array;
    NSString *identity = AFIdentity(icon);
    for (NSDictionary *slot in layout[@"slots"]) {
        if (slot[@"icon"] == icon) [exact addObject:slot];
        if ([AFIdentity(slot[@"icon"]) isEqual:identity]) [matches addObject:slot];
    }
    return exact.count ? exact : matches;
}
static NSDictionary *AFFindFolder(NSString *identity) {
    for (NSDictionary *record in AFLayout()[@"folders"]) if ([record[@"id"] isEqual:identity]) return record;
    return nil;
}
static NSDictionary *AFCounts(NSDictionary *layout) {
    NSMutableDictionary *counts = NSMutableDictionary.dictionary;
    for (NSDictionary *slot in layout[@"slots"]) {
        id icon = slot[@"icon"];
        if (AFBoolean(icon, @"isFolderIcon")) continue;
        NSString *key = AFIdentity(icon);
        counts[key] = @([counts[key] unsignedIntegerValue] + 1);
    }
    return counts;
}
static NSDictionary *AFSnapshot(void) {
    if (!AFBoolean(AFModel(), @"saveIconStateIfNeeded")) AFFail(@"Cannot save the Home Screen layout");
    id state = AFGet(AFModel(), @"iconState");
    if (![state isKindOfClass:NSDictionary.class]) AFFail(@"Cannot read the Home Screen layout");
    return state;
}
static void AFBackup(void) {
    NSDictionary *state = AFSnapshot();
    NSString *directory = [@"/var/mobile/Library/SpringBoard/AddToFolderFixRecovery" stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:&error]) AFFail(error.localizedDescription);
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:state format:NSPropertyListBinaryFormat_v1_0 options:0 error:&error];
    AFRecovery = [directory stringByAppendingPathComponent:@"IconState.plist"];
    if (!data || ![data writeToFile:AFRecovery options:NSDataWritingAtomic error:&error]) AFFail(error.localizedDescription ?: @"Cannot write recovery snapshot");
}
static void AFRelayout(void) {
    if ([AFManager() respondsToSelector:NSSelectorFromString(@"relayout")]) AFInvoke(AFManager(), @"relayout", @[], NO);
}
static UIViewController *AFPresenter(void) {
    UIViewController *controller = AFWindow.rootViewController;
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) controller = controller.presentedViewController;
    return controller;
}
static void AFClose(void) {
    AFWindow.hidden = YES; AFWindow = nil; AFShowing = NO;
    [AFPreviousKeyWindow makeKeyWindow]; AFPreviousKeyWindow = nil;
}
static NSString *AFText(NSString *en, NSString *ru) {
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"] ? ru : en;
}
static void AFError(NSString *message) {
    NSLog(@"[AddToFolderFix] %@ recovery=%@", message, AFRecovery ?: @"none");
    if (!AFWindow) return;
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:AFText(@"AddToFolder", @"AddToFolder") message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) { AFClose(); }]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        UIViewController *presenter = AFPresenter();
        if (presenter.presentedViewController) [presenter dismissViewControllerAnimated:NO completion:^{ [presenter presentViewController:alert animated:YES completion:nil]; }];
        else [presenter presentViewController:alert animated:YES completion:nil];
    });
}
static BOOL AFContains(id folder, id icon) {
    for (id list in AFArray(AFGet(folder, @"lists")))
        for (id candidate in AFArray(AFGet(list, @"icons"))) if (candidate == icon) return YES;
    // Dock lists are not necessarily exposed by rootFolder.lists.
    if (folder == AFRoot()) for (NSDictionary *slot in AFPositions(AFLayout(), icon)) if (slot[@"folder"] == folder) return YES;
    return NO;
}
static void AFAdd(id folder, id icon, id source) {
    SEL can = NSSelectorFromString(@"canAddIcon:");
    NSMethodSignature *sig = [folder methodSignatureForSelector:can];
    if (![folder respondsToSelector:can] || sig.numberOfArguments != 3 ||
        *AFType([sig getArgumentTypeAtIndex:2]) != '@' || !strchr("Bc", *AFType(sig.methodReturnType))) AFFail(@"Folder capacity API unavailable");
    if (!((BOOL (*)(id, SEL, id))objc_msgSend)(folder, can, icon)) AFFail(AFText(@"The destination folder cannot accept this icon.", @"Выбранная папка не может принять эту иконку."));
    AFInvoke(folder, @"addIcon:options:", @[icon], YES);
    if (!AFContains(folder, icon)) AFFail(@"SpringBoard rejected the destination insertion");
    // Some folder mutation policies automatically remove the previous position;
    // others leave it until the caller removes it. Handle either policy explicitly.
    if (source && source != folder && AFContains(source, icon)) AFInvoke(source, @"removeIcon:options:", @[icon], YES);
}
static void AFMove(id requestedIcon, NSString *destinationID, NSNumber *page, NSString *newName) {
    if (AFMoving) return;
    AFMoving = YES;
    id icon = requestedIcon, source = nil, createdIcon = nil;
    NSIndexPath *originalPath = nil;
    NSDictionary *before = nil;
    BOOL began = NO;
    @try {
        NSDictionary *layout = AFLayout();
        NSArray *positions = AFPositions(layout, icon);
        if (positions.count > 1) AFFail(@"The source icon has several Home Screen positions; reopen its menu from one position.");
        if (positions.count) { icon = positions[0][@"icon"]; source = positions[0][@"folder"]; originalPath = AFGet1(source, @"indexPathForIcon:", icon); }
        if (source && !originalPath) AFFail(@"The source icon no longer has a valid position");
        id destination = AFRoot();
        if (destinationID) {
            NSDictionary *record = AFFindFolder(destinationID);
            if (!record) AFFail(AFText(@"This folder is no longer on the Home Screen. Reopen the menu.", @"Этой папки уже нет на рабочем столе. Откройте меню заново."));
            destination = record[@"folder"];
        }
        if (page && page.unsignedIntegerValue >= AFArray(AFGet(AFRoot(), @"lists")).count) AFFail(@"This Home Screen page no longer exists");
        if (source == destination && !page && !newName) { AFClose(); AFMoving = NO; return; }
        before = AFCounts(layout);
        NSMutableDictionary *expected = [before mutableCopy];
        if (!positions.count) expected[AFIdentity(icon)] = @([expected[AFIdentity(icon)] unsignedIntegerValue]+1);
        AFBackup(); began = YES;
        if (newName) {
            if (!source) AFFail(@"Place this icon on the Home Screen before creating a folder.");
            if (source != AFRoot()) AFAdd(AFRoot(), icon, source);
            SEL create = NSSelectorFromString(@"createNewFolderFromRecipientIcon:grabbedIcon:");
            NSMethodSignature *sig = [AFManager() methodSignatureForSelector:create];
            if (![AFManager() respondsToSelector:create] || sig.numberOfArguments != 4 ||
                *AFType(sig.methodReturnType) != '@' || *AFType([sig getArgumentTypeAtIndex:2]) != '@' ||
                *AFType([sig getArgumentTypeAtIndex:3]) != '@') AFFail(@"Folder creation API unavailable");
            createdIcon = ((id (*)(id, SEL, id, id))objc_msgSend)(AFManager(), create, icon, nil);
            destination = AFGet(createdIcon, @"folder");
            if (!destination) AFFail(@"SpringBoard did not create a folder");
            AFInvoke(createdIcon, @"setDisplayName:", @[newName], NO);
            if (!AFContains(destination, icon)) AFAdd(destination, icon, AFRoot());
        } else if (page) {
            NSUInteger indexes[2] = {page.unsignedIntegerValue, 0};
            NSIndexPath *path = [NSIndexPath indexPathWithIndexes:indexes length:2];
            AFInsert(destination, icon, path);
            if (!AFContains(destination, icon)) AFFail(@"SpringBoard rejected the page insertion");
            if (source && source != destination && AFContains(source, icon)) AFInvoke(source, @"removeIcon:options:", @[icon], YES);
        } else AFAdd(destination, icon, source);
        NSDictionary *after = AFLayout();
        NSArray *placed = AFPositions(after, icon);
        if (placed.count != 1 || placed[0][@"folder"] != destination || ![AFCounts(after) isEqual:expected]) AFFail(@"Icon position or layout inventory validation failed");
        if (page && placed[0][@"list"] != AFArray(AFGet(AFRoot(), @"lists"))[page.unsignedIntegerValue]) AFFail(@"The requested Home Screen page rejected this icon");
        AFSnapshot(); AFRelayout();
        NSLog(@"[AddToFolderFix] moved %@ into %@; recovery=%@", AFIdentity(icon), AFFolderID(destination), AFRecovery);
        AFClose();
    } @catch (NSException *exception) {
        if (began) {
            @try {
                if (source && originalPath) {
                    AFInsert(source, icon, originalPath);
                    for (NSDictionary *slot in AFPositions(AFLayout(), icon))
                        if (slot[@"folder"] != source) AFInvoke(slot[@"folder"], @"removeIcon:options:", @[icon], YES);
                }
                else for (NSDictionary *slot in AFPositions(AFLayout(), icon)) AFInvoke(slot[@"folder"], @"removeIcon:options:", @[icon], YES);
                if (createdIcon) AFInvoke(AFRoot(), @"removeIcon:options:", @[createdIcon], YES);
                AFSnapshot(); AFRelayout();
                if (![AFCounts(AFLayout()) isEqual:before]) NSLog(@"[AddToFolderFix] rollback inventory mismatch; snapshot=%@", AFRecovery);
            } @catch (NSException *rollback) { NSLog(@"[AddToFolderFix] rollback failed %@ snapshot=%@", rollback.reason, AFRecovery); }
        }
        AFError(exception.reason ?: @"Unknown SpringBoard error");
    }
    AFMoving = NO;
}
static void AFPromptName(id icon) {
    UIAlertController *prompt = [UIAlertController alertControllerWithTitle:AFText(@"New folder", @"Новая папка") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [prompt addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = AFText(@"Folder name", @"Имя папки"); }];
    [prompt addAction:[UIAlertAction actionWithTitle:AFText(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) { AFClose(); }]];
    [prompt addAction:[UIAlertAction actionWithTitle:AFText(@"Create", @"Создать") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        NSString *name = [prompt.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (!name.length || name.length > 128) { AFError(AFText(@"Enter a folder name (1–128 characters).", @"Введите имя папки (1–128 символов).")); return; }
        AFMove(icon, nil, nil, name);
    }]];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [AFPresenter() presentViewController:prompt animated:YES completion:nil]; });
}
static void AFPagePicker(id icon) {
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:AFText(@"Move to page", @"Переместить на страницу") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    NSUInteger count = AFArray(AFGet(AFRoot(), @"lists")).count;
    for (NSUInteger i = 0; i < count; i++) {
        NSNumber *page = @(i);
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"%lu", (unsigned long)i+1] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { AFMove(icon, nil, page, nil); }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:AFText(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) { AFClose(); }]];
    sheet.popoverPresentationController.sourceView = AFWindow.rootViewController.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(AFWindow.bounds.size.width/2, AFWindow.bounds.size.height/2, 1, 1);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 350*NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [AFPresenter() presentViewController:sheet animated:YES completion:nil]; });
}
static void AFShow(id icon, UIWindowScene *preferredScene) {
    if (AFShowing || AFMoving || !icon) return;
    if (AFBoolean(icon, @"isFolderIcon") || AFBoolean(icon, @"isWidgetIcon") || AFBoolean(icon, @"isPlaceholder")) return;
    AFShowing = YES;
    UIWindowScene *scene = preferredScene;
    if (!scene) for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes)
        if ([candidate isKindOfClass:UIWindowScene.class] && candidate.activationState == UISceneActivationStateForegroundActive) { scene = (UIWindowScene *)candidate; break; }
    for (UIWindow *window in scene.windows) if (window.isKeyWindow) { AFPreviousKeyWindow = window; break; }
    AFWindow = scene ? [[UIWindow alloc] initWithWindowScene:scene] : [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    AFWindow.windowLevel = UIWindowLevelAlert+1; AFWindow.rootViewController = UIViewController.new;
    AFWindow.rootViewController.view.backgroundColor = UIColor.clearColor; [AFWindow makeKeyAndVisible];
    @try {
        NSDictionary *layout = AFLayout();
        NSArray *positions = AFPositions(layout, icon);
        id source = positions.count == 1 ? positions[0][@"folder"] : nil;
        NSString *name = AFGet(icon, @"displayName") ?: @"";
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:AFText(@"Add %@ to folder…", @"Добавить %@ в папку…"), name] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:AFText(@"＋ New folder", @"＋ Новая папка") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { AFPromptName(icon); }]];
        if (source && source != AFRoot()) [sheet addAction:[UIAlertAction actionWithTitle:AFText(@"Remove from current folder", @"Убрать из текущей папки") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { AFMove(icon, nil, nil, nil); }]];
        [sheet addAction:[UIAlertAction actionWithTitle:AFText(@"Move to page…", @"Переместить на страницу…") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { AFPagePicker(icon); }]];
        NSArray *folders = [layout[@"folders"] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSComparisonResult result = [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
            return result == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : result;
        }];
        NSMutableDictionary *names = NSMutableDictionary.dictionary;
        for (NSDictionary *record in folders) names[record[@"name"]] = @([names[record[@"name"]] unsignedIntegerValue]+1);
        for (NSDictionary *record in folders) {
            if (record[@"folder"] == source) continue;
            NSString *title = record[@"name"], *identity = record[@"id"];
            if ([names[title] unsignedIntegerValue] > 1) title = [NSString stringWithFormat:@"%@ — %@", title, record[@"location"]];
            [sheet addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { AFMove(icon, identity, nil, nil); }]];
        }
        [sheet addAction:[UIAlertAction actionWithTitle:AFText(@"Cancel", @"Отмена") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action) { AFClose(); }]];
        sheet.popoverPresentationController.sourceView = AFWindow.rootViewController.view;
        sheet.popoverPresentationController.sourceRect = CGRectMake(AFWindow.bounds.size.width/2, AFWindow.bounds.size.height/2, 1, 1);
        [AFWindow.rootViewController presentViewController:sheet animated:YES completion:nil];
    } @catch (NSException *exception) { AFError(exception.reason); }
}
static BOOL AFIsShortcut(id item) { return [AFGet(item, @"type") isEqual:AFShortcutType]; }
static void (*AFOriginalActivate)(id, SEL, id, id, id);
static void AFActivate(id self, SEL selector, id item, id bundleID, id view) {
    if (AFIsShortcut(item)) { id icon = AFGet(view, @"icon"); UIWindowScene *scene = [view isKindOfClass:UIView.class] ? [(UIView *)view window].windowScene : nil; dispatch_async(dispatch_get_main_queue(), ^{ AFShow(icon, scene); }); return; }
    AFOriginalActivate(self, selector, item, bundleID, view);
}
static BOOL (*AFOriginalShould)(id, SEL, id, id, NSUInteger);
static BOOL AFShould(id self, SEL selector, id view, id item, NSUInteger index) {
    if (AFIsShortcut(item)) { id icon = AFGet(view, @"icon"); UIWindowScene *scene = [view isKindOfClass:UIView.class] ? [(UIView *)view window].windowScene : nil; dispatch_async(dispatch_get_main_queue(), ^{ AFShow(icon, scene); }); return NO; }
    return AFOriginalShould(self, selector, view, item, index);
}
static BOOL (*AFOriginalDelegate)(id, SEL, id, id, NSUInteger, id);
static BOOL AFDelegate(id self, SEL selector, id manager, id item, NSUInteger index, id view) {
    if (AFIsShortcut(item)) { id icon = AFGet(view, @"icon"); UIWindowScene *scene = [view isKindOfClass:UIView.class] ? [(UIView *)view window].windowScene : nil; dispatch_async(dispatch_get_main_queue(), ^{ AFShow(icon, scene); }); return NO; }
    return AFOriginalDelegate(self, selector, manager, item, index, view);
}
static void AFInstallHooks(void) {
    Class view = object_getClass(NSClassFromString(@"SBIconView"));
    SEL activate = NSSelectorFromString(@"activateShortcut:withBundleIdentifier:forIconView:");
    Method method = class_getInstanceMethod(view, activate);
    if (method) {
        NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (sig.numberOfArguments == 5 && *AFType(sig.methodReturnType) == 'v') MSHookMessageEx(view, activate, (IMP)AFActivate, (IMP *)&AFOriginalActivate);
    }
    Class manager = NSClassFromString(@"SBHIconManager");
    SEL should = NSSelectorFromString(@"iconView:shouldActivateApplicationShortcutItem:atIndex:");
    method = class_getInstanceMethod(manager, should);
    if (method) {
        NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (sig.numberOfArguments == 5 && strchr("Bc", *AFType(sig.methodReturnType))) MSHookMessageEx(manager, should, (IMP)AFShould, (IMP *)&AFOriginalShould);
    }
    Class controller = NSClassFromString(@"SBIconController");
    SEL delegate = NSSelectorFromString(@"iconManager:shouldActivateApplicationShortcutItem:atIndex:forIconView:");
    method = class_getInstanceMethod(controller, delegate);
    if (method) {
        NSMethodSignature *sig = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (sig.numberOfArguments == 6 && strchr("Bc", *AFType(sig.methodReturnType))) MSHookMessageEx(controller, delegate, (IMP)AFDelegate, (IMP *)&AFOriginalDelegate);
    }
    NSLog(@"[AddToFolderFix] 1.0.0 hooks activate=%d should=%d delegate=%d", AFOriginalActivate != NULL, AFOriginalShould != NULL, AFOriginalDelegate != NULL);
}
__attribute__((constructor)) static void AFInitialize(void) {
    // Install after dylib constructors so the original tweak remains underneath
    // this handler regardless of ElleKit's dylib enumeration order.
    dispatch_async(dispatch_get_main_queue(), ^{ AFInstallHooks(); });
}
