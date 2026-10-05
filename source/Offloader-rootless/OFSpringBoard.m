#import "OFHook.h"
#import "OFApplications.h"
#import <UIKit/UIKit.h>

static NSString *OFPending;
static UIAlertController *OFProgress;
static UIViewController *OFPresenter(void) {
    Class cls = NSClassFromString(@"SBIconController");
    UIViewController *controller = OFObject(OFObject(cls,@selector(sharedInstance)),@selector(rootViewController));
    if (![controller isKindOfClass:UIViewController.class]) {
        for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
            if (![scene isKindOfClass:UIWindowScene.class]) continue;
            for (UIWindow *window in ((UIWindowScene *)scene).windows) if (window.isKeyWindow) { controller = window.rootViewController; break; }
            if (controller) break;
        }
    }
    while (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) controller = controller.presentedViewController;
    return controller.view.window ? controller : nil;
}
static void OFMessage(NSString *message) {
    UIViewController *presenter = OFPresenter();
    if (!presenter) { NSLog(@"[Offloader] %@",message); return; }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Offloader" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:OFText(@"OK",@"ОК") style:UIAlertActionStyleDefault handler:nil]];
    [presenter presentViewController:alert animated:YES completion:nil];
}
static void OFFinish(NSString *identifier, NSString *message) {
    if (![OFPending isEqual:identifier]) return;
    OFPending = nil;
    UIAlertController *progress = OFProgress; OFProgress = nil;
    if (progress.presentingViewController) [progress dismissViewControllerAnimated:YES completion:^{OFMessage(message);}];
    else OFMessage(message);
}
static void OFPoll(NSString *identifier, NSDate *started) {
    if (![OFPending isEqual:identifier]) return;
    id response = OFPreferences(OFDomain)[@"response"];
    if (OFResponseMatches(response,identifier)) {
        NSString *message = [response[@"message"] isKindOfClass:NSString.class] ? response[@"message"] : OFText(@"Offload finished.",@"Выгрузка завершена.");
        OFFinish(identifier,message); return;
    }
    if (-started.timeIntervalSinceNow > 45) {
        id request = OFPreferences(OFDomain)[@"request"];
        if ([request isKindOfClass:NSDictionary.class] && [request[@"id"] isEqual:identifier]) OFWrite(OFDomain,@"request",nil);
        OFFinish(identifier,OFText(@"iOS did not confirm the offload. Check the app's cloud icon before trying again. Allow Offloader in Settings and SpringBoard in Choicy.",@"iOS не подтвердила выгрузку. Перед повтором проверьте значок облака у приложения. Разрешите Offloader для Настроек и SpringBoard в Choicy.")); return;
    }
    notify_post(OFCommand);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{OFPoll(identifier,started);});
}
static void OFStartOffload(NSString *bundle) {
    if (OFPending) { OFMessage(OFText(@"An offload is already in progress.",@"Выгрузка уже выполняется.")); return; }
    if (OFProtected(bundle) || !OFEligible(bundle)) { OFMessage(OFText(@"This app cannot be offloaded or is protected.",@"Это приложение нельзя выгрузить или оно защищено.")); return; }
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDate *started = NSDate.date;
    if (!OFWrite(OFDomain,@"request",@{@"id":identifier,@"bundle":bundle,@"date":started})) { OFMessage(OFText(@"Could not send the offload request.",@"Не удалось отправить команду выгрузки.")); return; }
    OFPending = identifier;
    OFProgress = [UIAlertController alertControllerWithTitle:@"Offloader" message:OFText(@"Offloading…",@"Выгрузка…") preferredStyle:UIAlertControllerStyleAlert];
    UIViewController *presenter = OFPresenter();
    if (presenter) [presenter presentViewController:OFProgress animated:YES completion:nil];
    notify_post(OFCommand);
    // The Settings process has the native storage-management privileges.
    // Launch in the background; its constructor consumes commands on cold launch.
    UIApplication *app = UIApplication.sharedApplication;
    SEL selector = @selector(launchApplicationWithIdentifier:suspended:);
    if (OFCanCall(app,selector,'b',"@b")) ((BOOL(*)(id,SEL,id,BOOL))[app methodForSelector:selector])(app,selector,@"com.apple.Preferences",YES);
    else if (OFCanCall(app,selector,'v',"@b")) ((void(*)(id,SEL,id,BOOL))[app methodForSelector:selector])(app,selector,@"com.apple.Preferences",YES);
    else {
        OFWrite(OFDomain,@"request",nil);
        OFFinish(identifier,OFText(@"Open Settings once, then try Offload again.",@"Откройте Настройки, затем повторите выгрузку.")); return;
    }
    OFPoll(identifier,started);
}
static void OFConfirmOffload(NSString *bundle) {
    // Let the icon's context menu finish dismissal before presenting a confirmation.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        UIViewController *presenter = OFPresenter();
        if (!presenter) return;
        NSString *name = OFString(OFProxy(bundle),@selector(localizedName)) ?: bundle;
        NSString *message = [NSString stringWithFormat:OFText(@"Offload %@? Its documents and data will be kept. Reinstalling later requires the app to remain available.",@"Выгрузить %@? Документы и данные сохранятся. Для повторной установки приложение должно оставаться доступным."),name];
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:OFText(@"Offload App",@"Выгрузить приложение") message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:OFText(@"Cancel",@"Отмена") style:UIAlertActionStyleCancel handler:nil]];
        [alert addAction:[UIAlertAction actionWithTitle:OFText(@"Offload",@"Выгрузить") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{OFStartOffload(bundle);});
        }]];
        [presenter presentViewController:alert animated:YES completion:nil];
    });
}
static NSString *OFViewBundle(id view) {
    id icon = OFObject(view,@selector(icon));
    // Folder, widget, stack, bookmark and web clip menus retain their original contents.
    Class cls = NSClassFromString(@"SBHApplicationIcon");
    if (!cls || ![icon isKindOfClass:cls]) return nil;
    NSString *identifier = OFString(icon,@selector(applicationBundleID));
    if (!OFValidID(identifier)) identifier = OFString(view,@selector(applicationBundleIdentifierForShortcuts));
    return OFValidID(identifier) ? identifier : nil;
}
static NSArray *OFFilterShortcuts(NSArray *items, NSDictionary *settings) {
    if (![items isKindOfClass:NSArray.class]) return items;
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        OFActionKind kind = OFKind(OFString(item,@selector(type)),OFString(item,@selector(localizedTitle)),OFBool(item,@selector(sbh_isShortcutDeleteOrRemove)));
        if (OFShowKind(kind,settings)) [result addObject:item];
    }
    return result;
}
static NSArray<UIMenuElement *> *OFFilterMenu(NSArray *items, NSDictionary *settings) {
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:items.count];
    for (id item in items) {
        if ([item isKindOfClass:UIMenu.class]) {
            UIMenu *menu = item;
            NSArray *children = OFFilterMenu(menu.children,settings);
            if (children.count) [result addObject:[children isEqual:menu.children] ? menu : [menu menuByReplacingChildren:children]];
        } else if ([item isKindOfClass:UIAction.class]) {
            UIAction *action = item;
            if (OFShowKind(OFKind(action.identifier,action.title,NO),settings)) [result addObject:action];
        } else [result addObject:item];
    }
    return result;
}
static IMP OFItemsOriginal, OFEffectiveOriginal, OFMenuOriginal;
static id OFItems(id self, SEL cmd) {
    id original = ((id(*)(id,SEL))OFItemsOriginal)(self,cmd);
    return OFViewBundle(self) ? OFFilterShortcuts(original,OFPreferences(OFDomain)) : original;
}
static id OFEffective(id self, SEL cmd) {
    id original = ((id(*)(id,SEL))OFEffectiveOriginal)(self,cmd);
    return OFViewBundle(self) ? OFFilterShortcuts(original,OFPreferences(OFDomain)) : original;
}
static id OFMenu(id self, SEL cmd, id interaction, id configuration) {
    id original = ((id(*)(id,SEL,id,id))OFMenuOriginal)(self,cmd,interaction,configuration);
    NSString *bundle = OFViewBundle(self);
    if (!bundle || (original && ![original isKindOfClass:NSArray.class])) return original;
    NSDictionary *settings = OFPreferences(OFDomain);
    NSMutableArray *items = [OFFilterMenu(original ?: @[],settings) mutableCopy];
    if (OFShowKind(OFActionOffload,settings) && !OFProtected(bundle) && OFEligible(bundle)) {
        UIAction *action = [UIAction actionWithTitle:OFText(@"Offload App",@"Выгрузить приложение") image:[UIImage systemImageNamed:@"icloud.and.arrow.down"] identifier:@"com.level3tjg.offloader/offload" handler:^(__unused UIAction *a){OFConfirmOffload(bundle);}];
        [items addObject:action];
    }
    return items;
}
#ifndef OFFLOADER_UI_TEST
__attribute__((constructor)) static void OFSpringBoardStart(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
        Class cls = NSClassFromString(@"SBIconView");
        OFHook(cls,NO,@"applicationShortcutItems",(IMP)OFItems,&OFItemsOriginal,'@',"");
        OFHook(cls,NO,@"effectiveApplicationShortcutItems",(IMP)OFEffective,&OFEffectiveOriginal,'@',"");
        OFHook(cls,NO,@"_contextMenuInteraction:overrideSuggestedActionsForConfiguration:",(IMP)OFMenu,&OFMenuOriginal,'@',"@@");
        dispatch_async(dispatch_get_main_queue(),^{
            if (![NSFileManager.defaultManager fileExistsAtPath:OF_PROTECTION_PATH]) {
                NSError *error;
                if (!OFWriteProtectionSnapshot(OFPreferences(OFAntiDomain),&error)) NSLog(@"[Offloader] Could not migrate protection: %@",error);
            }
            NSLog(@"[Offloader] SpringBoard menus loaded");
        });
    }
}
#endif
