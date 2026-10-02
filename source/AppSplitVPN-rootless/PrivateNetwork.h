#import <Foundation/Foundation.h>
// Narrow declarations verified against the iOS 17.0 runtime. No Apple headers copied.
@interface NEPolicySession : NSObject
@property NSInteger priority;
- (NSUInteger)addPolicy:(id)policy;
- (BOOL)removeAllPolicies;
- (BOOL)apply;
@end
@interface NEPolicyCondition : NSObject
+ (instancetype)effectiveApplication:(NSUUID *)uuid;
+ (instancetype)realApplication:(NSUUID *)uuid;
+ (instancetype)allInterfaces;
@end
@interface NEPolicyResult : NSObject
+ (instancetype)scopeToDirectInterface;
+ (instancetype)skipWithOrder:(unsigned)order;
+ (instancetype)tunnelIPToInterfaceName:(NSString *)name secondaryResultType:(NSInteger)type;
+ (instancetype)drop;
@end
@interface NEPolicy : NSObject
- (instancetype)initWithOrder:(unsigned)order result:(id)result conditions:(NSArray *)conditions;
@end
@interface NEProcessInfo : NSObject
+ (NSArray<NSUUID *> *)copyUUIDsForBundleID:(NSString *)identifier uid:(unsigned)uid;
+ (NSArray<NSUUID *> *)copyUUIDsForExecutable:(NSString *)executable;
+ (void)clearUUIDCache;
@end
@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString *)identifier;
@property(readonly) NSArray *plugInKitPlugins;
@property(readonly) NSURL *bundleURL;
@end
