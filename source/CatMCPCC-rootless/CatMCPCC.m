// CatMCPCC Control Center toggle.
//
// The tile renders UI and spawns /usr/bin/catmcpcchelper. The helper owns the
// privileged launchctl/killall work. State is always re-read by connecting to
// 127.0.0.1:9000, which is the observable CatMCP server endpoint.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/socket.h>
#import <sys/wait.h>
#import <netinet/in.h>
#import <unistd.h>
#import <string.h>
#import <errno.h>
#import "CCUIToggleModule.h"

extern char **environ;

@interface CatMCPCC : CCUIToggleModule {
    BOOL _catmcpIsRunning;
    UILabel *_glyphOverlay;
    NSInteger _overlayAttachTries;
    NSTimeInterval _lastToggleAt;
}
@end

@implementation CatMCPCC

static void LifeLog(NSString *msg) {
    @autoreleasepool {
        NSString *line = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], msg];
        NSString *p = @"/var/mobile/Library/Preferences/com.ratush.catmcpcc.life.log";
        NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:p];
        if (!fh) { [line writeToFile:p atomically:YES encoding:NSUTF8StringEncoding error:nil]; return; }
        [fh seekToEndOfFile];
        [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]];
        [fh closeFile];
    }
}

+ (void)load { LifeLog(@"+load"); }

static UIImage *RenderText(NSString *t, CGFloat fs, UIColor *color) {
    CGSize sz = CGSizeMake(80, 80);
    UIGraphicsImageRendererFormat *fmt = [UIGraphicsImageRendererFormat defaultFormat];
    fmt.opaque = NO;
    fmt.scale = 3.0;
    UIImage *img = [[[UIGraphicsImageRenderer alloc] initWithSize:sz format:fmt]
        imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            NSMutableParagraphStyle *p = [NSMutableParagraphStyle new];
            p.alignment = NSTextAlignmentCenter;
            [t drawInRect:CGRectMake(0, (sz.height - fs) / 2.0, sz.width, fs)
              withAttributes:@{
                NSFontAttributeName: [UIFont systemFontOfSize:fs weight:UIFontWeightHeavy],
                NSForegroundColorAttributeName: color,
                NSParagraphStyleAttributeName: p
              }];
        }];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

static UIImage *BlankGlyph(void) {
    static UIImage *g = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        g = RenderText(@" ", 1, [UIColor clearColor]);
    });
    return g;
}

static BOOL CatMCPPortOpen(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return NO;
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(9000);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    BOOL ok = (connect(fd, (struct sockaddr *)&a, sizeof(a)) == 0);
    close(fd);
    return ok;
}

- (BOOL)isSelected {
    return _catmcpIsRunning;
}

- (UIColor *)selectedColor {
    return [UIColor colorWithRed:0.10 green:0.72 blue:0.32 alpha:1.0];
}

- (UIImage *)iconGlyph {
    [self updateGlyphOverlay];
    return BlankGlyph();
}

- (UIImage *)selectedIconGlyph {
    [self updateGlyphOverlay];
    return BlankGlyph();
}

- (void)repaint {
    [self updateGlyphOverlay];
    if ([self respondsToSelector:@selector(refreshState)]) {
        [self performSelectorOnMainThread:@selector(refreshState)
                               withObject:nil waitUntilDone:NO];
    }
    if ([self respondsToSelector:@selector(reconfigureView)]) {
        [self performSelectorOnMainThread:@selector(reconfigureView)
                               withObject:nil waitUntilDone:NO];
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateGlyphOverlay];
    });
}

- (void)applyState:(BOOL)on {
    if (_catmcpIsRunning == on) {
        [self updateGlyphOverlay];
        return;
    }
    _catmcpIsRunning = on;
    [self repaint];
}

