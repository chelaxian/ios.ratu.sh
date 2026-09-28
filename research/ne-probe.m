#import <Foundation/Foundation.h>
#import <dlfcn.h>
@interface NEPolicySession:NSObject
@property NSInteger priority;
- (NSUInteger)addPolicy:(id)p;
- (BOOL)apply;
- (id)dumpKernelPolicies;
@end
@interface NEPolicyResult:NSObject
+ (id)scopeToDirectInterface;
@end
@interface NEPolicyCondition:NSObject
+ (id)effectiveApplication:(id)uuid;
+ (id)allInterfaces;
@end
@interface NEPolicy:NSObject
- (id)initWithOrder:(unsigned)o result:(id)r conditions:(NSArray *)c;
@end
@interface NEProcessInfo:NSObject
+ (NSArray *)copyUUIDsForExecutable:(NSString *)s;
+ (NSArray *)copyUUIDsForBundleID:(NSString *)s uid:(unsigned)u;
@end
int main(int argc,char **argv) { @autoreleasepool {
 dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension",RTLD_NOW);
 NEPolicySession *s=[NSClassFromString(@"NEPolicySession") new]; s.priority=1;
 if(argc==1){ NSLog(@"%@",[s dumpKernelPolicies]); return 0; }
 NSString *target=@(argv[1]);
 NSArray *uuids=[target hasPrefix:@"/"]?[NSClassFromString(@"NEProcessInfo") copyUUIDsForExecutable:target]:[NSClassFromString(@"NEProcessInfo") copyUUIDsForBundleID:target uid:501];
 NSLog(@"UUIDs %@",uuids);
 for(id uuid in uuids) {
 id c=[NSClassFromString(@"NEPolicyCondition") effectiveApplication:uuid];
 id r=[NSClassFromString(@"NEPolicyResult") scopeToDirectInterface];
 id p=[[NSClassFromString(@"NEPolicy") alloc] initWithOrder:100 result:r conditions:@[c,[NSClassFromString(@"NEPolicyCondition") allInterfaces]]];
 NSLog(@"add=%lu policy=%@",(unsigned long)[s addPolicy:p],p);
 }
 NSLog(@"apply=%d session=%@",[s apply],s);
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:45]];
 NSLog(@"probe finished; rules released");
 } return 0; }
