#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CCUIToggleModule : NSObject
@property (nonatomic, readonly) UIViewController *contentViewController;
- (UIImage *)iconGlyph;
- (UIImage *)selectedIconGlyph;
- (UIColor *)selectedColor;
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;
- (void)refreshState;
- (void)reconfigureView;
@end

