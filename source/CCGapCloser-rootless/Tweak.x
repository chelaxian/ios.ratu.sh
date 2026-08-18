#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <unistd.h>

static NSString *const kCCGDomain = @"com.ratush.ccgapcloser";
static NSString *const kCCGReloadNotification = @"com.ratush.ccgapcloser.reload";
static NSString *const kCCGApplyNotification = @"com.ratush.ccgapcloser.apply";
static NSString *const kCCGRespringNotification = @"com.ratush.ccgapcloser.respring";

static NSString *const kKeyEnabled = @"enabled";
static NSString *const kKeyPortraitTop = @"portraitTopOffset";
static NSString *const kKeyLandscapeTop = @"landscapeTopOffset";
static NSString *const kKeyHideStatusBar = @"hideStatusBar";

static NSDictionary *gPrefs;
static BOOL gApplying;
static int gNotifyToken = 0;
static int gApplyToken = 0;
static int gRespringToken = 0;
static CGFloat gOriginalStatusBarWindowLevel = CGFLOAT_MIN;

static NSDictionary *CCGReadPrefs(void) {
    NSMutableDictionary *cfPrefs = [NSMutableDictionary dictionary];
    NSArray *keys = @[kKeyEnabled, kKeyPortraitTop, kKeyLandscapeTop, kKeyHideStatusBar];
    for (NSString *key in keys) {
        CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kCCGDomain);
        if (value) {
            cfPrefs[key] = (__bridge id)value;
            CFRelease(value);
        }
    }
    if (cfPrefs.count) return cfPrefs;

    NSArray *paths = @[
        @"/var/mobile/Library/Preferences/com.ratush.ccgapcloser.plist",
    ];
    for (NSString *path in paths) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if (prefs.count) return prefs;
    }
    return @{};
}

static void CCGLoadPrefs(void) {
    gPrefs = CCGReadPrefs();
}

static BOOL CCGBool(NSString *key, BOOL def) {
    id value = gPrefs[key];
    return value ? [value boolValue] : def;
}

static CGFloat CCGFloat(NSString *key, CGFloat def) {
    id value = gPrefs[key];
    return value ? [value doubleValue] : def;
}

static BOOL CCGEnabled(void) {
    return CCGBool(kKeyEnabled, YES);
}

static BOOL CCGShouldHideStatusBar(void) {
    return CCGBool(kKeyHideStatusBar, NO);
}

