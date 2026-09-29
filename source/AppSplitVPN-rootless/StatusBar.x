#import <UIKit/UIKit.h>
#import <notify.h>
#import "Shared.h"

// iOS 17 draws the status-bar VPN badge as a string view with the text "VPN":
// STUIStatusBarStringView in SpringBoard, _UIStatusBarStringView in apps.
// While split rules are applied the badge reads "VPN½", so partial tunnelling is visible at a glance.

static BOOL splitActive;
static NSHashTable<UILabel *> *badges;
static NSString *const ASVBadgeText = @"VPN½";

static BOOL ASVReadState(void) {
    static int token = -1;
    if (token < 0 && notify_register_check(ASV_STATE_NOTIFY, &token) != NOTIFY_STATUS_OK) return NO;
    uint64_t value = 0;
    notify_get_state(token, &value);
    return value == 1;
}

static NSString *ASVBadge(UILabel *label, NSString *text) {
    if (![text isEqualToString:@"VPN"] && ![text isEqualToString:ASVBadgeText]) return text;
    [badges addObject:label];
    return splitActive ? ASVBadgeText : @"VPN";
}

%hook STUIStatusBarStringView
- (void)setText:(NSString *)text { %orig(ASVBadge((UILabel *)self, text)); }
%end

%hook _UIStatusBarStringView
- (void)setText:(NSString *)text { %orig(ASVBadge((UILabel *)self, text)); }
%end

%ctor {
    badges = [NSHashTable weakObjectsHashTable];
    splitActive = ASVReadState();
    int token;
    notify_register_dispatch(ASV_STATE_NOTIFY, &token, dispatch_get_main_queue(), ^(__unused int t) {
        BOOL now = ASVReadState();
        if (now == splitActive) return;
        splitActive = now;
        for (UILabel *label in badges.allObjects) {
            label.text = label.text;
            [label invalidateIntrinsicContentSize];
            [label.superview setNeedsLayout];
        }
    });
    %init;
}
