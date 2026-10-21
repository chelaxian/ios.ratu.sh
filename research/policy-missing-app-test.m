#define LSApplicationProxy ASVMockApplicationProxy
#import "../source/AppSplitVPN-rootless/PolicyEngine.h"
#import "../source/AppSplitVPN-rootless/ASVBundleIdentity.h"
#import <objc/runtime.h>
#include <stdlib.h>
static BOOL Reinstalled=NO;

// Exercise the actual PolicyEngine with private API test doubles. No kernel
// policies or real LaunchServices are accessed by this macOS regression test.
@implementation NEPolicySession
- (NSUInteger)addPolicy:(id)policy { return policy?1:0; }
- (BOOL)removeAllPolicies { return YES; }
- (BOOL)apply { return YES; }
@end
@implementation NEPolicyCondition
+ (instancetype)effectiveApplication:(NSUUID *)uuid { return uuid?[self new]:nil; }
+ (instancetype)realApplication:(NSUUID *)uuid { return uuid?[self new]:nil; }
+ (instancetype)allInterfaces { return [self new]; }
+ (instancetype)domain:(NSString *)domain { return domain.length?[self new]:nil; }
@end
@implementation NEPolicyResult
+ (instancetype)scopeToDirectInterface { return [self new]; }
+ (instancetype)skipWithOrder:(unsigned)order { (void)order;return [self new]; }
+ (instancetype)tunnelIPToInterfaceName:(NSString *)name secondaryResultType:(NSInteger)type { (void)name;(void)type;return [self new]; }
+ (instancetype)drop { return [self new]; }
+ (instancetype)netAgentUUID:(NSUUID *)uuid { return uuid?[self new]:nil; }
@end
@implementation NEPolicy
- (instancetype)initWithOrder:(unsigned)order result:(id)result conditions:(NSArray *)conditions { (void)order;return result && conditions.count?[super init]:nil; }
@end
@implementation NEProcessInfo
+ (void)clearUUIDCache {}
+ (NSArray *)copyUUIDsForBundleID:(NSString *)identifier uid:(unsigned)uid {
    (void)uid;
    if([identifier isEqual:@"throws"])[NSException raise:NSInvalidArgumentException format:@"Simulated updating record"];
    if([identifier isEqual:@"malformed"])return (id)@"not an array";
    return ([identifier isEqual:@"installed"] || (Reinstalled && [identifier isEqual:@"offloaded"]))?@[[[NSUUID alloc] initWithUUIDString:@"12345678-1234-1234-1234-123456789ABC"],@"invalid UUID"]:@[];
}
+ (NSArray *)copyUUIDsForExecutable:(NSString *)executable { (void)executable;return @[]; }
@end
@interface ASVTestProxy : LSApplicationProxy
@property(nonatomic) BOOL unavailable;
@end
@implementation LSApplicationProxy
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier {
    if([identifier isEqual:@"deleted"])return nil;
    ASVTestProxy *proxy=[ASVTestProxy new];proxy.unavailable=!([@[@"installed",@"throws",@"malformed",@"unresolved"] containsObject:identifier] || (Reinstalled && [identifier isEqual:@"offloaded"]));return proxy;
}
- (NSArray *)plugInKitPlugins { return @[]; }
- (NSURL *)bundleURL { return nil; }
@end
@implementation ASVTestProxy
- (NSURL *)bundleURL { return self.unavailable?nil:[NSBundle mainBundle].bundleURL; }
- (NSArray *)plugInKitPlugins { ASVTestProxy *plugin=[ASVTestProxy new];plugin.unavailable=YES;return self.unavailable?@[]:@[plugin]; }
@end
static void Check(BOOL ok,NSString *message) { if(!ok){NSLog(@"FAIL: %@",message);exit(1);} }
int main(void) { @autoreleasepool {
    // macOS itself loads LSApplicationProxy. Do not define a duplicate class:
    // replace only its factory in this disposable test process with our mock.
    Class live=NSClassFromString(@"LSApplicationProxy");
    Method factory=class_getClassMethod(ASVMockApplicationProxy.class,@selector(applicationProxyForIdentifier:));
    if(live)class_replaceMethod(object_getClass(live),@selector(applicationProxyForIdentifier:),method_getImplementation(factory),method_getTypeEncoding(factory));
    else objc_registerClassPair(objc_allocateClassPair(ASVMockApplicationProxy.class,"LSApplicationProxy",0));
    Check(ASVExecutableForBundleURL(nil)==nil,@"nil URL safely rejected");
    Check(ASVExecutableForBundleURL((id)@"invalid")==nil,@"wrong URL type safely rejected");
    Check(ASVExecutableForBundleURL([NSURL URLWithString:@"https://example.com"] )==nil,@"non-file URL rejected");
    Check(ASVExecutableForBundleURL(NSBundle.mainBundle.bundleURL).length>0,@"installed executable retained");
    for(NSString *mode in @[@"bypass",@"tunnelOnly"]) {
        ASVPolicyEngine *engine=[ASVPolicyEngine new];NSString *error=nil;
        Check([engine replaceMode:mode applications:@[@"installed",@"deleted",@"offloaded",@"throws",@"malformed",@"unresolved",@123] error:&error],mode);
        Check(engine.unresolved.count==6,@"bad/missing selections isolated");
        Check(engine.count==([mode isEqual:@"bypass"]?1:2),@"working application's policies preserved");
        Check([engine clear] && engine.count==0,@"owned policies cleaned");
        Reinstalled=YES;
        Check([engine replaceMode:mode applications:@[@"offloaded"] error:&error] && engine.unresolved.count==0,@"reinstalled selection resolves without editing preferences");
        Reinstalled=NO;
    }
    ASVPolicyEngine *matrix=[ASVPolicyEngine new];NSString *error=nil;
    ASVPolicyEngine *dns=[ASVPolicyEngine new];
    dns.directDNSRules=@[@{@"agent":NSUUID.UUID,@"domain":@"chatgpt.com"},@{@"agent":NSUUID.UUID,@"domain":@""}];
    Check([dns replaceMode:@"bypass" applications:@[@"installed",@"deleted"] error:&error] && dns.count==5,@"DNS gate, domain resolvers and direct fallback staged");
    Check([dns replaceMode:@"tunnelOnly" applications:@[@"installed"] error:&error] && dns.count==2,@"DNS option cannot alter TUNNEL ONLY");
    Check([dns clear] && !dns.directDNSRules.count,@"master clear releases DNS rules");
    Check([matrix replaceMatrix:@{@"installed":@"profile",@"deleted":@"profile",@"offloaded":@"profile",@"throws":@"profile",@"malformed":@"profile",@"unresolved":@"profile"} interfaces:@{@"profile":@"utun4"} providerIDs:@[] error:&error],@"MATRIX missing app/extension URL");
    Check(matrix.unresolved.count==5 && matrix.count==2,@"MATRIX retains valid assignment and fallback");
    NSLog(@"PASS: missing/deleted/offloaded apps and missing extension URLs in BYPASS, TUNNEL ONLY and MATRIX");
}return 0;}
