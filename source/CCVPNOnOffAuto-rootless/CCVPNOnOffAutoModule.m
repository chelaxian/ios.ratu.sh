// The CC host only transports commands and displays the daemon's atomic snapshot.
#import "CCUIToggleModule.h"
#import <UIKit/UIKit.h>
#import <notify.h>
static const char *StateName="com.ratush.ccvpnonoffauto.state.v2";
static const char *TapName="com.ratush.ccvpnonoffauto.cmd.tap.v2";
static const char *AutoName="com.ratush.ccvpnonoffauto.cmd.auto.v2";
static void Query(void){notify_post("com.ratush.ccvpnonoffauto.cmd.query");}
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

@interface CCVPNOnOffAutoModule : CCUIToggleModule {
    BOOL _connected, _autoMode, _holding;
    int _stateToken, _tapToken, _autoToken;
    uint64_t _snapshot;
    __weak UIView *_gestureView;
    UILongPressGestureRecognizer *_hold;
    NSTimer *_pollTimer;
    NSUInteger _attachAttempts;
}
- (void)cc_readState;
- (void)cc_ensureLongPress;
- (void)cc_onLongPress:(UILongPressGestureRecognizer *)gesture;
@end
@implementation CCVPNOnOffAutoModule
- (instancetype)init {
    self=[super init]; if(self){
        _stateToken=_tapToken=_autoToken=-1;_snapshot=UINT64_MAX;
        __weak typeof(self) weakSelf=self;
        notify_register_check(TapName,&_tapToken);
        notify_register_check(AutoName,&_autoToken);
        notify_register_dispatch(StateName,&_stateToken,dispatch_get_main_queue(),^(__unused int token){[weakSelf cc_readState];});
        dispatch_async(dispatch_get_main_queue(),^{[weakSelf cc_readState];[weakSelf cc_ensureLongPress];Query();});
        _pollTimer=[NSTimer scheduledTimerWithTimeInterval:1 repeats:YES block:^(__unused NSTimer *timer){[weakSelf cc_readState];}];
    }return self;
}
- (void)dealloc {
    [_pollTimer invalidate];
    for(NSNumber *token in @[@(_stateToken),@(_tapToken),@(_autoToken)])if(token.intValue>=0)notify_cancel(token.intValue);
}
- (void)cc_readState {
    uint64_t value=0;
    if(_stateToken<0 || notify_get_state(_stateToken,&value)!=NOTIFY_STATUS_OK || value==_snapshot)return;
    _snapshot=value;_connected=(value&1)!=0;_autoMode=(value&2)!=0;
    [self refreshState];
    if([self respondsToSelector:@selector(reconfigureView)])[self reconfigureView];
}
- (void)cc_send:(BOOL)autoCommand {
    int token=autoCommand?_autoToken:_tapToken;uint64_t count=0;
    if(token<0 || notify_get_state(token,&count)!=NOTIFY_STATUS_OK)return;
    if(notify_set_state(token,count+1)==NOTIFY_STATUS_OK)notify_post(autoCommand?AutoName:TapName);
}
- (UIImage *)iconGlyph {
    dispatch_async(dispatch_get_main_queue(),^{[self cc_ensureLongPress];});
    return _autoMode?AutoImage():VPNImage();
}
- (UIImage *)selectedIconGlyph {return _autoMode?AutoImage():VPNImage();}
- (UIColor *)selectedColor {return _autoMode?AutoBlue():OnGreen();}
- (BOOL)isSelected {return _connected;}
- (void)setSelected:(BOOL)selected {
    if(_holding)return;
    [self cc_send:NO];
    [self cc_ensureLongPress];
}
- (void)cc_ensureLongPress {
    UIViewController *controller=nil;
    @try {id object=[self valueForKey:@"contentViewController"];if([object isKindOfClass:UIViewController.class])controller=object;}@catch(__unused id exception){}
    UIView *view=controller.view;
    if(!view){if(_attachAttempts++<20){__weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf cc_ensureLongPress];});}return;}
    if(view==_gestureView)return;
    if(_hold)[_gestureView removeGestureRecognizer:_hold];
    _hold=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(cc_onLongPress:)];
    _hold.minimumPressDuration=.4;_hold.allowableMovement=40;
    _hold.cancelsTouchesInView=YES;_hold.delaysTouchesBegan=NO;
    [view addGestureRecognizer:_hold];_gestureView=view;_attachAttempts=0;
}
- (void)cc_onLongPress:(UILongPressGestureRecognizer *)gesture {
    if(gesture.state==UIGestureRecognizerStateBegan){_holding=YES;[self cc_send:YES];}
    else if(gesture.state==UIGestureRecognizerStateEnded || gesture.state==UIGestureRecognizerStateCancelled || gesture.state==UIGestureRecognizerStateFailed){
        // Cancellation prevents the host's touch-up action; only suppress within
        // this gesture's event, never a subsequent deliberate tap.
        dispatch_async(dispatch_get_main_queue(),^{self->_holding=NO;});
    }
}
@end
