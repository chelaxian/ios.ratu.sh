#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/runtime.h>
#import "Shared.h"

// In BYPASS, iOS keeps its VPN badge; in TUNNEL ONLY its system view is detached.
// Color the native badge in BYPASS and add a small badge beside Wi-Fi in the
// SpringBoard status bar when the system has removed the native one.

static uint64_t splitMode; // 0: inactive, 1: BYPASS, 2: TUNNEL ONLY
static BOOL colorOff;      // user switched the badge coloring off
static NSHashTable<UILabel *> *badges;
static NSHashTable<UIView *> *statusBars;
static NSString *const ASVBadgeText = @"VPN½";
static const void *ASVOriginalColorKey=&ASVOriginalColorKey;
static const NSInteger ASVTunnelBadgeTag=0x41535650;
static BOOL ASVApplyingColor;

static BOOL ASVIsVPNText(NSString *text) {
    return [text isEqualToString:@"VPN"] || [text isEqualToString:ASVBadgeText];
}

// Color the badge should have now; nil keeps whatever the system asked for.
static UIColor *ASVWantedColor(UILabel *label) {
    if (colorOff || !ASVIsVPNText(label.text)) return nil;
    if (splitMode==1) return UIColor.systemRedColor;
    if (splitMode==2) return UIColor.systemGreenColor;
    return nil;
}

static uint64_t ASVReadState(BOOL *noColor) {
    static int token = -1;
    if (token < 0 && notify_register_check(ASV_STATE_NOTIFY, &token) != NOTIFY_STATUS_OK) { *noColor=NO; return 0; }
    uint64_t value = 0;
    notify_get_state(token, &value);
    *noColor=(value & 4)!=0;
    value&=3;
    return value <= 2 ? value : 0;
}

