#import <UIKit/UIKit.h>
#import <notify.h>
#import "Shared.h"

@interface CCUIContentModule : NSObject
- (void)refreshState;
- (void)reconfigureView;
@end
@interface CCUIToggleModule : CCUIContentModule
- (UIImage *)iconGlyph;
- (UIImage *)selectedIconGlyph;
- (UIColor *)selectedColor;
- (BOOL)isSelected;
- (void)setSelected:(BOOL)selected;
@end

@interface ASVCCModule : CCUIToggleModule
@end

static __weak ASVCCModule *currentModule;
static void StateChanged(__unused CFNotificationCenterRef center,__unused void *observer,
                         __unused CFStringRef name,__unused const void *object,__unused CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [currentModule refreshState];
        if ([currentModule respondsToSelector:@selector(reconfigureView)]) [currentModule reconfigureView];
    });
}
static UIImage *ASVGlyph(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(80,80)];
        image=[[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
            [[UIColor whiteColor] setStroke];
            UIBezierPath *outline=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(8,10,64,60) cornerRadius:12];
            outline.lineWidth=5;[outline stroke];
            UIBezierPath *arrows=[UIBezierPath bezierPath];
            arrows.lineWidth=5;arrows.lineCapStyle=kCGLineCapRound;arrows.lineJoinStyle=kCGLineJoinRound;
            [arrows moveToPoint:CGPointMake(22,49)];[arrows addLineToPoint:CGPointMake(38,33)];
            [arrows moveToPoint:CGPointMake(29,33)];[arrows addLineToPoint:CGPointMake(38,33)];[arrows addLineToPoint:CGPointMake(38,42)];
            [arrows moveToPoint:CGPointMake(58,31)];[arrows addLineToPoint:CGPointMake(42,47)];
            [arrows moveToPoint:CGPointMake(42,38)];[arrows addLineToPoint:CGPointMake(42,47)];[arrows addLineToPoint:CGPointMake(51,47)];
            [arrows stroke];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    });
    return image;
}
@implementation ASVCCModule
+ (void)load {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,StateChanged,
        CFSTR(ASV_STATE_NOTIFY),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
}
- (instancetype)init { if ((self=[super init])) currentModule=self;return self; }
- (BOOL)isSelected {
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS];
    // This is the tweak's enable switch, not the VPN's connection indicator.
    // Keep it visibly on while waiting for a VPN so the next tap turns it off.
    return [prefs[@"enabled"] boolValue];
}
- (void)setSelected:(BOOL)selected {
    (void)selected;
    notify_post(ASV_CMD_TOGGLE);
}
- (UIImage *)iconGlyph { return ASVGlyph(); }
- (UIImage *)selectedIconGlyph { return ASVGlyph(); }
- (UIColor *)selectedColor { return [UIColor colorWithRed:0.10 green:0.55 blue:0.75 alpha:1]; }
@end
