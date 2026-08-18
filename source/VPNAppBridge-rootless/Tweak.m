#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <notify.h>

static NSString *const AVFPrefsPath = @"/var/mobile/Library/Preferences/com.snail.autovpnpref.plist";
static NSString *const AVFEventPath = @"/var/mobile/Library/Preferences/com.ratush.vpnbridge.event.plist";
static const char *AVFEventNotification = "com.ratush.vpnbridge.event";
static const char *AVFStateNotification = "com.ratush.vpnbridge.state";

static BOOL AVFDidBootstrap;
static NSString *AVFLastPostedBundle;
static NSString *AVFLastAction;
static NSTimeInterval AVFLastPostedAt;
static UIWindow *AVFIndicatorWindow;
static UILabel *AVFIndicatorLabel;
static void (*AVFOrigPostNotification)(NSNotificationCenter *, SEL, NSNotificationName, id, NSDictionary *);
static void (*AVFOrigSetText)(id, SEL, NSString *);

static NSString *AVFStringFromObject(id object);
static void AVFPrefsChanged(CFNotificationCenterRef center,
                            void *observer,
                            CFStringRef name,
                            const void *object,
                            CFDictionaryRef userInfo);

static NSDictionary *AVFPrefs(void) {
    NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:AVFPrefsPath];
    return [prefs isKindOfClass:NSDictionary.class] ? prefs : @{};
}

static BOOL AVFBool(NSDictionary *prefs, NSString *key, BOOL fallback) {
    id value = prefs[key];
    return value ? [value boolValue] : fallback;
}

static UIColor *AVFColorFromHex(NSString *hex) {
    if (![hex isKindOfClass:NSString.class]) {
        return [UIColor systemGreenColor];
    }
    NSString *clean = [[hex stringByReplacingOccurrencesOfString:@"#" withString:@""] uppercaseString];
    if (clean.length != 6) {
        return [UIColor systemGreenColor];
    }
    unsigned value = 0;
    [[NSScanner scannerWithString:clean] scanHexInt:&value];
    return [UIColor colorWithRed:((value >> 16) & 0xff) / 255.0
                           green:((value >> 8) & 0xff) / 255.0
                            blue:(value & 0xff) / 255.0
                           alpha:1.0];
}

static void AVFEnsureIndicator(void) {
    if (AVFIndicatorWindow) {
        return;
    }
    CGRect frame = CGRectMake(UIScreen.mainScreen.bounds.size.width - 76.0, 2.0, 52.0, 18.0);
    AVFIndicatorWindow = [[UIWindow alloc] initWithFrame:frame];
    AVFIndicatorWindow.windowLevel = UIWindowLevelStatusBar + 10.0;
    AVFIndicatorWindow.hidden = YES;
    AVFIndicatorWindow.userInteractionEnabled = NO;
    AVFIndicatorWindow.backgroundColor = UIColor.clearColor;

    AVFIndicatorLabel = [[UILabel alloc] initWithFrame:AVFIndicatorWindow.bounds];
    AVFIndicatorLabel.text = @"VPN";
    AVFIndicatorLabel.textAlignment = NSTextAlignmentCenter;
    AVFIndicatorLabel.font = [UIFont boldSystemFontOfSize:10.0];
    AVFIndicatorLabel.layer.cornerRadius = 5.0;
    AVFIndicatorLabel.layer.masksToBounds = YES;
    AVFIndicatorLabel.textColor = UIColor.whiteColor;
    [AVFIndicatorWindow addSubview:AVFIndicatorLabel];
}

static void AVFUpdateIndicator(BOOL vpnActive) {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *prefs = AVFPrefs();
        BOOL enabled = AVFBool(prefs, @"isEnabled", YES);
        BOOL show = enabled && vpnActive && AVFBool(prefs, @"isEnabledIndicator", YES);
        AVFEnsureIndicator();
        AVFIndicatorLabel.backgroundColor = AVFColorFromHex(prefs[@"indicatorColor"]);
        AVFIndicatorWindow.hidden = !show;
    });
}

static void AVFStateChanged(CFNotificationCenterRef center,
                            void *observer,
                            CFStringRef name,
                            const void *object,
                            CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    uint64_t state = 0;
    int token = 0;
    if (notify_register_check(AVFStateNotification, &token) == NOTIFY_STATUS_OK) {
        notify_get_state(token, &state);
        notify_cancel(token);
    }
    AVFUpdateIndicator(state == 1);
}

