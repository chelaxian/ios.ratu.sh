#import <UIKit/UIKit.h>
// Ordered selection for reserves, or a single profile picker for a matrix assignment.
@interface ASVProfileListController : UITableViewController <UISearchResultsUpdating>
- (instancetype)initForReserves;
- (instancetype)initWithSelection:(NSString *)uuid completion:(void (^)(NSString *uuid))completion;
@end
