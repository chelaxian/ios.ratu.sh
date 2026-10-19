#import <UIKit/UIKit.h>
#import <notify.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import "CCUIToggleModule.h"
extern char **environ;

@interface SERVICE_CLASS : CCUIToggleModule {
    NSInteger _state;
    int _token;
    NSTimer *_timer;
    UILabel *_label;
    BOOL _busy;
    CFTimeInterval _lastTap;
}
@end
@implementation SERVICE_CLASS
- (instancetype)init {
    if ((self = [super init])) {
        _token = NOTIFY_TOKEN_INVALID;
        __weak typeof(self) weak = self;
        notify_register_dispatch(SERVICE_NOTIFICATION, &_token, dispatch_get_main_queue(), ^(int token) {
            uint64_t value = 0;
            if (notify_get_state(token, &value) == NOTIFY_STATUS_OK) {
                typeof(self) me = weak;
                if (!me) return;
                me->_state = value;
                [me updateLabel];
                [me refreshState];
                if ([me respondsToSelector:@selector(reconfigureView)]) [me reconfigureView];
            }
        });
        _timer = [NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(__unused NSTimer *timer) {
            [weak runCommand:@"status"];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{ [weak updateLabel]; [weak runCommand:@"status"]; });
    }
    return self;
}
- (void)dealloc { [_timer invalidate]; if (_token != NOTIFY_TOKEN_INVALID) notify_cancel(_token); }
- (BOOL)isSelected { return _state == 1; }
- (UIColor *)selectedColor { return UIColor.whiteColor; }
- (UIImage *)iconGlyph {
    [self updateLabel];
    static UIImage *blank; static dispatch_once_t once;
    dispatch_once(&once, ^{
        blank = [[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40,40)] imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {}] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    });
    return blank;
}
- (UIImage *)selectedIconGlyph { return [self iconGlyph]; }
- (void)updateLabel {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self updateLabel]; }); return; }
    UIViewController *vc = nil;
    @try { id value = [self valueForKey:@"contentViewController"]; if ([value isKindOfClass:UIViewController.class]) vc = value; } @catch (__unused NSException *error) {}
    UIView *view = vc.view;
    if (!view) return;
    if (_label.superview != view) {
        [_label removeFromSuperview];
        _label = [[UILabel alloc] initWithFrame:view.bounds];
        _label.textAlignment = NSTextAlignmentCenter;
        _label.font = [UIFont systemFontOfSize:17 weight:UIFontWeightHeavy];
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = .6;
        _label.userInteractionEnabled = NO;
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [view addSubview:_label];
    }
    _label.frame = view.bounds;
    _label.text = _state == 3 ? @"!" SERVICE_TEXT : (_state == 2 ? SERVICE_TEXT @"·L" : SERVICE_TEXT);
    _label.textColor = [self isSelected] ? SERVICE_ACTIVE_TEXT_COLOR : UIColor.whiteColor;
    _label.alpha = 1;
    [view bringSubviewToFront:_label];
    view.accessibilityLabel = SERVICE_NAME;
    view.accessibilityValue = _state == 1 ? @"Включено" : (_state == 2 ? @"Только localhost" : (_state == 3 ? @"Ошибка" : @"Выключено"));
}
- (void)runCommand:(NSString *)command {
    if (_busy) return;
    _busy = YES;
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        const char *path = SERVICE_HELPER;
        char *args[] = {(char *)path, (char *)command.UTF8String, NULL};
        pid_t pid = 0; int status = 0;
        int rc = posix_spawn(&pid, path, NULL, NULL, args, environ);
        if (!rc) { while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {} }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) me = weak;
            if (me) { me->_busy = NO; if (rc) { me->_state = 3; [me refreshState]; [me updateLabel]; } }
        });
    });
}
- (void)setSelected:(BOOL)selected {
    (void)selected;
    CFTimeInterval now = [NSProcessInfo processInfo].systemUptime;
    if (now - _lastTap < .6 || _busy) return;
    _lastTap = now;
    [self runCommand:@"toggle"];
}
@end
