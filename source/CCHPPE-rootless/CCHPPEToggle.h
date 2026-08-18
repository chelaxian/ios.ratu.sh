#import <UIKit/UIKit.h>

// Minimal redeclaration of the private ControlCenterUIKit toggle base class, so we
// do not depend on private-framework headers being present in the Theos SDK. The
// real CCUIToggleModule implementation is provided by ControlCenterUIKit at link
// time (see the Makefile's PRIVATE_FRAMEWORKS); we only override the documented
// toggle methods and call [super refreshState], exactly like the AlbumManager CC
// toggle this is modelled on.
@interface CCUIToggleModule : NSObject
- (void)refreshState;
@end

@interface CCHPPEToggle : CCUIToggleModule
@end
