#define OFFLOADER_UI_TEST 1
#import "../OFSpringBoard.m"
static unsigned assertions;
#define CHECK(expression) do { ++assertions; if (!(expression)) { NSLog(@"FAIL line %d: %s",__LINE__,#expression); exit(1); } } while(0)
@interface OFTestShortcut : NSObject
@property(nonatomic,copy) NSString *type;
@property(nonatomic,copy) NSString *localizedTitle;
@property(nonatomic) BOOL sbh_isShortcutDeleteOrRemove;
@end
@implementation OFTestShortcut
@end
@interface SBHApplicationIcon : NSObject
@property(nonatomic,copy) NSString *applicationBundleID;
@end
@implementation SBHApplicationIcon
@end
@interface OFTestLeafIcon : NSObject
@property(nonatomic,copy) NSString *applicationBundleID;
@end
@implementation OFTestLeafIcon
@end
@interface OFTestView : NSObject
@property(nonatomic,strong) id icon;
@end
@implementation OFTestView
@end
@interface OFTestLauncher : NSObject
@property(nonatomic) BOOL succeed;
@property(nonatomic) BOOL called;
@property(nonatomic) BOOL suspended;
@property(nonatomic,copy) NSString *identifier;
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended;
@end
@implementation OFTestLauncher
- (BOOL)launchApplicationWithIdentifier:(NSString *)identifier suspended:(BOOL)suspended { self.called=YES; self.identifier=identifier; self.suspended=suspended; return self.succeed; }
@end
static UIAction *Action(NSString *identifier,NSString *title) {
    return [UIAction actionWithTitle:title image:nil identifier:identifier handler:^(__unused UIAction *action){}];
}
int main(void) { @autoreleasepool {
    OFTestLauncher *launcher=[OFTestLauncher new]; launcher.succeed=YES;
    CHECK(OFLaunchSettings(launcher)); CHECK(launcher.called); CHECK(!launcher.suspended); CHECK([launcher.identifier isEqual:@"com.apple.Preferences"]);
    launcher.succeed=NO; CHECK(!OFLaunchSettings(launcher)); CHECK(!OFLaunchSettings([NSObject new]));
    UIAction *offload = Action(@"com.level3tjg.offloader/offload",@"Offload App");
    UIAction *remove = Action(@"delete-app",@"Удалить приложение");
    UIAction *edit = Action(@"rearrange-icons",@"Edit Home Screen");
    UIAction *custom = Action(@"com.example.delete",@"Delete App");
    UIMenu *native = [UIMenu menuWithTitle:@"System" image:nil identifier:@"native" options:UIMenuOptionsDisplayInline children:@[remove,edit]];
    UIMenu *nested = [UIMenu menuWithTitle:@"Nested" children:@[native]];
    NSArray *original = @[custom,nested,offload];
    for(unsigned mask=0;mask<8;++mask) {
        NSDictionary *settings = @{@"3doffload":@((mask&1)!=0),@"3ddelete":@((mask&2)!=0),@"3dedit":@((mask&4)!=0)};
        NSArray *filtered = OFFilterMenu(original,settings);
        CHECK(filtered.firstObject==custom);
        CHECK(filtered.count == 1 + ((mask&6) ? 1 : 0) + ((mask&1) ? 1 : 0));
        if(mask&6) {
            UIMenu *outer=filtered[1]; UIMenu *inner=(UIMenu *)outer.children.firstObject;
            CHECK([outer.title isEqual:@"Nested"]); CHECK([inner.identifier isEqual:@"native"]); CHECK(inner.options==UIMenuOptionsDisplayInline);
            CHECK(inner.children.count == ((mask&2) ? 1 : 0) + ((mask&4) ? 1 : 0));
            if(mask&2)CHECK(inner.children.firstObject==remove); if(mask&4)CHECK(inner.children.lastObject==edit);
        }
        CHECK(native.children.count==2); CHECK(nested.children.count==1);
        CHECK([OFFilterMenu(filtered,settings) isEqual:filtered]);
        NSMutableArray *shortcuts=[NSMutableArray array];
        for(NSString *type in @[@"delete-app",@"rearrange-icons",@"com.level3tjg.offloader/offload",@"com.example.delete"]) {
            OFTestShortcut *shortcut=[OFTestShortcut new]; shortcut.type=type; shortcut.localizedTitle=@"Delete App"; [shortcuts addObject:shortcut];
        }
        NSArray *result=OFFilterShortcuts(shortcuts,settings);
        CHECK(result.count==1+((mask&1)?1:0)+((mask&2)?1:0)+((mask&4)?1:0)); CHECK(result.lastObject==shortcuts.lastObject); CHECK(shortcuts.count==4);
    }
    CHECK(OFFilterShortcuts(nil,@{})==nil); CHECK(OFFilterMenu(@[],@{}).count==0);
    CHECK(OFKind(NSUUID.UUID.UUIDString,@"Удалить приложение",NO)==OFActionDelete);
    CHECK(OFKind(@"com.apple.springboardhome.edit",@"任意标题",NO)==OFActionEdit);
    OFTestView *view=[OFTestView new]; view.icon=[NSObject new]; CHECK(OFViewBundle(view)==nil);
    SBHApplicationIcon *icon=[SBHApplicationIcon new]; icon.applicationBundleID=@"com.example.app"; view.icon=icon; CHECK([OFViewBundle(view) isEqual:icon.applicationBundleID]);
    icon.applicationBundleID=@"../invalid"; CHECK(OFViewBundle(view)==nil);
    UIMenu *decorated=OFDecorateMenu([UIMenu menuWithTitle:@"Original" children:@[custom]],@"com.example.app",@{},YES,NO,NO);
    CHECK([decorated.title isEqual:@"Original"]); CHECK(decorated.children.firstObject==custom); CHECK(decorated.children.count==2);
    CHECK([((UIAction *)decorated.children.lastObject).identifier isEqual:@"com.level3tjg.offloader/offload"]);
    CHECK(OFDecorateMenu(decorated,@"com.example.app",@{},YES,NO,NO).children.count==2);
    CHECK(OFDecorateMenu(decorated,@"com.example.app",@{},NO,NO,NO).children.count==1);
    CHECK(OFDecorateMenu(decorated,@"com.example.app",@{},YES,YES,NO).children.count==1);
    CHECK(OFDecorateMenu(decorated,@"com.example.app",@{@"3doffload":@NO},YES,NO,NO).children.count==1);
    UIMenu *stalled=OFDecorateMenu([UIMenu menuWithTitle:@"Original" children:@[custom]],@"com.example.app",@{},NO,NO,YES);
    CHECK(stalled.children.count==2); CHECK([((UIAction *)stalled.children.lastObject).identifier isEqual:@"com.level3tjg.offloader/restart-appstored"]);
    CHECK(OFDecorateMenu(stalled,@"com.example.app",@{},NO,NO,YES).children.count==2);
    CHECK(OFDecorateMenu(stalled,@"com.example.app",@{},NO,NO,NO).children.count==1);
    CHECK(OFDecorateMenu(stalled,@"com.example.app",@{@"3drestartstore":@NO},NO,NO,YES).children.count==1);
    CHECK(OFDecorateMenu(stalled,@"com.example.app",@{},YES,NO,YES).children.count==3);
    CHECK([OFStoreTarget(501) isEqual:@"user/501/com.apple.appstored"]);
    CHECK(OFStoreRequestValid(@{@"id":@"A-1",@"date":NSDate.date},NSDate.date));
    CHECK(!OFStoreRequestValid(@{@"id":@"A-1",@"date":[NSDate dateWithTimeIntervalSinceNow:-60]},NSDate.date));
    CHECK(!OFStoreRequestValid(@{@"id":@"../x",@"date":NSDate.date},NSDate.date)); CHECK(!OFStoreRequestValid(nil,NSDate.date));
    OFTestView *loose=[OFTestView new]; OFTestLeafIcon *other=[OFTestLeafIcon new]; other.applicationBundleID=@"com.example.downloading"; loose.icon=other;
    CHECK(OFViewBundle(loose)==nil); CHECK([OFMenuBundle(loose) isEqual:@"com.example.downloading"]);
    loose.icon=[NSObject new]; CHECK(OFMenuBundle(loose)==nil);
    __block unsigned providerCalls=0;
    UIContextMenuConfiguration *configuration=[UIContextMenuConfiguration configurationWithIdentifier:@"test" previewProvider:nil actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggested){ ++providerCalls; CHECK(suggested.firstObject==custom); return [UIMenu menuWithTitle:@"Native" children:suggested]; }];
    CHECK(OFWrapConfiguration(configuration,@"com.example.app")==configuration);
    OFMenuProvider provider=(OFMenuProvider)OFObject(configuration,@selector(actionProvider)); CHECK(provider!=nil);
    UIMenu *provided=provider(@[custom]); CHECK(providerCalls==1); CHECK(provided.children.firstObject==custom); CHECK([provided.title isEqual:@"Native"]);
    OFWrapConfiguration(configuration,@"com.example.app"); CHECK(OFObject(configuration,@selector(actionProvider))==provider);
    printf("PASS: %u UIKit assertions; nested menus, all toggle combinations, original actions, custom action conservation and icon discrimination.\n",assertions);
    return 0;
} }
