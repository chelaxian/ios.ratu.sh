//
//  CCVPNOnOffAutoModule.m
//  CCVPN-ON-OFF-AUTO — Control Center tile (NO entitlement). Does NOT touch
//  NetworkExtension directly (the CC host is sandboxed and lacks the NE
//  entitlement, so nesessionmanager would reject it). Instead it forwards
//  short-tap / long-press to the privileged root daemon `ccvpnd` over Darwin
//  notifications, and mirrors the daemon's broadcast state:
//      off  -> dark tile, grey "VPN" glyph            (isSelected = NO)
//      vpn  -> green tile, white "VPN" glyph          (isSelected = YES)
//      auto -> blue tile, white "AUTO" glyph          (isSelected = YES) watchdog
//
//  Rendering: we override BOTH iconGlyph (off) and selectedIconGlyph (on/auto).
//  Glyphs are drawn in their final colour as AlwaysOriginal images, so the look
//  is identical regardless of how ControlCenterUIKit chooses to tint them.
//

#import "CCUIToggleModule.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

#define CMD_TAP    @"com.ratush.ccvpnonoffauto.cmd.tap"
#define CMD_LONG   @"com.ratush.ccvpnonoffauto.cmd.longpress"
#define CMD_QUERY  @"com.ratush.ccvpnonoffauto.cmd.query"
#define ST_OFF     @"com.ratush.ccvpnonoffauto.state.off"
#define ST_VPN     @"com.ratush.ccvpnonoffauto.state.vpn"
#define ST_AUTO    @"com.ratush.ccvpnonoffauto.state.auto"

#define kSuite     @"com.ratush.ccvpnonoffauto"
#define kLogKey    @"log"

#pragma mark - Darwin notifications

static void CCPost(NSString *name) {
    CFNotificationCenterPostNotification(
        CFNotificationCenterGetDarwinNotifyCenter(),
        (__bridge CFStringRef)name, NULL, NULL, YES);
}

NS_FORMAT_FUNCTION(1, 2)
static void CCLog(NSString *fmt, ...) {
    @try {
        va_list args; va_start(args, fmt);
        NSString *body = [[NSString alloc] initWithFormat:fmt arguments:args];
        va_end(args);
        NSUserDefaults *ud = [[NSUserDefaults alloc] initWithSuiteName:kSuite];
        NSMutableArray *a = [NSMutableArray arrayWithArray:[ud arrayForKey:kLogKey]];
        [a addObject:[NSString stringWithFormat:@"%@ %@", [NSDate date], body]];
        if (a.count > 80) [a removeObjectsInRange:NSMakeRange(0, a.count - 80)];
        [ud setObject:a forKey:kLogKey];
        [ud synchronize];
    } @catch (__unused id e) {}
}

#pragma mark - Glyph

static UIColor *OnGreen(void)  { return [UIColor colorWithRed:0.20 green:0.78 blue:0.35 alpha:1.0]; }
static UIColor *AutoBlue(void) { return [UIColor colorWithRed:0.13 green:0.51 blue:0.96 alpha:1.0]; }

// Draw text in a colour, returned as AlwaysOriginal so the framework cannot
// re-tint it. Sized for a 1x1 CC tile (glyph box ~80pt wide).
static UIImage *CCRenderText(NSString *t, CGFloat fs, UIColor *color) {
    CGSize sz = CGSizeMake(80, 80);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO; fmt.scale = 3.0;
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:sz format:fmt]
        imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
            p.alignment = NSTextAlignmentCenter;
            [t drawInRect:CGRectMake(0, (sz.height - fs) / 2.0, sz.width, fs)
                withAttributes:@{
                    NSFontAttributeName: [UIFont systemFontOfSize:fs weight:UIFontWeightHeavy],
                    NSForegroundColorAttributeName: color,
                    NSParagraphStyleAttributeName: p}];
        }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIImage *VPNImage(void) {
    static UIImage *img = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ img = CCRenderText(@"VPN", 20.0, [UIColor whiteColor]); });
    return img;
}

static UIImage *AutoImage(void) {
    static UIImage *aImg = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ aImg = CCRenderText(@"AUTO", 16.0, [UIColor whiteColor]); });
    return aImg;
}

#pragma mark - Module

