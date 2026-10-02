#import <UIKit/UIKit.h>
#import <notify.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "Shared.h"

// In BYPASS, iOS keeps its VPN badge; in TUNNEL ONLY its system view is detached.
// Color the native badge in BYPASS and add a small badge beside Wi-Fi in the
// SpringBoard status bar when the system has removed the native one.

static uint64_t splitMode; // 0: inactive, 1: BYPASS, 2: TUNNEL ONLY
static BOOL colorOff;      // user switched the badge coloring off
static NSUInteger activeCount;
static NSHashTable<UILabel *> *badges;
static NSHashTable<UIView *> *statusBars;
static NSString *const ASVBadgeText = @"VPN½";
static const void *ASVOriginalColorKey=&ASVOriginalColorKey;
static const NSInteger ASVTunnelBadgeTag=0x41535650;
static BOOL ASVApplyingColor;

static BOOL ASVIsVPNText(NSString *text) {
    return [text isEqualToString:@"VPN"] || [text isEqualToString:ASVBadgeText] || [text hasPrefix:@"VPN:"];
}
static NSString *ASVCurrentText(void){return splitMode==3?[NSString stringWithFormat:@"VPN:%lu",(unsigned long)activeCount]:ASVBadgeText;}

// Color the badge should have now; nil keeps whatever the system asked for.
static UIColor *ASVWantedColor(UILabel *label) {
    if (colorOff || !ASVIsVPNText(label.text)) return nil;
    if (splitMode==1) return UIColor.systemRedColor;
    if (splitMode==2) return UIColor.systemGreenColor;
    if (splitMode==3) return UIColor.systemBlueColor;
    return nil;
}

static uint64_t ASVReadState(BOOL *noColor) {
    static int token = -1;
    if (token < 0 && notify_register_check(ASV_STATE_NOTIFY, &token) != NOTIFY_STATUS_OK) { *noColor=NO; return 0; }
    uint64_t value = 0;
    notify_get_state(token, &value);
    *noColor=(value & 4)!=0;
    activeCount=(NSUInteger)((value>>8)&127);
    value&=3;
    return value;
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
    if (!ASVIsVPNText(text)) {
        [badges removeObject:label];
        return text;
    }
    [badges addObject:label];
    return splitMode ? ASVCurrentText() : @"VPN";
}

static UIView *ASVFindAnchor(UIView *view, Class wanted) {
    if ([view isKindOfClass:wanted]) return view;
    for (UIView *child in view.subviews) {
        UIView *found=ASVFindAnchor(child,wanted);
        if (found) return found;
    }
    return nil;
}
static BOOL ASVHasNativeBadge(UIView *view){
    if(view.hidden || view.alpha<0.01)return NO;
    if(view.tag!=ASVTunnelBadgeTag && [view isKindOfClass:UILabel.class] && ASVIsVPNText(((UILabel *)view).text))return YES;
    for(UIView *child in view.subviews)if(ASVHasNativeBadge(child))return YES;
    return NO;
}
static BOOL ASVNativeVPNEnabled(UIView *statusBar){
    // Native badges may be rasterized from a detached UILabel and have no view
    // in the live hierarchy. Consult the bar's actual display data as well.
    @try{
        for(NSString *name in @[@"currentAggregatedData",@"currentData"]){
            SEL getter=NSSelectorFromString(name);if(![statusBar respondsToSelector:getter])continue;
            id data=((id(*)(id,SEL))objc_msgSend)(statusBar,getter);SEL entry=NSSelectorFromString(@"vpnEntry");
            if(![data respondsToSelector:entry])continue;id vpn=((id(*)(id,SEL))objc_msgSend)(data,entry);
            SEL enabled=NSSelectorFromString(@"isEnabled");if([vpn respondsToSelector:enabled] && ((BOOL(*)(id,SEL))objc_msgSend)(vpn,enabled))return YES;
        }
    }@catch(__unused NSException *exception){}
    return NO;
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
    if (splitMode!=2 && splitMode!=3) { [badge removeFromSuperview];return; }
    // Never add a second indicator when the system is already rendering one.
    if(ASVNativeVPNEnabled(statusBar) || ASVHasNativeBadge(statusBar)){[badge removeFromSuperview];return;}
    Class wifiClass=NSClassFromString(@"STUIStatusBarWifiSignalView");
    Class cellularClass=NSClassFromString(@"STUIStatusBarCellularSignalView");
    UIView *anchor=wifiClass?ASVFindAnchor(foreground,wifiClass):nil;
    if (!anchor && cellularClass) anchor=ASVFindAnchor(foreground,cellularClass);
    if (!anchor || !anchor.superview) return;
    CGRect anchorFrame=[anchor.superview convertRect:anchor.frame toView:foreground];
    CGFloat nextLeft=CGRectGetMaxX(foreground.bounds)-3;
    // Ignore decorative backdrop/avoidance views: their frames span the screen.
    for(UIView *sibling in foreground.subviews){
        NSString *name=NSStringFromClass(sibling.class);
        if(sibling==badge || sibling==anchor || sibling.hidden || sibling.alpha<0.01 ||
           (![name hasPrefix:@"STUIStatusBar"] && ![name hasPrefix:@"_UIStatusBar"]))continue;
        if(CGRectGetMinX(sibling.frame)>=CGRectGetMaxX(anchorFrame)-1)nextLeft=MIN(nextLeft,CGRectGetMinX(sibling.frame));
    }
    CGRect position=CGRectMake(CGRectGetMaxX(anchorFrame)+3,anchorFrame.origin.y-1,43,18);
    if(CGRectGetMaxX(position)>nextLeft-3){
        // Dynamic Island leaves too little horizontal room. Keep the fallback
        // inside the 54pt bar, below the signal row, without moving native items.
        position=CGRectMake(MAX(3,MIN(CGRectGetMaxX(anchorFrame)-43,foreground.bounds.size.width-46)),
            MAX(0,MIN(CGRectGetMaxY(anchorFrame)+2,foreground.bounds.size.height-16)),43,16);
    }
    if (!badge) {
        badge=[[UILabel alloc] initWithFrame:position];badge.tag=ASVTunnelBadgeTag;
        badge.text=ASVCurrentText();badge.font=[UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
        badge.textAlignment=NSTextAlignmentCenter;badge.textColor=UIColor.systemGreenColor;
        badge.backgroundColor=UIColor.clearColor;badge.layer.cornerRadius=5;
        badge.layer.borderWidth=1.25;badge.layer.borderColor=UIColor.systemGreenColor.CGColor;
        badge.userInteractionEnabled=NO;[foreground addSubview:badge];
    } else badge.frame=position;
    badge.font=[UIFont systemFontOfSize:position.size.height<18?9:10 weight:UIFontWeightSemibold];
    badge.text=ASVCurrentText();
    UIColor *tint=colorOff?ASVNeutralColor(foreground):(splitMode==3?UIColor.systemBlueColor:UIColor.systemGreenColor);
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
        NSUInteger oldCount=activeCount;
        uint64_t now = ASVReadState(&noColor);
        if (now == splitMode && noColor == colorOff && oldCount==activeCount) return;
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
