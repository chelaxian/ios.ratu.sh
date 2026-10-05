#import "OFShared.h"
#import <dlfcn.h>
@interface NSObject (OFStorageInitialization)
- (instancetype)initWithApplicationIdentifier:(NSString *)identifier;
@end
static id OFProxy(NSString *identifier) {
    Class cls = NSClassFromString(@"LSApplicationProxy");
    SEL selector = @selector(applicationProxyForIdentifier:);
    return OFValidID(identifier) && OFCanCall(cls,selector,'@',"@") ? ((id(*)(id,SEL,id))[cls methodForSelector:selector])(cls,selector,identifier) : nil;
}
static BOOL OFEligible(NSString *identifier) {
    @try {
    id proxy = OFProxy(identifier);
    if (!proxy || !OFBool(proxy,@selector(isInstalled)) || OFBool(proxy,@selector(isPlaceholder))) return NO;
    // StorageData owns STStorageApp on iOS 17. Its decision includes restrictions
    // and covers removable Apple apps too; do not infer eligibility from app type.
    static dispatch_once_t once;
    dispatch_once(&once,^{ dlopen("/System/Library/PrivateFrameworks/StorageData.framework/StorageData",RTLD_NOW); });
    Class cls = NSClassFromString(@"STStorageApp");
    SEL selector = @selector(initWithApplicationIdentifier:);
    if (!OFMethodMatches(class_getInstanceMethod(cls,selector),'@',"@")) return NO;
    // Use a real Objective-C init send, so ARC handles replacement receivers
    // correctly; a generic id-returning IMP call loses init-family ownership.
    id app = [[cls alloc] initWithApplicationIdentifier:identifier];
    // Fail closed when the platform cannot establish that this app is demotable.
    return app && OFBool(app,@selector(isDemotable));
    } @catch (NSException *exception) {
        NSLog(@"[Offloader] Eligibility check failed: %@",exception.reason);
        return NO;
    }
}
