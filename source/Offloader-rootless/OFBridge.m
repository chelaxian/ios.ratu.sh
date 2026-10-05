#import "OFApplications.h"
#import <UIKit/UIKit.h>

static NSString *OFBridgeActive;
static NSString *OFBridgeLast;
static void OFBridgeReply(NSString *identifier, BOOL ok, NSString *message) {
    OFWrite(OFDomain,@"response",@{@"id":identifier,@"ok":@(ok),@"message":message ?: @"",@"date":NSDate.date});
    notify_post(OFResponse);
}
static void OFBridgeCheck(void) {
    // All state transitions are on main; the actual IX work runs off main.
    NSDictionary *request = OFPreferences(OFDomain)[@"request"];
    if (![request isKindOfClass:NSDictionary.class]) return;
    NSString *identifier = request[@"id"], *bundle = request[@"bundle"];
    NSDate *date = request[@"date"];
    if (!OFValidID(identifier) || !OFValidID(bundle) || ![date isKindOfClass:NSDate.class] ||
        -date.timeIntervalSinceNow > 45 || date.timeIntervalSinceNow > 5 || OFBridgeActive || [OFBridgeLast isEqual:identifier]) return;
    NSDictionary *response = OFPreferences(OFDomain)[@"response"];
    if ([response isKindOfClass:NSDictionary.class] && [response[@"id"] isEqual:identifier]) return;
    OFBridgeActive = identifier;
    OFBridgeLast = identifier;
    // No durable command replay after a Settings restart, including an in-flight command.
    if (!OFWrite(OFDomain,@"request",nil)) {
        OFBridgeReply(identifier,NO,OFText(@"Could not claim the offload request.",@"Не удалось принять команду выгрузки."));
        OFBridgeActive = nil; return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            NSError *error = nil;
            BOOL ok = NO;
            @try {
                if (OFProtected(bundle)) error = OFError(1,OFText(@"This app is protected from offloading.",@"Это приложение защищено от выгрузки."));
                else if (!OFEligible(bundle)) error = OFError(2,OFText(@"iOS does not allow this app to be offloaded.",@"iOS не разрешает выгрузить это приложение."));
                else {
                    Class cls = NSClassFromString(@"IXAppInstallCoordinator");
                    SEL selector = NSSelectorFromString(@"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:ignoreRemovability:error:");
                    if (OFCanCall(cls,selector,'b',"@qbb^")) {
                        ok = ((BOOL(*)(id,SEL,id,NSUInteger,BOOL,BOOL,NSError**))[cls methodForSelector:selector])(cls,selector,bundle,0,YES,NO,&error);
                    } else error = OFError(3,OFText(@"The iOS offload API is unavailable.",@"API выгрузки iOS недоступен."));
                    // Completion means deletion finished; also verify the LaunchServices state.
                    if (ok) {
                        for (unsigned attempt=0; attempt<20 && OFBool(OFProxy(bundle),@selector(isInstalled)); ++attempt) [NSThread sleepForTimeInterval:0.25];
                        id proxy = OFProxy(bundle);
                        if (!proxy || !OFCanCall(proxy,@selector(isInstalled),'b',"") || OFBool(proxy,@selector(isInstalled))) { ok = NO; error = OFError(4,OFText(@"iOS has not confirmed the offload.",@"iOS не подтвердила выгрузку.")); }
                    }
                }
            } @catch (NSException *exception) { error = OFError(5,exception.reason); }
            dispatch_async(dispatch_get_main_queue(),^{
                OFBridgeReply(identifier,ok,error.localizedDescription ?: OFText(@"App offloaded. Its documents and data are kept.",@"Приложение выгружено. Документы и данные сохранены."));
                OFBridgeActive = nil;
            });
        }
    });
}
__attribute__((constructor)) static void OFBridgeStart(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.Preferences"]) return;
        dlopen("/System/Library/PrivateFrameworks/InstallCoordination.framework/InstallCoordination",RTLD_NOW);
        dispatch_async(dispatch_get_main_queue(),^{
            int token;
            notify_register_dispatch(OFCommand,&token,dispatch_get_main_queue(),^(__unused int t){ OFBridgeCheck(); });
            // A cold launch may precede UIKit finishing initialization.
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{OFBridgeCheck();});
            NSLog(@"[Offloader] Settings bridge loaded");
        });
    }
}
