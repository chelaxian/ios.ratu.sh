#import <UIKit/UIKit.h>
#import <notify.h>
#import <spawn.h>
#import <sys/wait.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <string.h>
#import "CCUIToggleModule.h"
#import "CCServiceCommandIO.h"
extern char **environ;

@interface SERVICE_CLASS : CCUIToggleModule {
    NSInteger _state;
    int _token;
    NSTimer *_timer;
    UILabel *_label;
    BOOL _busy;
    NSMutableArray<NSString *> *_commands;
    CFTimeInterval _lastPoll;
    NSInteger _lastCommandError, _lastSpawnError, _lastHelperExit;
    NSUInteger _tapCount, _completedActions;
    NSInteger _pendingTarget;
}
@end
@implementation SERVICE_CLASS
- (instancetype)init {
    if ((self = [super init])) {
        _commands = [NSMutableArray array];
        _pendingTarget = -1;
        _token = NOTIFY_TOKEN_INVALID;
        __weak typeof(self) weak = self;
        // A notification is only a wakeup. Its global value can be stale;
        // the helper's own response is the authoritative status snapshot.
        notify_register_dispatch(SERVICE_NOTIFICATION, &_token, dispatch_get_main_queue(), ^(__unused int token) {
            [weak runCommand:@"status"];
        });
        _timer = [NSTimer timerWithTimeInterval:.5 repeats:YES block:^(__unused NSTimer *timer) {
            typeof(self) me = weak;
            if (!me) return;
            UIView *view = me->_label;
            BOOL visible = view.window && !view.window.hidden && view.window.alpha > .01;
            CFTimeInterval now = NSProcessInfo.processInfo.systemUptime;
            if (now - me->_lastPoll >= (visible ? .5 : 10)) [me runCommand:@"status"];
        }];
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
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
    _label.text = SERVICE_TEXT;
    _label.textColor = [self isSelected] ? SERVICE_ACTIVE_TEXT_COLOR : UIColor.whiteColor;
    _label.alpha = 1;
    [view bringSubviewToFront:_label];
    view.accessibilityLabel = SERVICE_NAME;
    view.accessibilityValue = _state == 1 ? @"Включено" : (_state == 2 ? @"Только localhost" : @"Выключено");
}
- (void)startNextCommand {
    if (_busy || !_commands.count) return;
    NSString *command = _commands.firstObject;
    [_commands removeObjectAtIndex:0];
    _busy = YES;
    _lastPoll = NSProcessInfo.processInfo.systemUptime;
    __weak typeof(self) weak = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        const char *path = SERVICE_HELPER;
        char *args[] = {(char *)path, (char *)command.UTF8String, NULL};
        int pipeFD[2] = {-1,-1};
        int rc = pipe(pipeFD);
        pid_t pid = 0;
        if (!rc) {
            posix_spawn_file_actions_t actions;
            posix_spawn_file_actions_init(&actions);
            posix_spawn_file_actions_adddup2(&actions, pipeFD[1], STDOUT_FILENO);
            posix_spawn_file_actions_addclose(&actions, pipeFD[0]);
            posix_spawn_file_actions_addclose(&actions, pipeFD[1]);
            // iOS may transiently return EBADEXEC during concurrent AMFI checks.
            // Retry only a failed spawn: the action has not run yet.
            for (int attempt=0; attempt<4; attempt++) {
                rc = posix_spawn(&pid, path, &actions, NULL, args, environ);
                if (rc != EBADEXEC) break;
                usleep(20000);
            }
            posix_spawn_file_actions_destroy(&actions);
            close(pipeFD[1]);
        }
        char output[32] = {0};
        CCCommandResult result={0};
        if (!rc) result=CCReadCommand(pid,pipeFD[0],[command isEqualToString:@"status"]?1.0:25.0,output,sizeof(output));
        if (pipeFD[0]>=0) close(pipeFD[0]);
        if (!rc && !result.reaped) {
            // Reap eventual exit without blocking a worker or delaying taps.
            __block dispatch_source_t exitSource=dispatch_source_create(DISPATCH_SOURCE_TYPE_PROC,(uintptr_t)pid,DISPATCH_PROC_EXIT,dispatch_get_global_queue(QOS_CLASS_UTILITY,0));
            if(exitSource){dispatch_source_set_event_handler(exitSource,^{int status;waitpid(pid,&status,WNOHANG);dispatch_source_cancel(exitSource);exitSource=nil;});dispatch_resume(exitSource);}
        }
        NSInteger helperExit=result.exitKnown?(WIFEXITED(result.status)?WEXITSTATUS(result.status):128+WTERMSIG(result.status)):-1;
        NSInteger executionError=rc?rc:(result.timedOut?ETIMEDOUT:(result.readError?:((helperExit>0)?helperExit:0)));
        // An action may fail while the service remains ON. Never paint an
        // execution error as OFF; retain the last observation if none arrived.
        NSInteger observed = -1;
        if (!rc && result.complete && !result.readError) {
            if (!strcmp(output,"on\n")) observed = 1;
            else if (!strcmp(output,"off\n")) observed = 0;
            else if (!strcmp(output,"local\n")) observed = 2;
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            typeof(self) me = weak;
            if (!me) return;
            me->_busy = NO;
            me->_lastSpawnError=rc;me->_lastHelperExit=helperExit;
            me->_lastCommandError=executionError?:((observed<0)?EIO:0);
            if(![command isEqualToString:@"status"]){
                me->_completedActions++;
                if(me->_lastCommandError){NSLog(@"%@ helper action failed (%ld)",SERVICE_NAME,(long)me->_lastCommandError);[[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];}
            }
            if (observed >= 0 && me->_state != observed) {
                me->_state = observed;
                [me refreshState];
                if ([me respondsToSelector:@selector(reconfigureView)]) [me reconfigureView];
            }
            [me updateLabel];
            if(!me->_commands.count)me->_pendingTarget=-1;
            [me startNextCommand];
        });
    });
}
- (void)runCommand:(NSString *)command {
    if (![NSThread isMainThread]) { dispatch_async(dispatch_get_main_queue(), ^{ [self runCommand:command]; }); return; }
    if ([command isEqualToString:@"status"]) {
        if (_busy || _commands.count) return;
    } else {
        // Every tap is an action, even while a previous poll/action is running.
        [_commands removeObject:@"status"];
    }
    [_commands addObject:command];
    [self startNextCommand];
}
- (void)setSelected:(BOOL)selected {
    (void)selected;
    _tapCount++;
    // Retain tap parity against the last requested target, even when a start
    // failed or the observed service has not caught up yet. Only the newest
    // queued absolute target matters; do not restart a daemon for every tap.
    BOOL target = _pendingTarget>=0 ? !_pendingTarget : _state!=1;
    _pendingTarget=target;
    [_commands removeAllObjects];
    [self runCommand:target?@"on":@"off"];
}
@end