static void ASVStyleNativeBadge(UILabel *label) {
    if (!label) return;
    UIColor *original=objc_getAssociatedObject(label,ASVOriginalColorKey);
    if (!original) {
        original=label.textColor;
        if (original) objc_setAssociatedObject(label,ASVOriginalColorKey,original,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    UIColor *color=ASVWantedColor(label) ?: original;
    if (color && ![label.textColor isEqual:color]) {
        ASVApplyingColor=YES;
        label.textColor=color;
        ASVApplyingColor=NO;
    }
}

static NSString *ASVBadge(UILabel *label, NSString *text) {
    if (![text isEqualToString:@"VPN"] && ![text isEqualToString:ASVBadgeText]) {
        [badges removeObject:label];
        return text;
    }
    [badges addObject:label];
    return splitMode ? ASVBadgeText : @"VPN";
}

static UIView *ASVFindAnchor(UIView *view, Class wanted) {
    if ([view isKindOfClass:wanted]) return view;
    for (UIView *child in view.subviews) {
        UIView *found=ASVFindAnchor(child,wanted);
        if (found) return found;
    }
    return nil;
}

// Neutral badge color when coloring is off: follow the clock's current tint.
static UIColor *ASVNeutralColor(UIView *foreground) {
    Class stringClass=NSClassFromString(@"STUIStatusBarStringView");
    NSMutableArray *queue=[NSMutableArray arrayWithObject:foreground];
    while (queue.count) {
        UIView *view=queue.firstObject;[queue removeObjectAtIndex:0];
        if (stringClass && [view isKindOfClass:stringClass] && !ASVIsVPNText(((UILabel *)view).text) && ((UILabel *)view).textColor)
            return ((UILabel *)view).textColor;
        [queue addObjectsFromArray:view.subviews];
    }
    return UIColor.labelColor;
}

static void ASVPlaceTunnelBadge(UIView *statusBar) {
    Class foregroundClass=NSClassFromString(@"STUIStatusBarForegroundView");
    if (!foregroundClass) return;
    UIView *foreground=ASVFindAnchor(statusBar,foregroundClass);
    if (!foreground) return;
    UILabel *badge=(UILabel *)[foreground viewWithTag:ASVTunnelBadgeTag];
    if (splitMode!=2) { [badge removeFromSuperview];return; }
    Class wifiClass=NSClassFromString(@"STUIStatusBarWifiSignalView");
    Class cellularClass=NSClassFromString(@"STUIStatusBarCellularSignalView");
    UIView *anchor=wifiClass?ASVFindAnchor(foreground,wifiClass):nil;
    if (!anchor && cellularClass) anchor=ASVFindAnchor(foreground,cellularClass);
    if (!anchor || !anchor.superview) return;
    UIView *row=anchor.superview;
    CGFloat right=CGRectGetMaxX(anchor.frame);
    for (UIView *sibling in row.subviews)
        if (sibling!=badge && !sibling.hidden) right=MAX(right,CGRectGetMaxX(sibling.frame));
    CGRect position=[row convertRect:CGRectMake(right+3,anchor.frame.origin.y-1,43,18) toView:foreground];
    if (!badge) {
        badge=[[UILabel alloc] initWithFrame:position];badge.tag=ASVTunnelBadgeTag;
        badge.text=ASVBadgeText;badge.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        badge.textAlignment=NSTextAlignmentCenter;badge.textColor=UIColor.systemGreenColor;
        badge.backgroundColor=UIColor.clearColor;badge.layer.cornerRadius=5;
        badge.layer.borderWidth=1.25;badge.layer.borderColor=UIColor.systemGreenColor.CGColor;
        badge.userInteractionEnabled=NO;[foreground addSubview:badge];
    } else badge.frame=position;
    UIColor *tint=colorOff?ASVNeutralColor(foreground):UIColor.systemGreenColor;
    if (![badge.textColor isEqual:tint]) { badge.textColor=tint;badge.layer.borderColor=tint.CGColor; }
}

%hook STUIStatusBarStringView
- (void)setText:(NSString *)text {
    NSString *badge = ASVBadge((UILabel *)self, text);
    %orig(badge);
    if ([badges containsObject:(UILabel *)self] || objc_getAssociatedObject((UILabel *)self,ASVOriginalColorKey)) ASVStyleNativeBadge((UILabel *)self);
}
// The status bar re-applies its style (Control Center, appearance changes)
// after the text is set; remember its color and keep the split color on top.
- (void)setTextColor:(UIColor *)color {
    if (!ASVApplyingColor && color) {
        objc_setAssociatedObject((UILabel *)self,ASVOriginalColorKey,color,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        color=ASVWantedColor((UILabel *)self) ?: color;
    }
    %orig(color);
}
- (void)didMoveToWindow {
    %orig;
    if ([badges containsObject:(UILabel *)self]) ASVStyleNativeBadge((UILabel *)self);
}
%end

%hook _UIStatusBarStringView
- (void)setText:(NSString *)text {
    NSString *badge = ASVBadge((UILabel *)self, text);
    %orig(badge);
    if ([badges containsObject:(UILabel *)self] || objc_getAssociatedObject((UILabel *)self,ASVOriginalColorKey)) ASVStyleNativeBadge((UILabel *)self);
}
- (void)setTextColor:(UIColor *)color {
    if (!ASVApplyingColor && color) {
        objc_setAssociatedObject((UILabel *)self,ASVOriginalColorKey,color,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        color=ASVWantedColor((UILabel *)self) ?: color;
    }
    %orig(color);
}
- (void)didMoveToWindow {
    %orig;
    if ([badges containsObject:(UILabel *)self]) ASVStyleNativeBadge((UILabel *)self);
}
%end

%hook STUIStatusBar
- (void)layoutSubviews {
    %orig;
    [statusBars addObject:(UIView *)self];
    ASVPlaceTunnelBadge((UIView *)self);
}
%end

%ctor {
    // App extensions and UIKit-using daemons have no status bar of their own.
    // Keep the badge in every full app (including SpringBoard), but avoid
    // installing its hooks in widgets, notifications, and other extensions.
    if (![[[NSBundle mainBundle] bundlePath] hasSuffix:@".app"]) return;
    badges = [NSHashTable weakObjectsHashTable];
    statusBars = [NSHashTable weakObjectsHashTable];
    splitMode = ASVReadState(&colorOff);
    int token;
    notify_register_dispatch(ASV_STATE_NOTIFY, &token, dispatch_get_main_queue(), ^(__unused int t) {
        BOOL noColor=NO;
        uint64_t now = ASVReadState(&noColor);
        if (now == splitMode && noColor == colorOff) return;
        splitMode = now;
        colorOff = noColor;
        for (UILabel *label in badges.allObjects) {
            label.text = label.text;
            ASVStyleNativeBadge(label);
            [label invalidateIntrinsicContentSize];
            [label.superview setNeedsLayout];
        }
        for (UIView *statusBar in statusBars.allObjects) {
            ASVPlaceTunnelBadge(statusBar);
            [statusBar setNeedsLayout];
        }
    });
    %init;
}
