#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Shared.h"
#import "ASVAppListController.h"
// Theos' deliberately minimal header omits this API, also used by AirKeeper.
// Keep the runtime gate; verify the selector on the target Settings process in QA.
@interface PSSpecifier (ASVListValues)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end
@interface PSListController (ASVIndexPath)
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end
static NSString *L(NSString *en,NSString *ru) {
    NSString *chosen=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][@"language"];
    BOOL russian=[chosen isEqual:@"ru"] || (![chosen isEqual:@"en"] && [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"]);
    return russian ? ru : en;
}
@interface ASVRootController : PSListController <UIDocumentPickerDelegate> {
    NSTimer *_statusTimer;
    NSString *_statusFingerprint;
}
@end
@implementation ASVRootController
- (NSString *)language { return [L(@"en",@"ru") isEqual:@"ru"] ? @"ru":@"en"; }
- (NSUInteger)countFor:(NSString *)key {
    NSArray *items=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][key];
    return [items isKindOfClass:NSArray.class]?items.count:0;
}
- (NSString *)statusFingerprint {
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    BOOL stale=[NSDate date].timeIntervalSince1970-[state[@"updated"] doubleValue]>90;
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%d",state[@"status"] ?: @"",state[@"error"] ?: @"",
        state[@"rules"] ?: @0,state[@"unresolved"] ?: @[],stale];
}
- (void)updateStatusIfChanged {
    NSString *current=[self statusFingerprint];
    if (![_statusFingerprint isEqualToString:current]) [self refreshStatus];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (![@[@"enabled",@"mode",@"language",ASV_VPN,ASV_DIRECT] containsObject:key]) return;
    NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[key]=value;
    if (![prefs writeToFile:ASV_PREFS atomically:YES]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:L(@"Could not save",@"Не удалось сохранить") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];return;
    }
    notify_post(ASV_NOTIFY);
    if ([key isEqual:@"language"]) [self refreshStatus];
}
- (PSSpecifier *)setting:(NSString *)name key:(NSString *)key type:(PSCellType)type fallback:(id)fallback detail:(Class)detail {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:detail cell:type edit:nil];
    [s setProperty:key forKey:@"key"];[s setProperty:ASV_DOMAIN forKey:@"defaults"];[s setProperty:fallback forKey:@"default"];
    return s;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items=[NSMutableArray array];
    PSSpecifier *group=[PSSpecifier groupSpecifierWithName:@"App Split VPN"];
    [group setProperty:L(@"Uses the active system VPN. VPN settings and routes still apply.",@"Использует активный системный VPN. Его настройки и маршруты сохраняются.") forKey:@"footerText"];
    [items addObject:group];
    [items addObject:[self setting:L(@"Enable",@"Включить") key:@"enabled" type:PSSwitchCell fallback:@NO detail:nil]];
    PSSpecifier *mode=[self setting:L(@"Mode",@"Режим") key:@"mode" type:PSLinkListCell fallback:@"bypass" detail:NSClassFromString(@"PSListItemsController")];
    if ([mode respondsToSelector:@selector(setValues:titles:)])
        [mode setValues:@[@"tunnelOnly",@"bypass"] titles:@[@"TUNNEL ONLY",@"BYPASS"]];
    else [mode setProperty:@NO forKey:@"enabled"];
    [items addObject:mode];
    PSSpecifier *language=[self setting:L(@"Language",@"Язык") key:@"language" type:PSLinkListCell fallback:@"system" detail:NSClassFromString(@"PSListItemsController")];
    if ([language respondsToSelector:@selector(setValues:titles:)])
        [language setValues:@[@"system",@"ru",@"en"] titles:@[L(@"System",@"Системный"),@"Русский",@"English"]];
    [items addObject:language];
    group=[PSSpecifier groupSpecifierWithName:L(@"Application lists",@"Списки приложений")];
    [group setProperty:L(@"TUNNEL ONLY: only VPN apps use the tunnel. BYPASS: DIRECT apps bypass it. Reopen apps after changing rules.",@"TUNNEL ONLY: туннель только для списка VPN. BYPASS: список DIRECT идёт напрямую. После изменения правил переоткройте приложения.") forKey:@"footerText"];
    [items addObject:group];
    NSUInteger total=[ASVAppListController installedApplicationCount];
    PSSpecifier *vpn=[PSSpecifier preferenceSpecifierNamed:@"VPN" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [vpn setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_VPN],(unsigned long)total] forKey:@"asvCount"];
    [vpn setProperty:@"green" forKey:@"asvColor"];
    [vpn setButtonAction:@selector(openVPNList)];[items addObject:vpn];
    PSSpecifier *direct=[PSSpecifier preferenceSpecifierNamed:@"DIRECT" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [direct setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_DIRECT],(unsigned long)total] forKey:@"asvCount"];
    [direct setProperty:@"red" forKey:@"asvColor"];
    [direct setButtonAction:@selector(openDirectList)];[items addObject:direct];
    PSSpecifier *export=[PSSpecifier preferenceSpecifierNamed:L(@"Export lists",@"Экспорт списков") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [export setButtonAction:@selector(exportLists)];[items addObject:export];
    PSSpecifier *import=[PSSpecifier preferenceSpecifierNamed:L(@"Import lists",@"Импорт списков") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [import setButtonAction:@selector(importLists)];[items addObject:import];
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    _statusFingerprint=[self statusFingerprint];
    NSString *code=state[@"status"] ?: @"unavailable";
    if ([NSDate date].timeIntervalSince1970-[state[@"updated"] doubleValue]>90) code=@"unavailable";
    NSDictionary *labels=@{
        @"disabled":L(@"Disabled",@"Выключен"),@"waitingVPN":L(@"Waiting for VPN",@"Ожидание VPN"),
        @"active":L(@"Rules applied",@"Правила применены"),
        @"partial":L(@"Available apps routed",@"Доступные приложения направлены"),
        @"error":L(@"Rules could not be updated",@"Не удалось обновить правила"),
        @"unsupported":L(@"System API unavailable",@"Системный API недоступен"),
        @"stopped":L(@"Service stopped",@"Служба остановлена"),@"unavailable":L(@"Service has not started",@"Служба ещё не запущена")};
    BOOL healthy=[@[@"active",@"partial"] containsObject:code];
    group=[PSSpecifier groupSpecifierWithName:[NSString stringWithFormat:@"%@ %@",healthy?@"🟢":@"🔴",L(@"Status",@"Статус")]];
    NSMutableArray *lines=[NSMutableArray arrayWithObject:labels[code] ?: code];
    if ([@[@"active",@"partial"] containsObject:code] && [state[@"rules"] integerValue]>0)
        [lines addObject:[NSString stringWithFormat:L(@"Rules: %@",@"Правил: %@"),state[@"rules"]]];
    NSArray *missing=state[@"unresolved"];
    if (missing.count) [lines addObject:[NSString stringWithFormat:L(@"Offloaded or unavailable: %lu",@"Выгружено или недоступно: %lu"),(unsigned long)missing.count]];
    NSString *detail=state[@"error"];
    if (detail.length) [lines addObject:detail];
    [group setProperty:[lines componentsJoinedByString:@"\n"] forKey:@"footerText"];[items addObject:group];
    PSSpecifier *refresh=[PSSpecifier preferenceSpecifierNamed:L(@"Refresh status",@"Обновить статус") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [refresh setButtonAction:@selector(refreshStatus)];[items addObject:refresh];
    PSSpecifier *logs=[PSSpecifier preferenceSpecifierNamed:L(@"Routing log",@"Журнал маршрутизации") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [logs setButtonAction:@selector(openLogs)];[items addObject:logs];
    NSString *vpnName=state[@"vpnName"];
    BOOL vpnUp=vpnName.length && ![code isEqual:@"waitingVPN"] && ![code isEqual:@"unavailable"];
    group=[PSSpecifier groupSpecifierWithName:L(@"Active VPN",@"Активный VPN")];[items addObject:group];
    PSSpecifier *active=[PSSpecifier preferenceSpecifierNamed:vpnUp?vpnName:L(@"Not connected",@"Не подключён") target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [active setProperty:vpnUp?@"green":@"gray" forKey:@"asvDot"];
    [items addObject:active];
    _specifiers=[items copy];return _specifiers;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier=[self specifierAtIndexPath:indexPath];
    NSString *color=[specifier propertyForKey:@"asvColor"];
    if (color) {
        UIColor *tint=[color isEqual:@"green"]?UIColor.systemGreenColor:UIColor.systemRedColor;
        cell.textLabel.textColor=tint;
        UILabel *count=[UILabel new];count.text=[specifier propertyForKey:@"asvCount"];count.textColor=tint;
        count.font=[UIFont monospacedDigitSystemFontOfSize:17 weight:UIFontWeightRegular];[count sizeToFit];
        UIImageView *chevron=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightSemibold]]];
        chevron.tintColor=UIColor.tertiaryLabelColor;[chevron sizeToFit];
        CGFloat height=MAX(count.bounds.size.height,chevron.bounds.size.height);
        UIView *box=[[UIView alloc] initWithFrame:CGRectMake(0,0,count.bounds.size.width+10+chevron.bounds.size.width,height)];
        count.frame=CGRectMake(0,(height-count.bounds.size.height)/2,count.bounds.size.width,count.bounds.size.height);
        chevron.frame=CGRectMake(count.bounds.size.width+10,(height-chevron.bounds.size.height)/2,chevron.bounds.size.width,chevron.bounds.size.height);
        [box addSubview:count];[box addSubview:chevron];cell.accessoryView=box;
    } else if ([specifier propertyForKey:@"asvDot"]) {
        BOOL up=[[specifier propertyForKey:@"asvDot"] isEqual:@"green"];
        cell.imageView.image=[UIImage systemImageNamed:up?@"lock.shield.fill":@"shield.slash"];
        cell.imageView.tintColor=up?UIColor.systemGreenColor:UIColor.secondaryLabelColor;
        cell.textLabel.textColor=up?UIColor.labelColor:UIColor.secondaryLabelColor;
        cell.accessoryView=nil;
    }
    return cell;
}
- (void)refreshStatus { _specifiers=nil;[self reloadSpecifiers]; }
- (void)openList:(NSString *)key {
    ASVAppListController *controller=[[ASVAppListController alloc] initWithListKey:key language:[self language]];
    [self.navigationController pushViewController:controller animated:YES];
}
- (void)openVPNList { [self openList:ASV_VPN]; }
- (void)openDirectList { [self openList:ASV_DIRECT]; }
- (void)exportLists {
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{};
    NSDictionary *payload=@{@"format":@"appsplitvpn-lists-v1",ASV_VPN:prefs[ASV_VPN] ?: @[],ASV_DIRECT:prefs[ASV_DIRECT] ?: @[]};
    NSData *data=[NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:nil];
    NSURL *url=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"AppSplitVPN-lists.json"];
    if (![data writeToURL:url atomically:YES]) return;
    UIActivityViewController *share=[[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:nil];
    share.popoverPresentationController.sourceView=self.view;
    [self presentViewController:share animated:YES completion:nil];
}
- (void)importLists {
    UIDocumentPickerViewController *picker=[[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeJSON,UTTypePlainText] asCopy:YES];
    picker.delegate=self;[self presentViewController:picker animated:YES completion:nil];
}
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSData *data=[NSData dataWithContentsOfURL:urls.firstObject options:0 error:nil];
    NSDictionary *payload=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    BOOL valid=[payload isKindOfClass:NSDictionary.class] && [payload[@"format"] isEqual:@"appsplitvpn-lists-v1"];
    NSCharacterSet *bad=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"].invertedSet;
    for (NSString *key in @[ASV_VPN,ASV_DIRECT]) {
        NSArray *items=payload[key];
        if (![items isKindOfClass:NSArray.class] || items.count>2048) valid=NO;
        for (id item in items) if (![item isKindOfClass:NSString.class] || [item length]<1 || [item length]>255 || [item rangeOfCharacterFromSet:bad].location!=NSNotFound) valid=NO;
    }
    if (valid) {
        NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];
        prefs[ASV_VPN]=[[NSOrderedSet orderedSetWithArray:payload[ASV_VPN]] array];
        prefs[ASV_DIRECT]=[[NSOrderedSet orderedSetWithArray:payload[ASV_DIRECT]] array];
        valid=[prefs writeToFile:ASV_PREFS atomically:YES];
        if (valid) { notify_post(ASV_NOTIFY);[self refreshStatus]; }
    }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:valid?L(@"Lists imported",@"Списки импортированы"):L(@"Invalid list file",@"Неверный файл списков") message:valid?L(@"Missing apps are kept in the lists and skipped until installed.",@"Отсутствующие приложения сохраняются в списках и пропускаются до установки."):nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)openLogs {
    NSArray *lines=[NSArray arrayWithContentsOfFile:ASV_LOG] ?: @[];
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{};
    NSString *mode=[prefs[@"mode"] isEqual:@"tunnelOnly"]?@"TUNNEL ONLY":@"BYPASS";
    NSString *selectedKey=[prefs[@"mode"] isEqual:@"tunnelOnly"]?ASV_VPN:ASV_DIRECT;
    NSString *selectedRoute=[selectedKey isEqual:ASV_VPN]?@"VPN":@"DIRECT";
    NSString *otherRoute=[selectedKey isEqual:ASV_VPN]?@"DIRECT":@"VPN";
    NSMutableString *body=[NSMutableString stringWithFormat:@"%@\n%@: %@\n\n",mode,L(@"Other apps",@"Остальные приложения"),otherRoute];
    for (NSString *identifier in prefs[selectedKey]) [body appendFormat:@"%@  %@\n",selectedRoute,identifier];
    [body appendFormat:@"\n%@\n",L(@"Rule changes",@"Изменения правил")];
    for (NSString *line in [lines reverseObjectEnumerator]) [body appendFormat:@"%@\n",line];
    UIViewController *page=[UIViewController new];page.title=L(@"Routing log",@"Журнал маршрутизации");
    UITextView *view=[[UITextView alloc] initWithFrame:CGRectZero];view.editable=NO;view.font=[UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];view.text=body;
    view.translatesAutoresizingMaskIntoConstraints=NO;[page.view addSubview:view];
    [NSLayoutConstraint activateConstraints:@[[view.topAnchor constraintEqualToAnchor:page.view.safeAreaLayoutGuide.topAnchor],[view.bottomAnchor constraintEqualToAnchor:page.view.bottomAnchor],[view.leadingAnchor constraintEqualToAnchor:page.view.leadingAnchor],[view.trailingAnchor constraintEqualToAnchor:page.view.trailingAnchor]]];
    [self.navigationController pushViewController:page animated:YES];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];[self refreshStatus];
    [_statusTimer invalidate];
    _statusTimer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(updateStatusIfChanged) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [_statusTimer invalidate];_statusTimer=nil;[super viewWillDisappear:animated]; }
- (void)dealloc { [_statusTimer invalidate]; }
@end
