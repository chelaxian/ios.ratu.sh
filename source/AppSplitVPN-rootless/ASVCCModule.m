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
            NSString *symbol=@"↗↙";
            [symbol drawInRect:CGRectMake(12,23,56,35) withAttributes:@{NSFontAttributeName:[UIFont boldSystemFontOfSize:24],NSForegroundColorAttributeName:UIColor.whiteColor}];
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
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    NSString *status=state[@"status"];
    return [prefs[@"enabled"] boolValue] && [@[@"active",@"partial"] containsObject:status];
}
- (void)setSelected:(BOOL)selected {
    (void)selected;
    notify_post(ASV_CMD_TOGGLE);
}
- (UIImage *)iconGlyph { return ASVGlyph(); }
- (UIImage *)selectedIconGlyph { return ASVGlyph(); }
- (UIColor *)selectedColor { return [UIColor colorWithRed:0.10 green:0.55 blue:0.75 alpha:1]; }
@end
