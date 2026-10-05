#import "OFHook.h"
#import <dlfcn.h>

static NSString *OFIdentityBundle(id identity) {
    if ([identity isKindOfClass:NSString.class]) return identity;
    NSString *identifier = OFString(identity,@selector(bundleIdentifier));
    if (!identifier) identifier = OFString(identity,@selector(bundleID));
    id base = OFObject(identity,@selector(miAppIdentity));
    return identifier ?: OFString(base,@selector(bundleIdentifier)) ?: OFString(base,@selector(bundleID));
}
static NSError *OFProtectionError(id identity) {
    NSString *identifier = OFIdentityBundle(identity);
    return OFProtected(identifier) ? OFError(1,[NSString stringWithFormat:@"%@ is protected from offloading.",identifier]) : nil;
}
static IMP OFSync3Original, OFSync4Original, OFSync5Original, OFSyncIdentityOriginal;
static IMP OFAsync4Original, OFAsync5Original, OFAsyncPrivateOriginal, OFAsyncIdentityOriginal, OFAsyncIdentityPrivateOriginal;
static void OFDeniedCompletion(void(^completion)(NSError *), NSError *error) {
    // Preserve asynchronous delivery and avoid re-entering a caller holding a lock.
    if (completion) dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^{completion(error);});
}
static BOOL OFSync3(id self, SEL cmd, id bundle, NSUInteger reason, NSError **error) {
    NSError *denied = OFProtectionError(bundle);
    if (denied) { if (error) *error = denied; return NO; }
    return ((BOOL(*)(id,SEL,id,NSUInteger,NSError**))OFSync3Original)(self,cmd,bundle,reason,error);
}
static BOOL OFSync4(id self, SEL cmd, id bundle, NSUInteger reason, BOOL wait, NSError **error) {
    NSError *denied = OFProtectionError(bundle);
    if (denied) { if (error) *error = denied; return NO; }
    return ((BOOL(*)(id,SEL,id,NSUInteger,BOOL,NSError**))OFSync4Original)(self,cmd,bundle,reason,wait,error);
}
static BOOL OFSync5(id self, SEL cmd, id bundle, NSUInteger reason, BOOL wait, BOOL ignore, NSError **error) {
    NSError *denied = OFProtectionError(bundle);
    if (denied) { if (error) *error = denied; return NO; }
    return ((BOOL(*)(id,SEL,id,NSUInteger,BOOL,BOOL,NSError**))OFSync5Original)(self,cmd,bundle,reason,wait,ignore,error);
}
static BOOL OFSyncIdentity(id self, SEL cmd, id identity, NSUInteger reason, BOOL wait, BOOL ignore, NSError **error) {
    NSError *denied = OFProtectionError(identity);
    if (denied) { if (error) *error = denied; return NO; }
    return ((BOOL(*)(id,SEL,id,NSUInteger,BOOL,BOOL,NSError**))OFSyncIdentityOriginal)(self,cmd,identity,reason,wait,ignore,error);
}
static void OFAsync4(id self, SEL cmd, id bundle, NSUInteger reason, BOOL wait, void(^completion)(NSError *)) {
    NSError *denied = OFProtectionError(bundle);
    if (denied) { OFDeniedCompletion(completion,denied); return; }
    ((void(*)(id,SEL,id,NSUInteger,BOOL,id))OFAsync4Original)(self,cmd,bundle,reason,wait,completion);
}
static void OFAsync5(id self, SEL cmd, id bundle, NSUInteger reason, BOOL wait, BOOL ignore, void(^completion)(NSError *)) {
    NSError *denied = OFProtectionError(bundle);
    if (denied) { OFDeniedCompletion(completion,denied); return; }
    ((void(*)(id,SEL,id,NSUInteger,BOOL,BOOL,id))OFAsync5Original)(self,cmd,bundle,reason,wait,ignore,completion);
}
static void OFAsyncPrivate(id self, SEL cmd, id bundle, NSUInteger reason, BOOL wait, BOOL ignore, void(^completion)(NSError *)) {
    NSError *denied = OFProtectionError(bundle);
    if (denied) { OFDeniedCompletion(completion,denied); return; }
    ((void(*)(id,SEL,id,NSUInteger,BOOL,BOOL,id))OFAsyncPrivateOriginal)(self,cmd,bundle,reason,wait,ignore,completion);
}
static void OFAsyncIdentity(id self, SEL cmd, id identity, NSUInteger reason, BOOL wait, BOOL ignore, void(^completion)(NSError *)) {
    NSError *denied = OFProtectionError(identity);
    if (denied) { OFDeniedCompletion(completion,denied); return; }
    ((void(*)(id,SEL,id,NSUInteger,BOOL,BOOL,id))OFAsyncIdentityOriginal)(self,cmd,identity,reason,wait,ignore,completion);
}
static void OFAsyncIdentityPrivate(id self, SEL cmd, id identity, NSUInteger reason, BOOL wait, BOOL ignore, BOOL early, void(^completion)(NSError *)) {
    NSError *denied = OFProtectionError(identity);
    if (denied) { OFDeniedCompletion(completion,denied); return; }
    ((void(*)(id,SEL,id,NSUInteger,BOOL,BOOL,BOOL,id))OFAsyncIdentityPrivateOriginal)(self,cmd,identity,reason,wait,ignore,early,completion);
}
static void OFInstallGuard(void) {
    Class cls = NSClassFromString(@"IXAppInstallCoordinator");
    if (!cls) return;
    OFHook(cls,YES,@"demoteAppToPlaceholderWithBundleID:forReason:error:",(IMP)OFSync3,&OFSync3Original,'b',"@q^");
    OFHook(cls,YES,@"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:error:",(IMP)OFSync4,&OFSync4Original,'b',"@qb^");
    OFHook(cls,YES,@"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:ignoreRemovability:error:",(IMP)OFSync5,&OFSync5Original,'b',"@qbb^");
    OFHook(cls,YES,@"demoteAppToPlaceholderWithApplicationIdentity:forReason:waitForDeletion:ignoreRemovability:error:",(IMP)OFSyncIdentity,&OFSyncIdentityOriginal,'b',"@qbb^");
    OFHook(cls,YES,@"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:completion:",(IMP)OFAsync4,&OFAsync4Original,'v',"@qbk");
    OFHook(cls,YES,@"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:ignoreRemovability:completion:",(IMP)OFAsync5,&OFAsync5Original,'v',"@qbbk");
    OFHook(cls,YES,@"_demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:ignoreRemovability:completion:",(IMP)OFAsyncPrivate,&OFAsyncPrivateOriginal,'v',"@qbbk");
    OFHook(cls,YES,@"demoteAppToPlaceholderWithApplicationIdentity:forReason:waitForDeletion:ignoreRemovability:completion:",(IMP)OFAsyncIdentity,&OFAsyncIdentityOriginal,'v',"@qbbk");
    OFHook(cls,YES,@"_demoteAppToPlaceholderWithApplicationIdentity:forReason:waitForDeletion:ignoreRemovability:returnEarlyForTesting:completion:",(IMP)OFAsyncIdentityPrivate,&OFAsyncIdentityPrivateOriginal,'v',"@qbbbk");
}
#ifndef OFFLOADER_HOST_TEST
__attribute__((constructor)) static void OFGuardStart(void) {
    @autoreleasepool {
        // Load first, so a not-yet-loaded private framework cannot silently skip hooks.
        dlopen("/System/Library/PrivateFrameworks/InstallCoordination.framework/InstallCoordination",RTLD_NOW);
        OFInstallGuard();
    }
}
#endif