@interface CCVPNOnOffAutoModule : CCUIToggleModule {
    int _mode;               // 0 = off, 1 = vpn, 2 = auto
    BOOL _attached;          // long-press gesture already on the tile view
    BOOL _didLongPress;      // swallow the synthetic tap that follows a hold
    CFTimeInterval _longPressAt;
    int _lpTries;            // retry counter for lazy view creation
}
- (void)cc_ensureLongPress;
- (void)cc_onLongPress:(UILongPressGestureRecognizer *)g;
@end

static __weak CCVPNOnOffAutoModule *sCurrent = nil;

@implementation CCVPNOnOffAutoModule

static void CCStateCallback(CFNotificationCenterRef center, void *observer,
                            CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    NSString *n = (__bridge NSString *)name;
    int mode = 0;
    if ([n hasSuffix:@".state.auto"]) mode = 2;
    else if ([n hasSuffix:@".state.vpn"]) mode = 1;
    dispatch_async(dispatch_get_main_queue(), ^{
        CCVPNOnOffAutoModule *m = sCurrent;
        if (!m) return;
        m->_mode = mode;
        // Re-evaluate isSelected / selectedColor / glyphs and force the tile
        // to repaint. reconfigureView additionally makes the host re-poll.
        @try { [m refreshState]; } @catch (__unused id e) {}
        @try { if ([m respondsToSelector:@selector(reconfigureView)]) [m reconfigureView]; } @catch (__unused id e) {}
    });
}

+ (void)load {
    NSArray *states = @[ST_OFF, ST_VPN, ST_AUTO];
    for (NSString *s in states) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), NULL, CCStateCallback,
            (__bridge CFStringRef)s, NULL,
            CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    CCLog(@"+load: observers registered, posting query");
    CCPost(CMD_QUERY);
}

- (instancetype)init {
    self = [super init];
    if (self) { sCurrent = self; }
    return self;
}

// Glyph shown when NOT selected (off): white "VPN" on the dark tile.
- (UIImage *)iconGlyph {
    sCurrent = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [self cc_ensureLongPress]; });
    if (_mode == 2) return AutoImage();
    return VPNImage();
}

// Glyph shown when SELECTED (on/auto): white "VPN" / white "AUTO".
- (UIImage *)selectedIconGlyph {
    sCurrent = self;
    return (_mode == 2) ? AutoImage() : VPNImage();
}

- (UIColor *)selectedColor {
    return (_mode == 2) ? AutoBlue() : OnGreen();
}

- (BOOL)isSelected { return _mode != 0; }

- (void)setSelected:(BOOL)selected {
    sCurrent = self;
    // A long-press ends in a touch-up that the host turns into a tap; swallow
    // it so holding the tile only toggles AUTO and never also flips the VPN.
    CFTimeInterval now = CACurrentMediaTime();
    if (_didLongPress || (now - _longPressAt) < 0.6) {
        _didLongPress = NO;
        CCLog(@"setSelected:%d swallowed (after long-press)", selected);
        return;
    }
    CCLog(@"setSelected:%d -> tap", selected);
    CCPost(CMD_TAP);
    dispatch_async(dispatch_get_main_queue(), ^{ [self cc_ensureLongPress]; });
}

#pragma mark - Long press -> AUTO

- (void)cc_ensureLongPress {
    if (_attached) return;
    UIViewController *vc = nil;
    @try {
        id o = [self valueForKey:@"contentViewController"];
        if ([o isKindOfClass:[UIViewController class]]) vc = o;
    } @catch (__unused id e) {}
    UIView *v = vc.view;
    if (![v isKindOfClass:[UIView class]]) {
        // The content view controller's view is created lazily; retry briefly.
        if (_lpTries++ < 20) {
            __weak typeof(self) ws = self;
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [ws cc_ensureLongPress]; });
        }
        return;
    }
    UILongPressGestureRecognizer *g =
        [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(cc_onLongPress:)];
    g.minimumPressDuration = 0.4;
    g.allowableMovement = 40.0;
    g.cancelsTouchesInView = NO;           // keep the normal tap working
    g.delaysTouchesBegan = NO;
    [v addGestureRecognizer:g];
    _attached = YES;
    CCLog(@"long-press gesture attached to contentViewController.view");
}

- (void)cc_onLongPress:(UILongPressGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateBegan) {
        _didLongPress = YES;
        _longPressAt = CACurrentMediaTime();
        CCLog(@"long-press -> AUTO toggle");
        CCPost(CMD_LONG);
    }
}

@end