static BOOL AVFShouldIgnoreBundle(NSString *bundleID) {
    if (bundleID.length == 0) {
        return YES;
    }
    if ([bundleID isEqualToString:@"com.apple.Preferences"]) {
        return YES;
    }
    return NO;
}

static void AVFWriteEvent(NSString *action, NSString *bundleID) {
    if (action.length == 0) {
        return;
    }
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    if ([action isEqualToString:AVFLastAction] &&
        [bundleID isEqualToString:AVFLastPostedBundle] &&
        (now - AVFLastPostedAt) < 0.75) {
        return;
    }
    AVFLastAction = [action copy];
    AVFLastPostedBundle = [bundleID copy];
    AVFLastPostedAt = now;

    NSDictionary *prefs = AVFPrefs();
    NSDictionary *event = @{
        @"action": action,
        @"bundle": bundleID ?: @"",
        @"prefs": prefs ?: @{},
        @"timestamp": @(now)
    };
    [event writeToFile:AVFEventPath atomically:YES];
    notify_post(AVFEventNotification);
}

static void AVFPostCurrentApp(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
    if (!AVFShouldIgnoreBundle(bundleID)) {
        AVFWriteEvent(@"active", bundleID);
    }
}

static NSString *AVFBundleFromAny(id object, NSUInteger depth) {
    if (!object || depth > 4) {
        return nil;
    }
    if ([object isKindOfClass:NSString.class]) {
        NSString *value = object;
        return [value containsString:@"."] ? value : nil;
    }
    if ([object isKindOfClass:NSArray.class]) {
        for (id value in (NSArray *)object) {
            NSString *bundleID = AVFBundleFromAny(value, depth + 1);
            if (bundleID) {
                return bundleID;
            }
        }
        return nil;
    }
    if ([object isKindOfClass:NSDictionary.class]) {
        NSDictionary *dict = object;
        for (id key in dict) {
            NSString *keyString = [key isKindOfClass:NSString.class] ? key : @"";
            if ([keyString.lowercaseString containsString:@"bundle"] ||
                [keyString.lowercaseString containsString:@"identifier"]) {
                NSString *bundleID = AVFBundleFromAny(dict[key], depth + 1);
                if (bundleID) {
                    return bundleID;
                }
            }
        }
        return nil;
    }
    // NOTE: Do NOT call arbitrary selectors (e.g. -application) here. Private
    // framework objects such as MediaRemote's MRNotificationClient implement
    // generic selectors and can return non-object values; ARC's objc_retain on
    // such a return crashed SpringBoard deterministically
    // (EXC_BAD_ACCESS @ 0x4c4f434c, verified 2026-06-30). Only safe, well-known
    // string accessors are attempted below.
    return AVFStringFromObject(object);
}

static NSString *AVFStringFromObject(id object) {
    SEL selectors[] = {
        @selector(bundleIdentifier),
        @selector(displayIdentifier),
        @selector(applicationBundleIdentifier),
        @selector(bundleID),
        @selector(identifier)
    };
    for (NSUInteger i = 0; i < sizeof(selectors) / sizeof(selectors[0]); i++) {
        SEL selector = selectors[i];
        if ([object respondsToSelector:selector]) {
            id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
            id value = send(object, selector);
            if ([value isKindOfClass:NSString.class] && [value containsString:@"."]) {
                return value;
            }
        }
    }
    return nil;
}

static NSString *AVFActionForNotification(NSString *name, NSString *bundleID) {
    NSString *lower = name.lowercaseString ?: @"";
    if ([lower containsString:@"lock"] && ![lower containsString:@"unlock"]) {
        return @"lock";
    }
    if ([lower containsString:@"terminate"] ||
        [lower containsString:@"kill"] ||
        [lower containsString:@"delete"] ||
        [lower containsString:@"remove"]) {
        return bundleID.length ? @"killed" : nil;
    }
    if ([lower containsString:@"deactivate"] ||
        [lower containsString:@"suspend"] ||
        [lower containsString:@"background"]) {
        return bundleID.length ? @"background" : nil;
    }
    if ([lower containsString:@"activate"] ||
        [lower containsString:@"foreground"] ||
        [lower containsString:@"front"] ||
        [lower containsString:@"launch"] ||
        [lower containsString:@"workspace"] ||
        [lower containsString:@"application"]) {
        return bundleID.length ? @"active" : @"home";
    }
    return nil;
}

