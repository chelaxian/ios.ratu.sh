#import "PrivateNetwork.h"
@interface ASVPolicyEngine : NSObject
@property(readonly) NSUInteger count;
@property(readonly) NSArray<NSString *> *unresolved;
@property(copy) NSArray<NSUUID *> *selfUUIDs;
- (BOOL)replaceMode:(NSString *)mode applications:(NSArray<NSString *> *)applications error:(NSString **)error;
- (BOOL)clear;
- (BOOL)replaceMatrix:(NSDictionary<NSString *,NSString *> *)matrix interfaces:(NSDictionary<NSString *,NSString *> *)interfaces providerIDs:(NSArray<NSString *> *)providers error:(NSString **)error;
@end
