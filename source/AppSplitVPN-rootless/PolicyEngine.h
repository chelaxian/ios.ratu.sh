#import "PrivateNetwork.h"
@interface ASVPolicyEngine : NSObject
@property(readonly) NSUInteger count;
@property(readonly) NSArray<NSString *> *unresolved;
@property(copy) NSArray<NSUUID *> *selfUUIDs;
- (BOOL)replaceMode:(NSString *)mode applications:(NSArray<NSString *> *)applications error:(NSString **)error;
- (BOOL)clear;
@end
