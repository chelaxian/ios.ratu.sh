//
//  Minimal vendored ControlCenterUIKit declarations.
//  The shipping iPhoneOS SDK only includes the .tbd; these headers declare just
//  the CCUIToggleModule surface a CC toggle module overrides. Extra base-class
//  members are intentionally omitted.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface CCUILayoutSize : NSObject <NSCopying>
@end

@interface CCUIContentModule : NSObject
- (void)refreshState;
@end

@interface CCUIToggleModule : CCUIContentModule
// Visual + state overrides implemented by toggle modules.
- (UIImage *)iconGlyph;            // glyph shown when NOT selected
- (UIImage *)selectedIconGlyph;     // glyph shown when selected
- (UIColor *)selectedColor;         // tile fill colour when selected
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;
// Re-evaluates isSelected / colors and refreshes the tile UI.
- (void)refreshState;
- (void)reconfigureView;
// Backing view controller whose .view hosts the tile (for gesture attachment).
@property (nonatomic, readonly) UIViewController *contentViewController;
@end
