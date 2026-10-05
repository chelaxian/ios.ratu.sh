#import "OFShared.h"
#import <substrate.h>
static BOOL OFHook(Class cls, BOOL classMethod, NSString *name, IMP replacement, IMP *original, char result, const char *arguments) {
    Class target = classMethod ? object_getClass(cls) : cls;
    SEL selector = NSSelectorFromString(name);
    if (!OFMethodMatches(class_getInstanceMethod(target,selector),result,arguments)) {
        NSLog(@"[Offloader] Skipped missing/incompatible %@ %@",NSStringFromClass(cls),name);
        return NO;
    }
    MSHookMessageEx(target,selector,replacement,original);
    return YES;
}