static BOOL CCGControlCenterWindowIsVisible(void) {
    @try {
        for (UIWindow *window in UIApplication.sharedApplication.windows) {
            NSString *name = NSStringFromClass(window.class);
            if ([name rangeOfString:@"ControlCenterWindow" options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
            if (!window.hidden && window.alpha > 0.01) return YES;
        }
    } @catch (__unused id e) {}
    return NO;
}

static BOOL CCGControlCenterIsActive(void) {
    if (CCGControlCenterWindowIsVisible()) return YES;

    @try {
        Class cls = NSClassFromString(@"SBControlCenterController");
        id controller = [cls respondsToSelector:@selector(sharedInstanceIfExists)] ? [cls performSelector:@selector(sharedInstanceIfExists)] : nil;
        if (!controller) return NO;

        BOOL visible = NO;
        if ([controller respondsToSelector:@selector(isVisible)]) {
            visible = ((BOOL (*)(id, SEL))objc_msgSend)(controller, @selector(isVisible));
        }
        if (!visible && [controller respondsToSelector:@selector(isPresented)]) {
            visible = ((BOOL (*)(id, SEL))objc_msgSend)(controller, @selector(isPresented));
        }
        if (!visible && [controller respondsToSelector:@selector(isPresentedOrDismissing)]) {
            visible = ((BOOL (*)(id, SEL))objc_msgSend)(controller, @selector(isPresentedOrDismissing));
        }
        return visible;
    } @catch (__unused id e) {
        return NO;
    }
}

static BOOL CCGShouldForceStatusBarVisible(void) {
    return CCGEnabled() && !CCGShouldHideStatusBar() && CCGControlCenterIsActive();
}

static BOOL CCGIsLandscapeForView(UIView *view) {
    CGSize size = view.window.bounds.size;
    if (size.width <= 0 || size.height <= 0) size = UIScreen.mainScreen.bounds.size;
    return size.width > size.height;
}

static CGFloat CCGTargetTopForView(UIView *view) {
    BOOL landscape = CCGIsLandscapeForView(view);
    CGFloat def = landscape ? 0.0 : 80.0;
    CGFloat value = CCGFloat(landscape ? kKeyLandscapeTop : kKeyPortraitTop, def);
    return MAX(0.0, value);
}

static BOOL CCGClassNameContains(UIView *view, NSArray<NSString *> *needles) {
    NSString *name = NSStringFromClass(view.class);
    for (NSString *needle in needles) {
        if ([name rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

static void CCGCollectViews(UIView *root,
                            NSMutableArray<UIView *> *scrolls,
                            NSMutableArray<UIView *> *collections,
                            NSMutableArray<UIView *> *modules,
                            NSMutableArray<UIView *> *headers,
                            NSMutableArray<UIView *> *statusWrappers) {
    if (!root) return;
    NSString *name = NSStringFromClass(root.class);
    if ([root isKindOfClass:UIScrollView.class] && CCGClassNameContains(root, @[@"CCUIScrollView"])) {
        [scrolls addObject:root];
    }
    if (CCGClassNameContains(root, @[@"ModuleCollection"])) {
        [collections addObject:root];
    }
    if (CCGClassNameContains(root, @[@"ContentModuleContainer", @"ModuleInstanceView", @"ModuleView"])) {
        [modules addObject:root];
    }
    if ([name rangeOfString:@"CCUIHeaderPocketView" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        [headers addObject:root];
    }
    if ([name rangeOfString:@"STUIStatusBar_Wrapper" options:NSCaseInsensitiveSearch].location != NSNotFound) {
        [statusWrappers addObject:root];
    }
    for (UIView *subview in root.subviews) CCGCollectViews(subview, scrolls, collections, modules, headers, statusWrappers);
}

static UIScrollView *CCGScrollAncestorForView(UIView *view) {
    UIView *cursor = view.superview;
    while (cursor) {
        if ([cursor isKindOfClass:UIScrollView.class]) return (UIScrollView *)cursor;
        cursor = cursor.superview;
    }
    return nil;
}

static void CCGResetModuleTransforms(NSArray<UIView *> *modules) {
    for (UIView *module in modules) {
        module.transform = CGAffineTransformIdentity;
    }
}

static CGFloat CCGAbsoluteY(UIView *view, UIView *root) {
    if (!view || !root) return CGFLOAT_MAX;
    return [view convertRect:view.bounds toView:root].origin.y;
}

// The Control Center top header pocket is always removed by the tweak (its
// core "close the gap" job). The "Hide status bar in CC" toggle controls
// whether the real status bar (operator/wifi/battery) is hidden inside CC.
// When shown, the SBStatusBarWindow is raised above CC (windowLevel 1100) and
// its top wrapper is pinned to y=0 — the same place it lives on the home
// screen — regardless of the module offset sliders.
static void CCGApplyHeaderPolicy(UIView *root, NSArray<UIView *> *headers, NSArray<UIView *> *statusWrappers) {
    BOOL hideStatusBar = CCGShouldHideStatusBar();

    for (UIView *header in headers) {
        header.hidden = YES;
        header.alpha = 0.0;
    }

    // Always show the top status-bar wrapper when not hidden; the window-level
    // raise in CCGApplyStatusBarWindowPolicy is what actually brings it above CC.
    for (UIView *wrapper in statusWrappers) {
        CGFloat y = CCGAbsoluteY(wrapper, root);
        if (y < 50.0) {
            wrapper.hidden = hideStatusBar;
            wrapper.alpha = hideStatusBar ? 0.0 : 1.0;
        } else {
            wrapper.hidden = YES;
            wrapper.alpha = 0.0;
        }
    }
}

static void CCGApplyStatusBarWindowPolicy(void) {
    if (!CCGEnabled()) return;
    BOOL hideStatusBar = CCGShouldHideStatusBar();

    for (UIWindow *window in UIApplication.sharedApplication.windows) {
        NSString *name = NSStringFromClass(window.class);
        if ([name rangeOfString:@"SBStatusBarWindow" options:NSCaseInsensitiveSearch].location == NSNotFound) continue;

        if (gOriginalStatusBarWindowLevel == CGFLOAT_MIN) {
            gOriginalStatusBarWindowLevel = window.windowLevel;
        }

        // Always raise the status-bar window above CC while the tweak is on;
        // the toggle only hides the wrapper content, not the window itself.
        window.hidden = NO;
        window.alpha = 1.0;
        window.windowLevel = 1100.0;

        for (UIView *subview in window.subviews) {
            NSString *subName = NSStringFromClass(subview.class);
            if ([subName rangeOfString:@"STUIStatusBar_Wrapper" options:NSCaseInsensitiveSearch].location != NSNotFound) {
                subview.hidden = hideStatusBar;
                subview.alpha = hideStatusBar ? 0.0 : 1.0;
                if (!hideStatusBar) {
                    CGRect frame = subview.frame;
                    frame.origin.y = 0.0;
                    subview.frame = frame;
                }
            }
        }
    }
}

static BOOL CCGRequestedStatusBarHidden(BOOL requestedHidden) {
    if (!CCGEnabled()) return requestedHidden;
    return CCGShouldHideStatusBar() ? YES : NO;
}

static void CCGApplyToRootView(UIView *root) {
    if (gApplying || !root || !CCGEnabled()) return;
    gApplying = YES;

    NSMutableArray<UIView *> *scrolls = [NSMutableArray array];
    NSMutableArray<UIView *> *collections = [NSMutableArray array];
    NSMutableArray<UIView *> *modules = [NSMutableArray array];
    NSMutableArray<UIView *> *headers = [NSMutableArray array];
    NSMutableArray<UIView *> *statusWrappers = [NSMutableArray array];
    CCGCollectViews(root, scrolls, collections, modules, headers, statusWrappers);

    CGFloat targetTop = CCGTargetTopForView(root);
    CCGApplyHeaderPolicy(root, headers, statusWrappers);
    CCGApplyStatusBarWindowPolicy();
    CCGResetModuleTransforms(modules);

    UIView *collection = collections.firstObject;
    UIScrollView *scroll = collection ? CCGScrollAncestorForView(collection) : (UIScrollView *)scrolls.firstObject;
    if (collection && scroll) {
        CGRect collectionFrame = collection.frame;
        CGFloat desiredOffsetY = collectionFrame.origin.y - targetTop;
        CGFloat desiredInsetTop = MAX(0.0, targetTop - collectionFrame.origin.y);

        UIEdgeInsets inset = scroll.contentInset;
        inset.top = desiredInsetTop;
        scroll.contentInset = inset;
        scroll.scrollIndicatorInsets = inset;
        scroll.contentOffset = CGPointMake(scroll.contentOffset.x, desiredOffsetY);
    }

    gApplying = NO;
}

static void CCGApplyToAllControlCenterWindows(void) {
    UIApplication *app = UIApplication.sharedApplication;
    for (UIWindow *window in app.windows) {
        if ([NSStringFromClass(window.class) rangeOfString:@"ControlCenter" options:NSCaseInsensitiveSearch].location != NSNotFound) {
            CCGApplyToRootView(window);
        }
    }
}

static void CCGApplySoon(UIView *view) {
    if (!view || !CCGEnabled()) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        CCGApplyToRootView(view);
    });
}

static void CCGRespring(void) {
    @try {
        Class cls = NSClassFromString(@"FBSystemService");
        id svc = [cls respondsToSelector:@selector(sharedService)] ? [cls performSelector:@selector(sharedService)] : nil;
        if (svc && [svc respondsToSelector:@selector(exitAndRelaunch:)]) {
            ((void (*)(id, SEL, id))objc_msgSend)(svc, @selector(exitAndRelaunch:), nil);
            return;
        }
    } @catch (__unused id e) {}
    _exit(0);
}

%group ControlCenterHooks

%hook CCUIModularControlCenterOverlayViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    CCGApplySoon(((UIViewController *)self).view);
}

- (void)viewDidLayoutSubviews {
    %orig;
    CCGApplySoon(((UIViewController *)self).view);
}
%end

%hook SBStatusBarWindow
- (void)layoutSubviews {
    %orig;
    CCGApplyStatusBarWindowPolicy();
}
%end

%hook STUIStatusBar_Wrapper
- (void)setAlpha:(CGFloat)alpha {
    %orig(CCGShouldForceStatusBarVisible() ? 1.0 : alpha);
}

- (void)setHidden:(BOOL)hidden {
    %orig(CCGShouldForceStatusBarVisible() ? NO : hidden);
}

- (void)didMoveToWindow {
    %orig;
    if (CCGShouldForceStatusBarVisible()) {
        UIView *view = (UIView *)self;
        view.hidden = NO;
        view.alpha = 1.0;
    }
}
%end

%hook SBControlCenterController
- (BOOL)_isStatusBarHiddenIgnoringControlCenter {
    if (CCGEnabled() && !CCGShouldHideStatusBar()) return NO;
    return %orig;
}

- (void)_setStatusBarHidden:(BOOL)hidden {
    %orig(CCGRequestedStatusBarHidden(hidden));
    CCGApplyStatusBarWindowPolicy();
}

- (void)controlCenterViewController:(id)viewController wantsHostStatusBarHidden:(BOOL)hidden {
    %orig(viewController, CCGRequestedStatusBarHidden(hidden));
    CCGApplyStatusBarWindowPolicy();
}

- (void)setHideStatusBarAssertion:(id)assertion {
    %orig(CCGShouldHideStatusBar() ? assertion : nil);
    CCGApplyStatusBarWindowPolicy();
}
%end

%hook CCUIModularControlCenterOverlayViewController
- (void)setOverlayStatusBarHidden:(BOOL)hidden {
    %orig(CCGRequestedStatusBarHidden(hidden));
    CCGApplyStatusBarWindowPolicy();
}
%end

%hook CCUIModularControlCenterViewController
- (void)viewDidLayoutSubviews {
    %orig;
    CCGApplySoon(((UIViewController *)self).view);
}
%end

%hook CCUIControlCenterViewController
- (void)viewDidLayoutSubviews {
    %orig;
    CCGApplySoon(((UIViewController *)self).view);
}
%end

%hook CCUIContentModuleContainerView
- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    CCGApplySoon(view.superview ?: view);
}
%end

%hook CCUIModuleCollectionView
- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    CCGApplySoon(view.window ?: view);
}

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    CCGApplySoon(view.window ?: view);
}
%end

%hook CCUIScrollView
- (void)didMoveToWindow {
    %orig;
    UIView *view = (UIView *)self;
    CCGApplySoon(view.window ?: view);
}

- (void)layoutSubviews {
    %orig;
    UIView *view = (UIView *)self;
    CCGApplySoon(view.window ?: view);
}
%end

%end

%ctor {
    @autoreleasepool {
        NSString *bundleID = NSBundle.mainBundle.bundleIdentifier ?: @"";
        if (![bundleID isEqualToString:@"com.apple.springboard"]) return;
        CCGLoadPrefs();
        notify_register_dispatch([kCCGReloadNotification UTF8String], &gNotifyToken, dispatch_get_main_queue(), ^(int token) {
            CCGLoadPrefs();
        });
        notify_register_dispatch([kCCGApplyNotification UTF8String], &gApplyToken, dispatch_get_main_queue(), ^(int token) {
            CCGLoadPrefs();
            CCGApplyToAllControlCenterWindows();
        });
        notify_register_dispatch([kCCGRespringNotification UTF8String], &gRespringToken, dispatch_get_main_queue(), ^(int token) {
            CCGRespring();
        });
        %init(ControlCenterHooks);
    }
}