- (void)updateGlyphOverlay {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateGlyphOverlay]; });
        return;
    }

    UIViewController *vc = nil;
    @try {
        id obj = [self valueForKey:@"contentViewController"];
        if ([obj isKindOfClass:[UIViewController class]]) vc = (UIViewController *)obj;
    } @catch (__unused NSException *e) {
        vc = nil;
    }

    UIView *view = vc.view;
    if (![view isKindOfClass:[UIView class]]) {
        if (_overlayAttachTries++ < 300) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{ [self updateGlyphOverlay]; });
        }
        return;
    }

    if (!_glyphOverlay || _glyphOverlay.superview != view) {
        [_glyphOverlay removeFromSuperview];
        _glyphOverlay = [[UILabel alloc] initWithFrame:view.bounds];
        _glyphOverlay.text = @"MCP";
        _glyphOverlay.textAlignment = NSTextAlignmentCenter;
        _glyphOverlay.backgroundColor = [UIColor clearColor];
        _glyphOverlay.userInteractionEnabled = YES;
        _glyphOverlay.adjustsFontSizeToFitWidth = YES;
        _glyphOverlay.minimumScaleFactor = 0.7;
        _glyphOverlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _glyphOverlay.font = [UIFont systemFontOfSize:18.0 weight:UIFontWeightHeavy];
        _glyphOverlay.layer.zPosition = 999.0;
        UITapGestureRecognizer *tap =
            [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(overlayTapped:)];
        tap.cancelsTouchesInView = NO;
        [_glyphOverlay addGestureRecognizer:tap];
        [view addSubview:_glyphOverlay];
        _overlayAttachTries = 0;
        LifeLog(@"glyph overlay attached");
    }

    _glyphOverlay.frame = view.bounds;
    _glyphOverlay.textColor = _catmcpIsRunning
        ? [UIColor colorWithRed:0.05 green:0.38 blue:1.0 alpha:1.0]
        : [UIColor whiteColor];
    _glyphOverlay.hidden = NO;
    [view bringSubviewToFront:_glyphOverlay];
}

static NSString *HelperPathForObject(id obj) {
    return @"/var/jb/usr/bin/catmcpcchelper";
}

static void SpawnHelper(NSString *helper) {
    const char *path = helper.fileSystemRepresentation;
    char *argv[] = { (char *)path, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, path, NULL, NULL, argv, environ);
    if (rc != 0) {
        LifeLog([NSString stringWithFormat:@"spawn helper failed path=%@ rc=%d errno=%d", helper, rc, errno]);
        return;
    }
    LifeLog([NSString stringWithFormat:@"spawn helper pid=%d path=%@", (int)pid, helper]);
}

- (void)triggerToggle:(NSString *)source {
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastToggleAt < 0.8) {
        LifeLog([NSString stringWithFormat:@"toggle swallowed source=%@", source]);
        return;
    }
    _lastToggleAt = now;

    BOOL current = CatMCPPortOpen();
    _catmcpIsRunning = current;
    LifeLog([NSString stringWithFormat:@"toggle source=%@ current=%d", source, (int)current]);
    [self applyState:!current];
    SpawnHelper(HelperPathForObject(self));
}

- (void)overlayTapped:(UITapGestureRecognizer *)g {
    if (g.state == UIGestureRecognizerStateEnded) {
        [self triggerToggle:@"gesture"];
    }
}

- (void)setSelected:(BOOL)selected {
    LifeLog([NSString stringWithFormat:@"setSelected:%d current=%d", (int)selected, (int)_catmcpIsRunning]);
    [self triggerToggle:@"setSelected"];
}

- (void)startPollTimer {
    __weak __typeof__(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        while (YES) {
            BOOL now = CatMCPPortOpen();
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) me = weakSelf;
                if (!me) return;
                [me applyState:now];
            });
            [NSThread sleepForTimeInterval:2.0];
        }
    });
}

- (instancetype)init {
    if ((self = [super init])) {
        LifeLog(@"init");
        _catmcpIsRunning = CatMCPPortOpen();
        LifeLog([NSString stringWithFormat:@"init catmcpPortOpen=%d", (int)_catmcpIsRunning]);
        dispatch_async(dispatch_get_main_queue(), ^{ [self updateGlyphOverlay]; });
        [self startPollTimer];
    }
    return self;
}

@end
