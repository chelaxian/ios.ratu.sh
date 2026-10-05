#import "OFShared.h"
#import <dlfcn.h>
static id OFProxy(NSString *identifier) {
    Class cls = NSClassFromString(@"LSApplicationProxy");
    SEL selector = @selector(applicationProxyForIdentifier:);
    return OFValidID(identifier) && OFCanCall(cls,selector,'@',"@") ? ((id(*)(id,SEL,id))[cls methodForSelector:selector])(cls,selector,identifier) : nil;
}
static BOOL OFEligible(NSString *identifier) {
    id proxy = OFProxy(identifier);
    if (!proxy || !OFBool(proxy,@selector(isInstalled)) || OFBool(proxy,@selector(isPlaceholder))) return NO;
    if (![OFString(proxy,@selector(applicationType)) isEqual:@"User"]) return NO;
    // StorageData owns STStorageApp on iOS 17. Its decision includes restrictions.
    static dispatch_once_t once;
    dispatch_once(&once,^{ dlopen("/System/Library/PrivateFrameworks/StorageData.framework/StorageData",RTLD_NOW); });
    Class cls = NSClassFromString(@"STStorageApp");
    SEL selector = @selector(initWithApplicationIdentifier:);
    id allocation = [cls alloc];
    id app = OFCanCall(allocation,selector,'@',"@") ? ((id(*)(id,SEL,id))[allocation methodForSelector:selector])(allocation,selector,identifier) : nil;
    // Fail closed when the platform cannot establish that this app is demotable.
    return app && OFBool(app,@selector(isDemotable));
}
