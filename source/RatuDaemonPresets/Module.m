#import "Shared.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
@interface CCUIToggleModule : NSObject
- (UIViewController*)contentViewControllerForContext:(id)context;
- (void)refreshState;
- (void)reconfigureView;
@end
@interface RPModule : CCUIToggleModule
@property int token;
@property BOOL attached;
@property double suppressUntil;
@property int retries;
@property (nonatomic,weak) UIViewController *controller;
@end
@implementation RPModule
- (instancetype)init {if((self=[super init])){__weak RPModule *w=self;notify_register_dispatch("com.ratush.daemonpresets.changed",&_token,dispatch_get_main_queue(),^(int t){if([w respondsToSelector:@selector(refreshState)])[w refreshState];if([w respondsToSelector:@selector(reconfigureView)])[w reconfigureView];});Command(@"query");}return self;}
- (UIViewController*)contentViewControllerForContext:(id)context {UIViewController *vc=[super contentViewControllerForContext:context];if([vc isKindOfClass:UIViewController.class]){if(vc!=self.controller){self.attached=NO;self.retries=0;}self.controller=vc;__weak RPModule *w=self;dispatch_async(dispatch_get_main_queue(),^{[w attach];});}return vc;}
- (void)dealloc {notify_cancel(_token);}
- (UIImage*)iconGlyph {return [UIImage systemImageNamed:@"gearshape.2"] ;}
- (UIImage*)selectedIconGlyph {return [UIImage systemImageNamed:@"gearshape.2.fill"];}
- (UIColor*)selectedColor {return [UIColor systemBlueColor];}
- (BOOL)isSelected {NSDictionary *s=Status();return [s[@"enabled"] boolValue] && [s[@"verified"] boolValue];}
- (void)setSelected:(BOOL)value {if(CACurrentMediaTime()<self.suppressUntil)return;Command(@"toggle");}
- (void)attach {if(self.attached)return;UIViewController *vc=self.controller;if(!vc)return;UIView *v=vc.view;if(!v){if(self.retries++<30)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,300*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[self attach];});return;}UILongPressGestureRecognizer *g=[[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(hold:)];g.minimumPressDuration=.45;g.cancelsTouchesInView=YES;[v addGestureRecognizer:g];self.attached=YES;}
- (void)hold:(UILongPressGestureRecognizer*)g {
 if(g.state==UIGestureRecognizerStateEnded || g.state==UIGestureRecognizerStateCancelled){self.suppressUntil=CACurrentMediaTime()+.8;return;}
 if(g.state!=UIGestureRecognizerStateBegan)return;self.suppressUntil=CACurrentMediaTime()+60;
 NSDictionary *s=Status();UIAlertController *a=[UIAlertController alertControllerWithTitle:@"Демоны iOS" message:[s[@"enabled"] boolValue]?@"Выберите активный набор":@"Твик выключен. Выбор сохранится до включения." preferredStyle:UIAlertControllerStyleActionSheet];
 NSUInteger count=0;for(NSDictionary *p in Presets()){if(![s[@"ccPresets"] containsObject:p[@"id"]])continue;count++;NSString *title=[NSString stringWithFormat:@"%@%@",[p[@"id"] isEqual:s[@"preset"]]?@"✓ ":@"",p[@"name"]];[a addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action){self.suppressUntil=CACurrentMediaTime()+.8;Command([@"preset." stringByAppendingString:p[@"id"]]);}]];}
 if(!count)a.message=@"Выберите наборы для этого списка в настройках твика.";
 [a addAction:[UIAlertAction actionWithTitle:@"Отмена" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action){self.suppressUntil=CACurrentMediaTime()+.8;}]];
 UIViewController *vc=self.controller.view.window.rootViewController;while(vc.presentedViewController)vc=vc.presentedViewController;
 if(a.popoverPresentationController){a.popoverPresentationController.sourceView=self.controller.view;a.popoverPresentationController.sourceRect=self.controller.view.bounds;}
 if(vc)[vc presentViewController:a animated:YES completion:nil];else self.suppressUntil=0;
}
@end

