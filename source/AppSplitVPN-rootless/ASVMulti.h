#import "PolicyEngine.h"
@interface ASVMulti : NSObject
@property(readonly) BOOL busy;
@property(readonly) BOOL ownsProfiles;
@property(readonly) NSString *status;
@property(readonly) NSString *error;
@property(readonly) NSString *names;
- (instancetype)initWithEngine:(ASVPolicyEngine *)engine;
- (void)tickMatrix:(NSDictionary *)matrix enabled:(BOOL)enabled;
- (void)restoreWithCompletion:(void (^)(BOOL))completion;
@end
