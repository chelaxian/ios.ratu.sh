// Host-only hook replacement. Never included by the iOS target.
#import <objc/runtime.h>
static inline void MSHookMessageEx(Class cls, SEL selector, IMP replacement, IMP *original) {
    Method method = class_getInstanceMethod(cls,selector);
    *original = method_setImplementation(method,replacement);
}
