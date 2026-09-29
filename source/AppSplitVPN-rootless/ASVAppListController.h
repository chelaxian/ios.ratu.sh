#import <UIKit/UIKit.h>
@interface ASVAppListController : UITableViewController <UISearchResultsUpdating>
- (instancetype)initWithListKey:(NSString *)key language:(NSString *)language;
+ (NSUInteger)installedApplicationCount;
@end
