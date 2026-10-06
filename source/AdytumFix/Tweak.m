#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <substrate.h>
#import <dlfcn.h>
#import <mach-o/loader.h>
#import <stdatomic.h>
#import <stdio.h>
#import "BlockRepair.h"

// UUID of the inspected Adytum 1.1 arm64e slice. Unknown future builds are skipped.
static const unsigned char AFUUID[16] = {
    0x5f,0xfa,0x53,0x40,0xe6,0xc8,0x3e,0x5b,0x90,0x84,0x08,0x9f,0xd3,0x54,0xef,0xb3
};
static bool AFAdytumInvokeAllowed(void *invoke) {
    Dl_info info;
    if (!dladdr(invoke,&info) || !info.dli_fname || strcmp(strrchr(info.dli_fname,'/') ? strrchr(info.dli_fname,'/')+1 : info.dli_fname,"Adytum.dylib")) return false;
    const struct mach_header_64 *header = info.dli_fbase;
    if (header->magic != MH_MAGIC_64 || header->sizeofcmds > 65536 || header->ncmds > 256) return false;
    const uint8_t *cursor = (const uint8_t *)(header+1), *end = cursor+header->sizeofcmds;
    bool match = false;
    for (uint32_t i=0;i<header->ncmds;++i) {
        if (cursor+sizeof(struct load_command)>end) return false;
        const struct load_command *command = (const void *)cursor;
        if (command->cmdsize<sizeof(*command) || cursor+command->cmdsize>end) return false;
        if (command->cmd==LC_UUID && command->cmdsize>=sizeof(struct uuid_command))
            match = !memcmp(((const struct uuid_command *)command)->uuid,AFUUID,sizeof(AFUUID));
        cursor += command->cmdsize;
    }
    return match;
}
static atomic_uint AFRepairs;
static FILE *AFDiagnostics;
static void AFRecord(NSString *message) {
    NSLog(@"[AdytumFix] %@",message);
    if (AFDiagnostics) { fprintf(AFDiagnostics,"%s\n",message.UTF8String); fflush(AFDiagnostics); }
}
static void AFRepair(void *block) {
    if (AFRepairBlock(block,AFAdytumInvokeAllowed)) {
        unsigned count = atomic_fetch_add(&AFRepairs,1)+1;
        if (count<=8) AFRecord([NSString stringWithFormat:@"repaired Adytum stack block (%u)",count]);
    }
}
static id (*AFActionOriginal)(id,SEL,id,id,id,void *);
static id AFAction(id self,SEL cmd,id title,id image,id identifier,void *handler) {
    AFRepair(handler);
    return AFActionOriginal(self,cmd,title,image,identifier,handler);
}
static void (*AFSpringOriginal)(id,SEL,double,double,double,double,NSUInteger,void *,void *);
static void AFSpring(id self,SEL cmd,double duration,double delay,double damping,double velocity,NSUInteger options,void *animations,void *completion) {
    AFRepair(animations); AFRepair(completion);
    AFSpringOriginal(self,cmd,duration,delay,damping,velocity,options,animations,completion);
}
static void (*AFAnimationOriginal)(id,SEL,double,double,NSUInteger,void *,void *);
static void AFAnimation(id self,SEL cmd,double duration,double delay,NSUInteger options,void *animations,void *completion) {
    AFRepair(animations); AFRepair(completion);
    AFAnimationOriginal(self,cmd,duration,delay,options,animations,completion);
}
static bool AFHook(Class cls,const char *name,IMP replacement,IMP *original,unsigned count) {
    Class meta = object_getClass(cls); SEL selector = sel_registerName(name);
    Method method = class_getInstanceMethod(meta,selector);
    if (!method || method_getNumberOfArguments(method)!=count) {
        NSLog(@"[AdytumFix] skipped incompatible method %s",name); return false;
    }
    MSHookMessageEx(meta,selector,replacement,original); return true;
}
__attribute__((constructor)) static void AFStart(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.springboard"]) return;
#if __has_feature(ptrauth_calls)
        AFDiagnostics = fopen("/var/mobile/Library/Logs/AdytumFix.log","w");
        bool action = AFHook(UIAction.class,"actionWithTitle:image:identifier:handler:",(IMP)AFAction,(IMP *)&AFActionOriginal,6);
        bool spring = AFHook(UIView.class,"animateWithDuration:delay:usingSpringWithDamping:initialSpringVelocity:options:animations:completion:",(IMP)AFSpring,(IMP *)&AFSpringOriginal,9);
        bool animation = AFHook(UIView.class,"animateWithDuration:delay:options:animations:completion:",(IMP)AFAnimation,(IMP *)&AFAnimationOriginal,7);
        AFRecord([NSString stringWithFormat:@"ready: UIAction=%d spring=%d animation=%d; Adytum 1.1 only",action,spring,animation]);
#else
        NSLog(@"[AdytumFix] arm64 process: no repair needed");
#endif
    }
}
