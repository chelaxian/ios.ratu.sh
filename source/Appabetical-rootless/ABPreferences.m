#import "AppabeticalPrefs/ABPRootListController.h"
#import "ABShared.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
@interface PSListController (ABMapping)
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)path;
@end
static NSString *ABLanguage(void){id value=ABReadPreference(@"appLanguage");if([value isEqual:@"en"]||[value isEqual:@"ru"])return value;return [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"]?@"ru":@"en";}
static NSString *ABText(NSString *en,NSString *ru){return [ABLanguage() isEqual:@"ru"]?ru:en;}
static NSString *ABL(NSString *key){NSBundle *bundle=[NSBundle bundleForClass:ABPRootListController.class];NSString *path=[bundle pathForResource:@"Localizable" ofType:@"strings" inDirectory:[ABLanguage() stringByAppendingString:@".lproj"]];NSDictionary *table=path?[NSDictionary dictionaryWithContentsOfFile:path]:nil;return [table[key] length]?table[key]:key;}
static NSString *ABResultText(NSDictionary *response){NSString *message=response[@"message"];
    NSArray *skipped=[response[@"skipped"] isKindOfClass:NSArray.class]?response[@"skipped"]:@[];NSString *list=[[skipped subarrayWithRange:NSMakeRange(0,MIN(skipped.count,(NSUInteger)5))] componentsJoinedByString:@", "];
    if([message isEqual:@"sortedPartial"])return [NSString stringWithFormat:ABText(@"Icons sorted. Skipped (see debug log): %@",@"Иконки отсортированы. Пропущено (подробности в debug-логе): %@"),list];
    if([message isEqual:@"partialFailed"])return [NSString stringWithFormat:ABText(@"Nothing was moved. These containers could not be sorted: %@",@"Ничего не перемещено. Не удалось отсортировать: %@"),list];
    NSDictionary *known=@{
    @"sorted":ABText(@"Icons sorted.",@"Иконки отсортированы."),@"alreadySorted":ABText(@"The layout is already sorted with these settings.",@"Раскладка уже отсортирована с текущими настройками."),
    @"disabled":ABL(@"alert_disabled"),@"busy":ABText(@"SpringBoard is starting or processing another action. Try again shortly.",@"SpringBoard запускается или выполняет другую команду. Повторите чуть позже."),
    @"saved":ABText(@"Layout saved.",@"Раскладка сохранена."),@"restored":ABText(@"Layout restored and verified.",@"Раскладка восстановлена и проверена."),@"deleted":ABText(@"Preset deleted.",@"Пресет удалён."),
    @"inventoryMismatch":ABText(@"Apps, folders or widgets changed after saving this preset. Restore cancelled to preserve your icons.",@"После сохранения изменился набор приложений, папок или виджетов. Восстановление отменено для сохранности текущих иконок."),@"exists":ABText(@"A preset with this name already exists.",@"Пресет с таким именем уже существует.")};return known[message] ?: message ?: ABText(@"Unknown error",@"Неизвестная ошибка");}
@interface ABPCommandController ()
@property(nonatomic,copy)NSString *pendingID;
@property(nonatomic,strong)UIAlertController *progress;
@property(nonatomic,copy)void(^completion)(NSDictionary *);
@property(nonatomic,strong)NSDate *started;
@property(nonatomic)int responseToken;
@end
@implementation ABPCommandController
- (void)viewDidLoad{[super viewDidLoad];self.responseToken=-1;__weak typeof(self) weakSelf=self;notify_register_dispatch(ABResponseNotification.UTF8String,&_responseToken,dispatch_get_main_queue(),^(__unused int token){[weakSelf checkResponse];});}
- (void)dealloc{if(_responseToken>=0)notify_cancel(_responseToken);}
- (void)showMessage:(NSString *)message{UIAlertController *alert=[UIAlertController alertControllerWithTitle:@"Appabetical" message:message preferredStyle:UIAlertControllerStyleAlert];[alert addAction:[UIAlertAction actionWithTitle:ABL(@"ok") style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:alert animated:YES completion:nil];}
- (void)finish:(NSDictionary *)response{void(^callback)(NSDictionary *)=self.completion;self.completion=nil;self.pendingID=nil;UIAlertController *progress=self.progress;self.progress=nil;void(^done)(void)=^{if(callback)callback(response);};if(progress.presentingViewController)[progress dismissViewControllerAnimated:YES completion:done];else done();}
- (void)checkResponse{if(!self.pendingID)return;id response=ABReadPreference(@"response");if([response isKindOfClass:NSDictionary.class]&&[response[@"id"] isEqual:self.pendingID])[self finish:response];}
- (void)poll:(NSString *)identifier{
    if(![self.pendingID isEqual:identifier])return;[self checkResponse];if(!self.pendingID)return;
    if(-self.started.timeIntervalSinceNow>90){[self finish:@{@"id":identifier,@"ok":@NO,@"message":ABText(@"SpringBoard did not confirm this action. Check Appabetical's permission in Choicy.",@"SpringBoard не подтвердил команду. Проверьте разрешение Appabetical в Choicy.")}];return;}
    __weak typeof(self) weakSelf=self;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf poll:identifier];});
}
- (void)sendCommand:(NSString *)command name:(NSString *)name overwrite:(BOOL)overwrite progress:(BOOL)visible completion:(void(^)(NSDictionary *))completion{
    if(self.pendingID)return;NSString *identifier=NSUUID.UUID.UUIDString;NSMutableDictionary *request=[@{@"id":identifier,@"command":command,@"date":NSDate.date,@"overwrite":@(overwrite)} mutableCopy];if(name)request[@"name"]=name;
    self.pendingID=identifier;self.completion=completion;self.started=NSDate.date;
    if(!ABWritePreference(@"request",request)){[self finish:@{@"ok":@NO,@"message":ABText(@"Could not send the command.",@"Не удалось отправить команду.")}];return;}
    void(^post)(void)=^{notify_post(ABCommandNotification.UTF8String);[self poll:identifier];};
    if(visible){self.progress=[UIAlertController alertControllerWithTitle:@"Appabetical" message:ABText(@"Applying…",@"Выполнение…") preferredStyle:UIAlertControllerStyleAlert];[self presentViewController:self.progress animated:YES completion:post];}else post();
}
- (PSSpecifier *)toggle:(NSString *)key title:(NSString *)title defaultValue:(BOOL)value{PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:title target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];[s setProperty:key forKey:@"key"];[s setProperty:ABDomain forKey:@"defaults"];[s setProperty:@(value) forKey:@"default"];return s;}
- (id)readPreferenceValue:(PSSpecifier *)specifier{return ABReadPreference([specifier propertyForKey:@"key"]) ?: [specifier propertyForKey:@"default"];}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier{if(!ABWritePreference([specifier propertyForKey:@"key"],value)){[self showMessage:ABText(@"Could not save the setting.",@"Не удалось сохранить настройку.")];[self reloadSpecifiers];return;}notify_post(ABReloadNotification.UTF8String);}
@end
@implementation ABPRootListController
- (NSString *)title{return @"Appabetical";}
- (NSArray *)specifiers{
    if(_specifiers)return _specifiers;NSMutableArray *items=NSMutableArray.array;
    NSArray *toggles=@[@[@"enabled",@"toggle_enabled",@YES],@[@"placeOffloadedAtEnd",@"toggle_offloaded",@YES],@[@"placeBookmarksAtEnd",@"toggle_bookmarks",@NO],@[@"ignoreEmoji",@"toggle_emoji",@YES],@[@"sortFolders",@"toggle_sortfolders",@YES],@[@"sortInsideFolders",@"toggle_sortinside",@YES],@[@"includeDock",@"toggle_dock",@NO],@[@"compactLayout",@"toggle_compact",@NO],@[@"autoSortOnRespring",@"toggle_autosort",@YES]];
    for(NSArray *row in toggles)[items addObject:[self toggle:row[0] title:ABL(row[1]) defaultValue:[row[2] boolValue]]];
    PSSpecifier *language=[PSSpecifier preferenceSpecifierNamed:ABL(@"label_language") target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];[language setProperty:@"language" forKey:@"action"];[language setButtonAction:@selector(showLanguageMenu)];[items addObject:language];
    PSSpecifier *sort=[PSSpecifier preferenceSpecifierNamed:ABL(@"button_sortnow") target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];[sort setProperty:@"sort" forKey:@"action"];[sort setButtonAction:@selector(sortNow)];[items addObject:sort];
    [items addObject:[PSSpecifier preferenceSpecifierNamed:ABL(@"button_presets") target:self set:NULL get:NULL detail:ABPPresetsController.class cell:PSLinkCell edit:nil]];_specifiers=items;return _specifiers;
}
- (void)showLanguageMenu{
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:ABL(@"label_language") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for(NSString *code in @[@"en",@"ru"])[alert addAction:[UIAlertAction actionWithTitle:[code isEqual:@"ru"]?@"Русский":@"English" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ABWritePreference(@"appLanguage",code);self->_specifiers=nil;[self reloadSpecifiers];notify_post(ABReloadNotification.UTF8String);}]];
    [alert addAction:[UIAlertAction actionWithTitle:ABL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];alert.popoverPresentationController.sourceView=self.view;alert.popoverPresentationController.sourceRect=CGRectMake(CGRectGetMidX(self.view.bounds),CGRectGetMidY(self.view.bounds),1,1);[self presentViewController:alert animated:YES completion:nil];
}
- (void)sortNow{if(!ABBool(ABSettings(),@"enabled",YES)){[self showMessage:ABL(@"alert_disabled")];return;}__weak typeof(self) weakSelf=self;[self sendCommand:@"sort" name:nil overwrite:NO progress:YES completion:^(NSDictionary *response){[weakSelf showMessage:ABResultText(response)];}];}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{NSString *action=[[self specifierAtIndexPath:path] propertyForKey:@"action"];if([action isEqual:@"sort"]){[table deselectRowAtIndexPath:path animated:YES];[self sortNow];}else if([action isEqual:@"language"]){[table deselectRowAtIndexPath:path animated:YES];[self showLanguageMenu];}else [super tableView:table didSelectRowAtIndexPath:path];}
@end
@implementation ABPPresetsController
- (NSString *)title{return ABL(@"presets_title");}
- (void)refresh{_specifiers=nil;[self reloadSpecifiers];}
- (NSArray *)names{id names=ABReadPreference(@"presetCatalog");return [names isKindOfClass:NSArray.class]?names:@[];}
- (void)viewDidAppear:(BOOL)animated{[super viewDidAppear:animated];[self refresh];__weak typeof(self) weakSelf=self;[self sendCommand:@"catalog" name:nil overwrite:NO progress:NO completion:^(NSDictionary *response){if([response[@"ok"] boolValue])[weakSelf refresh];else [weakSelf showMessage:ABResultText(response)];}];}
- (NSArray *)specifiers{
    if(_specifiers)return _specifiers;NSMutableArray *items=NSMutableArray.array;PSSpecifier *group=[PSSpecifier groupSpecifierWithName:nil];[group setProperty:ABL(@"presets_preservecc_footer") forKey:@"footerText"];[items addObject:group];[items addObject:[self toggle:@"preserveCC" title:ABL(@"toggle_preservecc") defaultValue:YES]];
    PSSpecifier *save=[PSSpecifier preferenceSpecifierNamed:ABL(@"presets_save") target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];[save setProperty:@"save" forKey:@"action"];[save setButtonAction:@selector(saveNewPreset)];[items addObject:save];
    PSSpecifier *presets=[PSSpecifier groupSpecifierWithName:nil];[presets setProperty:ABL(self.names.count?@"presets_saved_footer":@"presets_empty_footer") forKey:@"footerText"];[items addObject:presets];
    for(NSString *name in self.names){PSSpecifier *row=[PSSpecifier preferenceSpecifierNamed:name target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];[row setProperty:name forKey:@"presetName"];[row setButtonAction:@selector(applyPreset:)];[items addObject:row];}_specifiers=items;return _specifiers;
}
- (void)saveName:(NSString *)name overwrite:(BOOL)overwrite{__weak typeof(self) weakSelf=self;[self sendCommand:@"save" name:name overwrite:overwrite progress:YES completion:^(NSDictionary *response){[weakSelf refresh];[weakSelf showMessage:ABResultText(response)];}];}
- (void)saveNewPreset{
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:ABL(@"presets_save_title") message:ABL(@"presets_save_msg") preferredStyle:UIAlertControllerStyleAlert];[alert addTextFieldWithConfigurationHandler:^(UITextField *field){field.placeholder=ABL(@"presets_save_placeholder");}];[alert addAction:[UIAlertAction actionWithTitle:ABL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];__weak typeof(self) weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:ABL(@"save") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){NSString *name=[alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        dispatch_async(dispatch_get_main_queue(),^{if(!name.length||name.length>128){[weakSelf showMessage:ABText(@"Enter a name of 1–128 characters.",@"Введите имя длиной от 1 до 128 символов.")];return;}
            if([weakSelf.names containsObject:name]){UIAlertController *replace=[UIAlertController alertControllerWithTitle:name message:ABText(@"Replace this preset?",@"Заменить этот пресет?") preferredStyle:UIAlertControllerStyleAlert];[replace addAction:[UIAlertAction actionWithTitle:ABL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];[replace addAction:[UIAlertAction actionWithTitle:ABL(@"save") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){dispatch_async(dispatch_get_main_queue(),^{[weakSelf saveName:name overwrite:YES];});}]];[weakSelf presentViewController:replace animated:YES completion:nil];}else [weakSelf saveName:name overwrite:NO];});
    }]];[self presentViewController:alert animated:YES completion:nil];
}
- (void)applyPreset:(PSSpecifier *)specifier{NSString *name=[specifier propertyForKey:@"presetName"];if(!name)return;__weak typeof(self) weakSelf=self;[self sendCommand:@"restore" name:name overwrite:NO progress:YES completion:^(NSDictionary *response){[weakSelf showMessage:ABResultText(response)];}];}
- (void)deleteName:(NSString *)name{__weak typeof(self) weakSelf=self;[self sendCommand:@"delete" name:name overwrite:NO progress:YES completion:^(NSDictionary *response){[weakSelf refresh];if(![response[@"ok"] boolValue])[weakSelf showMessage:ABResultText(response)];}];}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)path{PSSpecifier *specifier=[self specifierAtIndexPath:path];if([specifier propertyForKey:@"presetName"]){[table deselectRowAtIndexPath:path animated:YES];[self applyPreset:specifier];}else if([[specifier propertyForKey:@"action"] isEqual:@"save"]){[table deselectRowAtIndexPath:path animated:YES];[self saveNewPreset];}else [super tableView:table didSelectRowAtIndexPath:path];}
- (BOOL)tableView:(UITableView *)table canEditRowAtIndexPath:(NSIndexPath *)path{return [[self specifierAtIndexPath:path] propertyForKey:@"presetName"]!=nil;}
- (UISwipeActionsConfiguration *)tableView:(UITableView *)table trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)path{NSString *name=[[self specifierAtIndexPath:path] propertyForKey:@"presetName"];if(!name)return nil;__weak typeof(self) weakSelf=self;UIContextualAction *action=[UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:nil handler:^(__unused UIContextualAction *a,__unused UIView *view,void(^done)(BOOL)){done(NO);[weakSelf deleteName:name];}];action.image=[UIImage systemImageNamed:@"trash"];return [UISwipeActionsConfiguration configurationWithActions:@[action]];}
- (void)tableView:(UITableView *)table commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)path{if(style==UITableViewCellEditingStyleDelete)[self deleteName:[[self specifierAtIndexPath:path] propertyForKey:@"presetName"]];}
@end
