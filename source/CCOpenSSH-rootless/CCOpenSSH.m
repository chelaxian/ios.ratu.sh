#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <unistd.h>
#import "CCUIToggleModule.h"

extern char **environ;

@interface CCOpenSSH : CCUIToggleModule {
    BOOL _running;
    UILabel *_label;
    NSInteger _tries;
    NSTimeInterval _lastTap;
}
@end

@implementation CCOpenSSH

static int ConfiguredPort(void) {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.ratush.ccopenssh.plist"];
    NSNumber *n = d[@"port"];
    int p = n ? n.intValue : 2222;
    return (p > 0 && p < 65536) ? p : 2222;
}

static BOOL PortOpen(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons((uint16_t)port);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    BOOL ok = connect(fd, (struct sockaddr *)&a, sizeof(a)) == 0;
    close(fd);
    return ok;
}

static UIImage *BlankGlyph(void) {
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    return [[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(80, 80) format:fmt]
        imageWithActions:^(__unused UIGraphicsImageRendererContext *ctx) {}]
        imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

- (BOOL)isSelected { return _running; }
- (UIColor *)selectedColor { return [UIColor colorWithRed:0.18 green:0.55 blue:0.94 alpha:1.0]; }
- (UIImage *)iconGlyph { [self updateLabel]; return BlankGlyph(); }
- (UIImage *)selectedIconGlyph { [self updateLabel]; return BlankGlyph(); }

- (void)repaint {
    [self updateLabel];
    if ([self respondsToSelector:@selector(refreshState)]) [self performSelectorOnMainThread:@selector(refreshState) withObject:nil waitUntilDone:NO];
    if ([self respondsToSelector:@selector(reconfigureView)]) [self performSelectorOnMainThread:@selector(reconfigureView) withObject:nil waitUntilDone:NO];
}

- (void)applyState:(BOOL)on {
    if (_running == on) { [self updateLabel]; return; }
    _running = on;
    [self repaint];
}

- (void)updateLabel {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateLabel]; });
        return;
    }
    UIViewController *vc = nil;
    @try {
        id obj = [self valueForKey:@"contentViewController"];
        if ([obj isKindOfClass:UIViewController.class]) vc = obj;
    } @catch (__unused NSException *e) {}
    UIView *v = vc.view;
    if (![v isKindOfClass:UIView.class]) {
        if (_tries++ < 300) dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [self updateLabel]; });
        return;
    }
    if (!_label || _label.superview != v) {
        [_label removeFromSuperview];
        _label = [[UILabel alloc] initWithFrame:v.bounds];
        _label.text = @"SSH";
        _label.textAlignment = NSTextAlignmentCenter;
        _label.backgroundColor = UIColor.clearColor;
        _label.userInteractionEnabled = YES;
        _label.adjustsFontSizeToFitWidth = YES;
        _label.minimumScaleFactor = 0.65;
        _label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _label.font = [UIFont systemFontOfSize:18 weight:UIFontWeightHeavy];
        _label.layer.zPosition = 999;
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(labelTap:)];
        tap.cancelsTouchesInView = NO;
        [_label addGestureRecognizer:tap];
        [v addSubview:_label];
    }
    _label.frame = v.bounds;
    _label.textColor = _running
        ? [UIColor colorWithRed:0.72 green:0.56 blue:0.06 alpha:1.0]
        : UIColor.whiteColor;
    [v bringSubviewToFront:_label];
}

static NSString *HelperPath(id obj) { return @"/var/jb/usr/bin/ccopenssh"; }

static void Spawn(NSString *arg, id obj) {
    NSString *h = HelperPath(obj);
    const char *path = h.fileSystemRepresentation;
    char *argv[] = { (char *)path, (char *)arg.UTF8String, NULL };
    pid_t pid = 0;
    posix_spawn(&pid, path, NULL, NULL, argv, environ);
}

- (void)toggle {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastTap < 0.8) return;
    _lastTap = now;
    BOOL live = PortOpen(ConfiguredPort());
    [self applyState:!live];
    Spawn(live ? @"off" : @"on", self);
}

- (void)labelTap:(UITapGestureRecognizer *)g { if (g.state == UIGestureRecognizerStateEnded) [self toggle]; }
- (void)setSelected:(BOOL)selected { (void)selected; [self toggle]; }

- (void)poll {
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (YES) {
            BOOL on = PortOpen(ConfiguredPort());
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) me = weakSelf;
                if (me) [me applyState:on];
            });
            [NSThread sleepForTimeInterval:2.0];
        }
    });
}

- (instancetype)init {
    if ((self = [super init])) {
        _running = PortOpen(ConfiguredPort());
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateLabel]; });
        [self poll];
    }
    return self;
}

@end
