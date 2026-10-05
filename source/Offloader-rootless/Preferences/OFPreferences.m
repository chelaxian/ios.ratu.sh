#import "../OFShared.h"
#import "../OFApplications.h"
#import "../OFAppStore.h"
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSSwitchTableCell.h>
#import <UIKit/UIKit.h>

@interface OFApplicationSwitchCell : PSSwitchTableCell
@end
@implementation OFApplicationSwitchCell
- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)identifier specifier:(PSSpecifier *)specifier {
    self = [super initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:identifier specifier:specifier];
    if (self) { self.detailTextLabel.text = [specifier propertyForKey:@"subtitle"]; self.detailTextLabel.font = [UIFont systemFontOfSize:11]; }
    return self;
}
- (void)refreshCellContentsWithSpecifier:(PSSpecifier *)specifier {
    [super refreshCellContentsWithSpecifier:specifier]; self.detailTextLabel.text = [specifier propertyForKey:@"subtitle"];
}
@end

static void OFPreferencesAlert(UIViewController *controller, NSString *message) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Offloader" message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:OFText(@"OK",@"ОК") style:UIAlertActionStyleDefault handler:nil]];
    [controller presentViewController:alert animated:YES completion:nil];
}
@interface OffAntiOffloadListController : PSListController <UISearchResultsUpdating>
@property(nonatomic,copy) NSArray<NSDictionary *> *applications;
@property(nonatomic,strong) UISearchController *search;
@property(nonatomic,copy) NSString *query;
@property(nonatomic) BOOL loading;
@end
@interface OffRootListController : PSListController
@property(nonatomic,strong) UIAlertController *storeProgress;
@property(nonatomic,copy) NSString *storeRequest;
@end
@implementation OffRootListController
- (NSString *)title { return @"Offloader"; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:OFText(@"Home Screen Menu",@"Меню экрана Домой")];
    [group setProperty:OFText(@"Changes apply when you next open an app's menu. Delete and Edit use the standard iOS actions.",@"Изменения действуют при следующем открытии меню приложения. Удаление и редактирование используют штатные действия iOS.") forKey:@"footerText"];
    [items addObject:group];
    for (NSArray *row in @[@[@"3doffload",OFText(@"Offload App",@"Выгрузить приложение")],@[@"3ddelete",OFText(@"Delete / Remove App",@"Удалить приложение")],@[@"3dedit",OFText(@"Edit Home Screen",@"Изменить экран Домой")],@[@"3drestartstore",OFText(@"Restart Stalled Download",@"Перезапуск зависшей загрузки")]]) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:row[1] target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [item setProperty:row[0] forKey:@"key"]; [item setProperty:@YES forKey:@"default"]; [item setProperty:OFDomain forKey:@"defaults"]; [items addObject:item];
    }
    PSSpecifier *store = [PSSpecifier groupSpecifierWithName:@"App Store"];
    [store setProperty:OFText(@"Use this when an app download or reinstall from the cloud icon stops progressing. It restarts the system App Store service (appstored); downloads continue on their own. The same action is in the menu of a downloading or offloaded app icon.",@"Используйте, если загрузка или повторная установка приложения через значок облака перестала двигаться. Кнопка перезапускает системную службу App Store (appstored), загрузки продолжаются сами. То же действие есть в меню значка загружаемого или выгруженного приложения.") forKey:@"footerText"];
    [items addObject:store];
    PSSpecifier *restart = [PSSpecifier preferenceSpecifierNamed:OFText(@"Restart App Store Service (appstored)",@"Перезапустить службу App Store (appstored)") target:self set:NULL get:NULL detail:nil cell:PSButtonCell edit:nil];
    restart.buttonAction = @selector(restartAppStore:);
    [items addObject:restart];
    PSSpecifier *protection = [PSSpecifier groupSpecifierWithName:OFText(@"Protection",@"Защита")];
    [protection setProperty:OFText(@"Selected apps cannot be offloaded manually or automatically. This does not block deleting an app. Documents and data remain when an app is offloaded.",@"Выбранные приложения защищены от ручной и автоматической выгрузки. Защита не запрещает удаление приложения. При выгрузке документы и данные сохраняются.") forKey:@"footerText"];
    [items addObject:protection];
    [items addObject:[PSSpecifier preferenceSpecifierNamed:OFText(@"Prevent Offloading of Apps",@"Защитить приложения от выгрузки") target:self set:NULL get:NULL detail:OffAntiOffloadListController.class cell:PSLinkCell edit:nil]];
    _specifiers = items; return _specifiers;
}
- (id)readPreferenceValue:(PSSpecifier *)specifier { return @(OFValueBool(OFPreferences(OFDomain)[[specifier propertyForKey:@"key"]],YES)); }
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    if (!OFWrite(OFDomain,[specifier propertyForKey:@"key"],@(OFValueBool(value,YES)))) {
        OFPreferencesAlert(self,OFText(@"Could not save this setting.",@"Не удалось сохранить настройку.")); [self reloadSpecifiers]; return;
    }
    notify_post(OFChanged);
}
- (void)restartAppStore:(PSSpecifier *)specifier {
    if (self.storeRequest) return;
    NSString *identifier = NSUUID.UUID.UUIDString;
    if (!OFWrite(OFDomain,OFStoreRequestKey,@{@"id":identifier,@"date":NSDate.date})) {
        OFPreferencesAlert(self,OFText(@"Could not send the restart request.",@"Не удалось отправить команду перезапуска.")); return;
    }
    self.storeRequest = identifier;
    self.storeProgress = [UIAlertController alertControllerWithTitle:@"Offloader" message:OFText(@"Restarting appstored…",@"Перезапуск appstored…") preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:self.storeProgress animated:YES completion:nil];
    notify_post(OFStoreRestart);
    [self pollAppStore:identifier started:NSDate.date];
}
- (void)finishAppStore:(NSString *)message {
    self.storeRequest = nil;
    UIAlertController *progress = self.storeProgress; self.storeProgress = nil;
    if (progress.presentingViewController) [progress dismissViewControllerAnimated:YES completion:^{OFPreferencesAlert(self,message);}];
    else OFPreferencesAlert(self,message);
}
- (void)pollAppStore:(NSString *)identifier started:(NSDate *)started {
    if (![self.storeRequest isEqual:identifier]) return;
    id response = OFPreferences(OFDomain)[OFStoreResponseKey];
    if (OFResponseMatches(response,identifier)) { [self finishAppStore:response[@"message"]]; return; }
    if (-started.timeIntervalSinceNow > 25) {
        id request = OFPreferences(OFDomain)[OFStoreRequestKey];
        if ([request isKindOfClass:NSDictionary.class] && [request[@"id"] isEqual:identifier]) OFWrite(OFDomain,OFStoreRequestKey,nil);
        [self finishAppStore:OFText(@"SpringBoard did not answer. Make sure Offloader is enabled for SpringBoard (Choicy), respring, and try again.",@"SpringBoard не ответил. Убедитесь, что Offloader включён для SpringBoard (Choicy), сделайте респринг и повторите.")]; return;
    }
    notify_post(OFStoreRestart);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[weakSelf pollAppStore:identifier started:started];});
}
@end
@implementation OffAntiOffloadListController
- (NSString *)title { return OFText(@"Protected Apps",@"Защищённые приложения"); }
- (void)viewDidLoad {
    [super viewDidLoad];
    self.search = [[UISearchController alloc] initWithSearchResultsController:nil];
    self.search.obscuresBackgroundDuringPresentation = NO;
    self.search.searchResultsUpdater = self;
    self.search.searchBar.placeholder = OFText(@"Name or bundle identifier",@"Название или идентификатор");
    self.navigationItem.searchController = self.search;
    self.navigationItem.hidesSearchBarWhenScrolling = NO;
    self.definesPresentationContext = YES;
    [self refreshApplications];
}
- (void)refreshApplications {
    self.loading = YES; _specifiers = nil; [self reloadSpecifiers];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        @autoreleasepool {
            NSMutableDictionary *rows = [NSMutableDictionary dictionary];
            NSString *failure = nil;
            @try {
                Class cls = NSClassFromString(@"LSApplicationWorkspace");
                id workspace = OFObject(cls,@selector(defaultWorkspace));
                id applications = OFObject(workspace,@selector(allApplications));
                if (![applications isKindOfClass:NSArray.class]) failure = OFText(@"The app list is unavailable. Your protection selections are kept.",@"Список приложений недоступен. Выбор защиты сохранён.");
                else for (id proxy in applications) {
                    NSString *identifier = OFString(proxy,@selector(bundleIdentifier));
                    if (!OFValidID(identifier)) continue;
                    if (![OFString(proxy,@selector(applicationType)) isEqual:@"User"] && !OFEligible(identifier)) continue;
                    rows[identifier] = @{@"id":identifier,@"name":OFString(proxy,@selector(localizedName)) ?: identifier};
                }
            } @catch (NSException *exception) { failure = exception.reason; }
            // Also retain selected offloaded/unavailable apps, so they can be unprotected.
            for (NSString *identifier in OFProtection()) if (!rows[identifier]) rows[identifier] = @{@"id":identifier,@"name":identifier};
            NSArray *sorted = [rows.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b){
                NSComparisonResult order = [a[@"name"] localizedStandardCompare:b[@"name"]];
                return order == NSOrderedSame ? [a[@"id"] compare:b[@"id"]] : order;
            }];
            dispatch_async(dispatch_get_main_queue(),^{
                typeof(self) controller = weakSelf; if (!controller) return;
                controller.applications = sorted; controller.loading = NO; controller->_specifiers = nil; [controller reloadSpecifiers];
                if (failure) OFPreferencesAlert(controller,failure);
            });
        }
    });
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:self.loading ? OFText(@"Loading…",@"Загрузка…") : nil];
    [group setProperty:OFText(@"A switch turned on protects the app. Search also matches the bundle identifier.",@"Включённый переключатель защищает приложение. Поиск также работает по идентификатору.") forKey:@"footerText"]; [items addObject:group];
    NSString *query = self.query ?: @"";
    for (NSDictionary *row in self.applications) {
        if (query.length && [row[@"name"] rangeOfString:query options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location == NSNotFound && [row[@"id"] rangeOfString:query options:NSCaseInsensitiveSearch].location == NSNotFound) continue;
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:row[@"name"] target:self set:@selector(setProtected:specifier:) get:@selector(readProtected:) detail:nil cell:PSSwitchCell edit:nil];
        [item setProperty:row[@"id"] forKey:@"key"]; [item setProperty:row[@"id"] forKey:@"subtitle"]; [item setProperty:OFApplicationSwitchCell.class forKey:@"cellClass"]; [items addObject:item];
    }
    _specifiers = items; return _specifiers;
}
- (id)readProtected:(PSSpecifier *)specifier { return @(OFProtected([specifier propertyForKey:@"key"])); }
- (void)setProtected:(id)value specifier:(PSSpecifier *)specifier {
    NSString *identifier = [specifier propertyForKey:@"key"];
    if (!OFValidID(identifier)) return;
    NSDictionary *previous = OFProtection();
    NSMutableDictionary *selection = [previous mutableCopy];
    BOOL enabled = OFValueBool(value,NO);
    if (enabled) selection[identifier] = @YES; else [selection removeObjectForKey:identifier];
    NSError *error;
    // Commit the cross-user file first; show success only after both stores persist.
    if (!OFWriteProtectionSnapshot(selection,&error) || !OFWrite(OFAntiDomain,identifier,enabled ? @YES : nil)) {
        OFWriteProtectionSnapshot(previous,NULL);
        OFPreferencesAlert(self,error.localizedDescription ?: OFText(@"Could not save protection.",@"Не удалось сохранить защиту.")); [self reloadSpecifiers]; return;
    }
    notify_post(OFChanged);
}
- (void)updateSearchResultsForSearchController:(UISearchController *)controller {
    self.query = [controller.searchBar.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    _specifiers = nil; [self reloadSpecifiers];
}
@end