static void AVFPostNotification(NSNotificationCenter *self, SEL _cmd, NSNotificationName name, id object, NSDictionary *userInfo) {
    AVFOrigPostNotification(self, _cmd, name, object, userInfo);
    @autoreleasepool {
        NSString *notificationName = [name isKindOfClass:NSString.class] ? (NSString *)name : (name ? name.description : @"");

        // Gate on the notification NAME first, before touching object/userInfo.
        // Frameworks (e.g. MediaRemote) post constantly with non-object payloads;
        // probing those reflectively crashed SB. If the name is not a lifecycle
        // keyword we bail out and never inspect the payload.
        NSString *provisionalAction = AVFActionForNotification(notificationName, @"");
        if (!provisionalAction) {
            return;
        }

        NSString *bundleID = AVFBundleFromAny(object, 0) ?: AVFBundleFromAny(userInfo, 0) ?: @"";
        NSString *action = AVFActionForNotification(notificationName, bundleID);
        if (!action) {
            return;
        }
        if ([action isEqualToString:@"active"] && AVFShouldIgnoreBundle(bundleID)) {
            return;
        }
        AVFWriteEvent(action, bundleID);
    }
}

static void AVFSetText(id self, SEL _cmd, NSString *text) {
    NSDictionary *prefs = AVFPrefs();
    if (AVFBool(prefs, @"isHideOriginalVPN", NO) &&
        [text isKindOfClass:NSString.class] &&
        [text.uppercaseString containsString:@"VPN"]) {
        text = @"";
    }
    AVFOrigSetText(self, _cmd, text);
}

static void AVFInstallSetTextHook(NSString *className) {
    Class cls = NSClassFromString(className);
    Method method = class_getInstanceMethod(cls, @selector(setText:));
    if (method && !AVFOrigSetText) {
        AVFOrigSetText = (void *)method_setImplementation(method, (IMP)AVFSetText);
    }
}

static void AVFInstallSpringBoardObserver(void) {
    Method method = class_getInstanceMethod(NSNotificationCenter.class,
                                            @selector(postNotificationName:object:userInfo:));
    if (method) {
        AVFOrigPostNotification = (void *)method_setImplementation(method, (IMP)AVFPostNotification);
    }
    AVFInstallSetTextHook(@"UIStatusBarStringView");
    AVFInstallSetTextHook(@"_UIStatusBarStringView");
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    AVFStateChanged,
                                    CFSTR("com.ratush.vpnbridge.state"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    AVFPrefsChanged,
                                    CFSTR("com.snail.autovpnpref/ReloadPrefs"),
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    AVFUpdateIndicator(NO);
}

static void AVFPrefsChanged(CFNotificationCenterRef center,
                            void *observer,
                            CFStringRef name,
                            const void *object,
                            CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)name; (void)object; (void)userInfo;
    AVFWriteEvent(@"prefs", @"");
    AVFStateChanged(NULL, NULL, NULL, NULL, NULL);
}

static void AVFBootstrap(const char *entryPoint) {
    if (AVFDidBootstrap) {
        return;
    }
    AVFDidBootstrap = YES;
    (void)entryPoint;

    @autoreleasepool {
        NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier] ?: @"";
        NSString *processName = [[NSProcessInfo processInfo] processName] ?: @"";
        if ([bundleID isEqualToString:@"com.apple.springboard"] ||
            [processName isEqualToString:@"SpringBoard"]) {
            AVFInstallSpringBoardObserver();
            return;
        }

        AVFPostCurrentApp();
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *note) {
            AVFPostCurrentApp();
        }];
    }
}

__attribute__((constructor))
static void AVFInit(void) {
    AVFBootstrap("constructor");
}

__attribute__((used, visibility("default")))
void AVFStart(void) {
    AVFBootstrap("lc-init");
}

@interface AVFRootHideFixLoader : NSObject
@end

@implementation AVFRootHideFixLoader
+ (void)load {
    AVFBootstrap("+load");
}
@end
