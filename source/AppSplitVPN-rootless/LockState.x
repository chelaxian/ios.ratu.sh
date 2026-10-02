#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <notify.h>
#import "Shared.h"

// Read-only bridge: never creates the lock-screen manager or alters locking.
static void ASVPublishUILock(id manager) {
    if(!manager || ![manager respondsToSelector:@selector(isUILocked)])return;
    static int token=-1;
    if(token<0 && notify_register_check(ASV_UI_LOCK_NOTIFY,&token)!=NOTIFY_STATUS_OK)return;
    BOOL locked=((BOOL(*)(id,SEL))objc_msgSend)(manager,@selector(isUILocked));
    uint64_t value=2|(locked?1:0),previous=0;
    notify_get_state(token,&previous);
    if(value==previous)return;
    if(notify_set_state(token,value)==NOTIFY_STATUS_OK)notify_post(ASV_UI_LOCK_NOTIFY);
}
static void ASVInitialUILock(unsigned attempt) {
    Class cls=NSClassFromString(@"SBLockScreenManager");
    SEL selector=@selector(sharedInstanceIfExists);
    id manager=[cls respondsToSelector:selector]?((id(*)(id,SEL))objc_msgSend)(cls,selector):nil;
    if(manager){ASVPublishUILock(manager);return;}
    if(attempt<10)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{ASVInitialUILock(attempt+1);});
}
%hook SBLockScreenManager
- (void)_reallySetUILocked:(BOOL)locked {
    %orig;
    if([NSThread isMainThread])ASVPublishUILock(self);
    else { id manager=self;dispatch_async(dispatch_get_main_queue(),^{ASVPublishUILock(manager);}); }
}
%end
%ctor {
    if(![[NSBundle mainBundle].bundleIdentifier isEqual:@"com.apple.springboard"])return;
    Class cls=NSClassFromString(@"SBLockScreenManager");
    if(![cls instancesRespondToSelector:@selector(_reallySetUILocked:)] || ![cls instancesRespondToSelector:@selector(isUILocked)])return;
    %init;
    dispatch_async(dispatch_get_main_queue(),^{ASVInitialUILock(0);});
}
