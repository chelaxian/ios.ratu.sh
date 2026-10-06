#define OFFLOADER_HOST_TEST 1
#define OF_PROTECTION_PATH ([NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"offloader-tests-%d/Protected.plist",getpid()]])
#import "../OFGuard.m"
#import "../OFNativeOffload.h"

static unsigned assertions, originalCalls;
static NSUInteger expectedNativeReason = 42;
#define CHECK(expression) do { ++assertions; if (!(expression)) { NSLog(@"FAIL line %d: %s",__LINE__,#expression); exit(1); } } while(0)
@interface OFTestIdentity : NSObject
@property(nonatomic,copy) NSString *bundleID;
@end
@implementation OFTestIdentity
@end
@interface IXAppInstallCoordinator : NSObject
+ (BOOL)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r error:(NSError **)e;
+ (BOOL)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w error:(NSError **)e;
+ (BOOL)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i error:(NSError **)e;
+ (BOOL)demoteAppToPlaceholderWithApplicationIdentity:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i error:(NSError **)e;
+ (void)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w completion:(void(^)(NSError *))c;
+ (void)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i completion:(void(^)(NSError *))c;
+ (void)_demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i completion:(void(^)(NSError *))c;
+ (void)demoteAppToPlaceholderWithApplicationIdentity:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i completion:(void(^)(NSError *))c;
+ (void)_demoteAppToPlaceholderWithApplicationIdentity:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i returnEarlyForTesting:(BOOL)t completion:(void(^)(NSError *))c;
@end
@implementation IXAppInstallCoordinator
+ (BOOL)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r error:(NSError **)e { ++originalCalls; if(e)*e=nil; return YES; }
+ (BOOL)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w error:(NSError **)e { ++originalCalls; CHECK(r==42); CHECK(w==YES); if(e)*e=nil; return YES; }
+ (BOOL)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i error:(NSError **)e { ++originalCalls; CHECK(r==expectedNativeReason); CHECK(w==YES); CHECK(i==NO); if(e)*e=nil; return YES; }
+ (BOOL)demoteAppToPlaceholderWithApplicationIdentity:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i error:(NSError **)e { ++originalCalls; CHECK(r==42); CHECK(w==YES); CHECK(i==NO); if(e)*e=nil; return YES; }
+ (void)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w completion:(void(^)(NSError *))c { ++originalCalls; CHECK(r==42); CHECK(w==YES); if(c)c(nil); }
+ (void)demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i completion:(void(^)(NSError *))c { ++originalCalls; CHECK(r==42); CHECK(w==YES); CHECK(i==NO); if(c)c(nil); }
+ (void)_demoteAppToPlaceholderWithBundleID:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i completion:(void(^)(NSError *))c { ++originalCalls; CHECK(r==42); CHECK(w==YES); CHECK(i==NO); if(c)c(nil); }
+ (void)demoteAppToPlaceholderWithApplicationIdentity:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i completion:(void(^)(NSError *))c { ++originalCalls; CHECK(r==42); CHECK(w==YES); CHECK(i==NO); if(c)c(nil); }
+ (void)_demoteAppToPlaceholderWithApplicationIdentity:(id)b forReason:(NSUInteger)r waitForDeletion:(BOOL)w ignoreRemovability:(BOOL)i returnEarlyForTesting:(BOOL)t completion:(void(^)(NSError *))c { ++originalCalls; CHECK(r==42); CHECK(w==YES); CHECK(i==NO); CHECK(t==NO); if(c)c(nil); }
@end
static void TestGuard(void) {
    OFInstallGuard();
    NSArray *selectors = @[
        @"demoteAppToPlaceholderWithBundleID:forReason:error:",
        @"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:error:",
        @"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:ignoreRemovability:error:",
        @"demoteAppToPlaceholderWithApplicationIdentity:forReason:waitForDeletion:ignoreRemovability:error:",
        @"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:completion:",
        @"demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:ignoreRemovability:completion:",
        @"_demoteAppToPlaceholderWithBundleID:forReason:waitForDeletion:ignoreRemovability:completion:",
        @"demoteAppToPlaceholderWithApplicationIdentity:forReason:waitForDeletion:ignoreRemovability:completion:",
        @"_demoteAppToPlaceholderWithApplicationIdentity:forReason:waitForDeletion:ignoreRemovability:returnEarlyForTesting:completion:"
    ];
    for (NSString *name in selectors) for (unsigned protected=0; protected<2; ++protected) for (unsigned nullResult=0; nullResult<2; ++nullResult) {
        NSString *bundle = protected ? @"com.test.protected" : @"com.test.allowed";
        id argument = bundle;
        if ([name containsString:@"ApplicationIdentity"]) { OFTestIdentity *identity = [OFTestIdentity new]; identity.bundleID=bundle; argument=identity; }
        SEL selector = NSSelectorFromString(name);
        NSMethodSignature *signature = [IXAppInstallCoordinator methodSignatureForSelector:selector];
        CHECK(signature != nil);
        NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
        invocation.target = IXAppInstallCoordinator.class; invocation.selector=selector;
        [invocation setArgument:&argument atIndex:2]; NSUInteger reason=42; [invocation setArgument:&reason atIndex:3];
        NSArray *labels = [name componentsSeparatedByString:@":"];
        for (NSUInteger i=4;i<signature.numberOfArguments-1;++i) { BOOL value=[labels[i-2] isEqual:@"waitForDeletion"]; [invocation setArgument:&value atIndex:i]; }
        __block unsigned callbacks=0; __block NSError *callbackError=nil;
        dispatch_semaphore_t finished=dispatch_semaphore_create(0);
        void(^completion)(NSError*)=^(NSError *error){++callbacks; callbackError=error; dispatch_semaphore_signal(finished);};
        if(nullResult)completion=nil;
        NSError *__autoreleasing error=nil; NSError *__autoreleasing *errorPointer = nullResult ? NULL : &error;
        BOOL async=[name hasSuffix:@"completion:"];
        [invocation setArgument:async ? (void *)&completion : (void *)&errorPointer atIndex:signature.numberOfArguments-1];
        unsigned previous=originalCalls; [invocation invoke];
        CHECK(originalCalls == previous + (protected ? 0 : 1));
        if(async) { if(!nullResult)CHECK(dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))==0); CHECK(callbacks == (nullResult ? 0 : 1)); if(!nullResult)CHECK(protected ? callbackError.code==1 : callbackError==nil); }
        else { BOOL result=NO; [invocation getReturnValue:&result]; CHECK(result==!protected); if(!nullResult)CHECK(protected ? error.code==1 : error==nil); }
    }
}
int main(void) { @autoreleasepool {
    CHECK(OFValidID(@"com.example.app-123")); CHECK(!OFValidID(@"../evil")); CHECK(!OFValidID(@"")); CHECK(!OFValidID(@42));
    CHECK(OFValueBool(@NO,YES)==NO); CHECK(OFValueBool(@"false",YES)==YES);
    CHECK(OFKind(@"com.example.delete",@"Delete App",NO)==OFActionOther);
    CHECK(OFKind(@"delete-app",@"Любой перевод",NO)==OFActionDelete);
    CHECK(OFKind(@"rearrange-icons",@"任意标题",NO)==OFActionEdit);
    CHECK(OFKind(@"com.apple.springboard.remove-app",nil,NO)==OFActionDelete);
    CHECK(OFKind(@"com.level3tjg.offloader/offload",nil,NO)==OFActionOffload);
    CHECK(OFKind(@"com.level3tjg.offloader/restart-appstored",nil,NO)==OFActionRestartStore);
    CHECK([OFLanguageFromValue(@"en") isEqual:@"en"]); CHECK([OFLanguageFromValue(@"ru") isEqual:@"ru"]);
    CHECK([@[@"en",@"ru"] containsObject:OFLanguageFromValue(nil)]); CHECK([@[@"en",@"ru"] containsObject:OFLanguageFromValue(@"de")]);
    CHECK([@[@"en",@"ru"] containsObject:OFLanguage()]);
    CHECK(OFShowKind(OFActionRestartStore,@{})); CHECK(!OFShowKind(OFActionRestartStore,@{@"3drestartstore":@NO}));
    CHECK(OFKind(@"unrelated",nil,YES)==OFActionDelete);
    for(unsigned mask=0;mask<8;++mask) {
        NSDictionary *prefs=@{@"3doffload":@((mask&1)!=0),@"3ddelete":@((mask&2)!=0),@"3dedit":@((mask&4)!=0)};
        CHECK(OFShowKind(OFActionOffload,prefs)==((mask&1)!=0)); CHECK(OFShowKind(OFActionDelete,prefs)==((mask&2)!=0)); CHECK(OFShowKind(OFActionEdit,prefs)==((mask&4)!=0)); CHECK(OFShowKind(OFActionOther,prefs));
    }
    CHECK(OFShowKind(OFActionDelete,@{}));
    NSDate *now=[NSDate dateWithTimeIntervalSince1970:1000];
    CHECK(OFRequestValid(@{@"id":@"123",@"bundle":@"com.example.app",@"date":now},now));
    CHECK(!OFRequestValid(@{@"id":@"123",@"bundle":@"../bad",@"date":now},now));
    CHECK(!OFRequestValid(@{@"id":@"123",@"bundle":@"com.example.app",@"date":[now dateByAddingTimeInterval:-46]},now));
    CHECK(!OFRequestValid(@{@"id":@"123",@"bundle":@"com.example.app",@"date":[now dateByAddingTimeInterval:6]},now));
    CHECK(!OFRequestValid(@{@"id":@"123",@"bundle":@"com.example.app",@"date":@"bad"},now));
    CHECK(!OFRequestValid(@[],now));
    CHECK(OFResponseMatches(@{@"id":@"123",@"ok":@NO,@"message":@"error"},@"123"));
    CHECK(!OFResponseMatches(@{@"id":@"stale",@"ok":@YES,@"message":@"ok"},@"123"));
    CHECK(!OFResponseMatches(@{@"id":@"123",@"message":@"ok"},@"123"));
    CHECK(!OFResponseMatches(@[],@"123"));
    CHECK(!OFCanCall(IXAppInstallCoordinator.class,@selector(description),'b',""));
    CHECK(!OFCanCall(IXAppInstallCoordinator.class,NSSelectorFromString(@"missing:"),'v',"@"));
    CHECK(OFCanCall(IXAppInstallCoordinator.class,NSSelectorFromString(@"demoteAppToPlaceholderWithBundleID:forReason:error:"),'b',"@q^"));
    CHECK(!OFCanCall(IXAppInstallCoordinator.class,NSSelectorFromString(@"demoteAppToPlaceholderWithBundleID:forReason:error:"),'v',"@q^"));
    CHECK(OFWriteProtectionSnapshot(@{@"com.test.protected":@YES,@"com.test.no":@NO,@"../bad":@YES,@"com.test.string":@"true"},NULL));
    CHECK(OFProtection().count==1); CHECK(OFProtected(@"com.test.protected")); CHECK(!OFProtected(@"com.test.no"));
    TestGuard();
    expectedNativeReason = 1;
    CHECK(OFDemotionReason == 1);
    unsigned beforeNative = originalCalls;
    NSError *nativeError = nil;
    CHECK(OFNativeDemote(@"com.test.allowed",&nativeError)); CHECK(nativeError == nil); CHECK(originalCalls == beforeNative + 1);
    CHECK(OFNativeDemote(@"com.test.allowed",NULL)); CHECK(originalCalls == beforeNative + 2);
    CHECK(!OFNativeDemote(@"com.test.protected",&nativeError)); CHECK([nativeError.domain isEqual:@"com.ratush.offloader"]); CHECK(originalCalls == beforeNative + 2);
    CHECK(!OFNativeDemote(@"../invalid",NULL)); CHECK(originalCalls == beforeNative + 2);
    CHECK(OFWriteProtectionSnapshot(@{},NULL)); CHECK(OFProtection().count==0); CHECK(!OFProtected(@"com.test.protected"));
    NSString *domain=[@"com.ratush.offloader.tests." stringByAppendingString:NSUUID.UUID.UUIDString];
    CHECK(OFWrite(domain,@"request",@{@"id":@"123",@"date":NSDate.date})); CHECK([OFPreferences(domain)[@"request"] isKindOfClass:NSDictionary.class]); CHECK(OFWrite(domain,@"request",nil)); CHECK(OFPreferences(domain)[@"request"]==nil);
    [NSFileManager.defaultManager removeItemAtPath:[OF_PROTECTION_PATH stringByDeletingLastPathComponent] error:NULL];
    printf("PASS: %u assertions; all nine IX routes protected/allowed, nil error/completion, eight toggle combinations, ABI checks, atomic snapshot and preferences round trip.\n",assertions);
    return 0;
} }
