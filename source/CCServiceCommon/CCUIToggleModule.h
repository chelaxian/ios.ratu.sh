#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CCUIToggleModule : NSObject
- (UIImage *)iconGlyph;
- (UIImage *)selectedIconGlyph;
- (UIColor *)selectedColor;
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;
- (void)refreshState;
- (void)reconfigureView;
- (UIViewController *)contentViewControllerForContext:(id)context;
@end
