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

@interface ASVCCModule : CCUIToggleModule {
    BOOL _holding;
    __weak UIView *_gestureView;
    UILongPressGestureRecognizer *_hold;
    NSUInteger _attachAttempts;
    int _commandToken, _ackToken;
    uint64_t _requestSequence, _pendingValue;
    NSTimeInterval _pendingAt, _lastSend, _lastRead;
    NSTimer *_pollTimer;
    NSDictionary *_observedPreferences;
}
- (void)asv_ensureLongPress;
- (void)asv_readState;
- (void)asv_onLongPress:(UILongPressGestureRecognizer *)gesture;
@end

static __weak ASVCCModule *currentModule;
static void StateChanged(__unused CFNotificationCenterRef center,__unused void *observer,
                         __unused CFStringRef name,__unused const void *object,__unused CFDictionaryRef info) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [currentModule refreshState];
        if ([currentModule respondsToSelector:@selector(reconfigureView)]) [currentModule reconfigureView];
    });
}
// Same fork as the tweak icon: one stem going up that splits into two arcs,
// each ending in an arrow head, left and right.
static UIImage *ASVGlyph(void) {
    static UIImage *image;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(80,80)];
        image=[[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
            [[UIColor whiteColor] setStroke];
            UIBezierPath *fork=[UIBezierPath bezierPath];
            fork.lineWidth=6.5;fork.lineCapStyle=kCGLineCapRound;fork.lineJoinStyle=kCGLineJoinRound;
            [fork moveToPoint:CGPointMake(40,70)];[fork addLineToPoint:CGPointMake(40,50)];
            [fork addQuadCurveToPoint:CGPointMake(17,17) controlPoint:CGPointMake(40,40)];
            [fork moveToPoint:CGPointMake(40,50)];
            [fork addQuadCurveToPoint:CGPointMake(63,17) controlPoint:CGPointMake(40,40)];
            // Arrow heads aligned with the end direction of each arc.
            [fork moveToPoint:CGPointMake(17,31)];[fork addLineToPoint:CGPointMake(17,17)];[fork addLineToPoint:CGPointMake(31,17)];
            [fork moveToPoint:CGPointMake(49,17)];[fork addLineToPoint:CGPointMake(63,17)];[fork addLineToPoint:CGPointMake(63,31)];
            [fork stroke];
        }] imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
    });
    return image;
}
@implementation ASVCCModule
+ (void)load {
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,StateChanged,
        CFSTR(ASV_STATE_NOTIFY),NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
}
- (instancetype)init {
    if ((self=[super init])) {
        currentModule=self;
        __weak ASVCCModule *weakSelf=self;
        _commandToken=_ackToken=-1;
        notify_register_check(ASV_CMD_SET,&_commandToken);
        uint64_t previous=0;if(_commandToken>=0)notify_get_state(_commandToken,&previous);
        _requestSequence=previous>>2;
        notify_register_dispatch(ASV_CMD_SET_ACK,&_ackToken,dispatch_get_main_queue(),^(__unused int token){[weakSelf asv_readState];});
        _pollTimer=[NSTimer timerWithTimeInterval:.25 repeats:YES block:^(__unused NSTimer *timer){
            ASVCCModule *module=weakSelf;if(!module)return;
            BOOL visible=module->_gestureView.window && !module->_gestureView.window.hidden;
            if(NSProcessInfo.processInfo.systemUptime-module->_lastRead >= ((visible || module->_pendingValue) ? .25 : 5))[module asv_readState];
        }];
        [NSRunLoop.mainRunLoop addTimer:_pollTimer forMode:NSRunLoopCommonModes];
        dispatch_async(dispatch_get_main_queue(),^{[weakSelf asv_ensureLongPress];[weakSelf asv_readState];});
    }
    return self;
}
// Short tap keeps toggling the master switch; a long press cycles the mode.
- (void)asv_ensureLongPress {
    UIViewController *controller=nil;
    @try {id object=[self valueForKey:@"contentViewController"];if([object isKindOfClass:UIViewController.class])controller=object;}@catch(__unused id exception){}
    UIView *view=controller.view;
    if(!view){
        if(_attachAttempts++<20){__weak ASVCCModule *weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf asv_ensureLongPress];});}
        return;
    }
    if(view==_gestureView)return;
    if(_hold)[_gestureView removeGestureRecognizer:_hold];
    _hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(asv_onLongPress:)];
    _hold.minimumPressDuration=.4;_hold.allowableMovement=40;
    _hold.cancelsTouchesInView=YES;_hold.delaysTouchesBegan=NO;
    [view addGestureRecognizer:_hold];_gestureView=view;_attachAttempts=0;
}
- (void)asv_onLongPress:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateBegan){
        _holding=YES;
        notify_post(ASV_CMD_MODE_NEXT);
        [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium] impactOccurred];
    } else if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed){
        // Release the guard after the host has handled this touch-up, so the next deliberate tap works.
        dispatch_async(dispatch_get_main_queue(),^{self->_holding=NO;});
    }
}
- (BOOL)isSelected {
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS];
    // This is the tweak's enable switch, not the VPN's connection indicator.
    // Keep it visibly on while waiting for a VPN so the next tap turns it off.
    return [prefs[@"enabled"] boolValue];
}
- (void)dealloc {
    [_pollTimer invalidate];
    if(_commandToken>=0)notify_cancel(_commandToken);
    if(_ackToken>=0)notify_cancel(_ackToken);
}
- (void)asv_readState {
    NSTimeInterval now=NSProcessInfo.processInfo.systemUptime;_lastRead=now;
    if(_pendingValue){
        uint64_t acknowledged=0,current=0;
        if(_ackToken>=0)notify_get_state(_ackToken,&acknowledged);
        if(_commandToken>=0)notify_get_state(_commandToken,&current);
        if(acknowledged==_pendingValue || current!=_pendingValue)_pendingValue=0;
        else if(now-_pendingAt>=8){_pendingValue=0;[[UINotificationFeedbackGenerator new] notificationOccurred:UINotificationFeedbackTypeError];}
        else if(now-_lastSend>=.5){_lastSend=now;notify_post(ASV_CMD_SET);}
    }
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS];
    NSDictionary *observed=@{@"enabled":@([prefs[@"enabled"] boolValue]),@"mode":prefs[@"mode"]?:@"bypass"};
    if(![observed isEqual:_observedPreferences]){
        _observedPreferences=observed;[self refreshState];
        if([self respondsToSelector:@selector(reconfigureView)])[self reconfigureView];
    }
}
- (void)setSelected:(BOOL)selected {
    if(_holding)return;
    // Physical taps flip the pending intent, not the still-old preferences.
    // The visible state continues to come only from the real master setting.
    if(!_pendingValue && selected==[self isSelected])return;
    BOOL base=_pendingValue?((_pendingValue&3)==1):[self isSelected];
    _requestSequence=(_requestSequence+1)&(UINT64_MAX>>2);
    if(!_requestSequence)_requestSequence=1;
    uint64_t sequence=_requestSequence;
    uint64_t request=(sequence<<2)|(base?2:1);
    if(_commandToken>=0 && notify_set_state(_commandToken,request)==NOTIFY_STATUS_OK){
        _pendingValue=request;_pendingAt=_lastSend=NSProcessInfo.processInfo.systemUptime;
        notify_post(ASV_CMD_SET);
    }else{_pendingValue=0;notify_post(ASV_CMD_TOGGLE);}
}
- (UIImage *)iconGlyph {
    dispatch_async(dispatch_get_main_queue(),^{[self asv_ensureLongPress];});
    return ASVGlyph();
}
- (UIImage *)selectedIconGlyph { return ASVGlyph(); }
// Green for TUNNEL ONLY, red for BYPASS, matching the status bar badge.
- (UIColor *)selectedColor {
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS];
    if([prefs[@"mode"] isEqual:@"multiVPN"])return UIColor.systemBlueColor;
    return [prefs[@"mode"] isEqual:@"tunnelOnly"]?UIColor.systemGreenColor:UIColor.systemRedColor;
}
@end
