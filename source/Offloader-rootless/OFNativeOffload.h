#import "OFShared.h"

// iOS 17 validates IX demotion reasons as 1...3. Zero is an error.
// Keep this separate from the guard, which must forward every caller's reason.
static const NSUInteger OFDemotionReason = 1;
static BOOL OFNativeDemote(NSString *bundle, NSError **error) {
    Class cls = NSClassFromString(@"IXAppInstallCoordinator");
    SEL selector = NSSelectorFromString(@"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:ignoreRemovability:error:");
    if (!OFValidID(bundle) || !OFCanCall(cls,selector,'b',"@qbb^")) {
        if (error) *error = OFError(3,OFText(@"The iOS offload API is unavailable.",@"API выгрузки iOS недоступен."));
        return NO;
    }
    return ((BOOL(*)(id,SEL,id,NSUInteger,BOOL,BOOL,NSError**))[cls methodForSelector:selector])(cls,selector,bundle,OFDemotionReason,YES,NO,error);
}
