#import "../OFShared.h"
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

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
@end
@implementation OffRootListController
- (NSString *)title { return @"Offloader"; }
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items = [NSMutableArray array];
    PSSpecifier *group = [PSSpecifier groupSpecifierWithName:OFText(@"Home Screen Menu",@"Меню экрана Домой")];
    [group setProperty:OFText(@"Changes apply when you next open an app's menu. Delete and Edit use the standard iOS actions.",@"Изменения действуют при следующем открытии меню приложения. Удаление и редактирование используют штатные действия iOS.") forKey:@"footerText"];
    [items addObject:group];
    for (NSArray *row in @[@[@"3doffload",OFText(@"Offload App",@"Выгрузить приложение")],@[@"3ddelete",OFText(@"Delete / Remove App",@"Удалить приложение")],@[@"3dedit",OFText(@"Edit Home Screen",@"Изменить экран Домой")]]) {
        PSSpecifier *item = [PSSpecifier preferenceSpecifierNamed:row[1] target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:nil cell:PSSwitchCell edit:nil];
        [item setProperty:row[0] forKey:@"key"]; [item setProperty:@YES forKey:@"default"]; [item setProperty:OFDomain forKey:@"defaults"]; [items addObject:item];
    }
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
                    if (!OFValidID(identifier) || ![OFString(proxy,@selector(applicationType)) isEqual:@"User"]) continue;
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
        [item setProperty:row[@"id"] forKey:@"key"]; [item setProperty:row[@"id"] forKey:@"subtitle"]; [items addObject:item];
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
