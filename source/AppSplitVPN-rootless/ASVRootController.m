#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "Shared.h"
#import "ASVAppListController.h"
// Theos' deliberately minimal header omits these runtime APIs.
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
static UIFont *ASVMono(CGFloat size) { return [UIFont fontWithName:@"CourierNewPSMT" size:size] ?: [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular]; }
static UIFont *ASVMonoBold(CGFloat size) { return [UIFont fontWithName:@"CourierNewPS-BoldMT" size:size] ?: [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightBold]; }

#pragma mark - Log pages

@interface ASVLogController : UIViewController
@property(nonatomic) BOOL routes;
@property(nonatomic,strong) UITextView *textView;
@end
@implementation ASVLogController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.blackColor;
    self.title=_routes?L(@"Routing log",@"Журнал маршрутизации"):L(@"Change log",@"Журнал изменений");
    _textView=[[UITextView alloc] initWithFrame:CGRectZero];_textView.editable=NO;
    _textView.backgroundColor=UIColor.blackColor;_textView.textColor=UIColor.systemGreenColor;
    _textView.textContainerInset=UIEdgeInsetsMake(12,10,12,10);
    _textView.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:_textView];
    [NSLayoutConstraint activateConstraints:@[[_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:L(@"Clear",@"Очистить") style:UIBarButtonItemStylePlain target:self action:@selector(confirmClear)];
    [self reload];
}
- (NSString *)reasonFor:(NSString *)identifier {
    NSDictionary *record=[ASVAppListController recordForIdentifier:identifier];
    if (!record) return L(@"deleted",@"удалено");
    if ([record[@"state"] isEqual:@"offloaded"]) return L(@"offloaded",@"выгружено");
    return L(@"identity not resolved",@"не определено");
}
- (NSString *)appLabel:(NSString *)identifier {
    NSDictionary *record=[ASVAppListController recordForIdentifier:identifier];
    NSString *name=record[@"name"];
    return name.length && ![name isEqual:identifier]?[NSString stringWithFormat:@"%@ (%@)",name,identifier]:identifier;
}
- (void)reload {
    NSMutableAttributedString *body=[NSMutableAttributedString new];
    NSDictionary *normal=@{NSFontAttributeName:ASVMono(12),NSForegroundColorAttributeName:UIColor.systemGreenColor};
    NSDictionary *header=@{NSFontAttributeName:ASVMonoBold(12),NSForegroundColorAttributeName:UIColor.whiteColor};
    NSDictionary *direct=@{NSFontAttributeName:ASVMono(12),NSForegroundColorAttributeName:UIColor.systemRedColor};
    NSDictionary *skip=@{NSFontAttributeName:ASVMono(12),NSForegroundColorAttributeName:UIColor.systemGrayColor};
    void (^add)(NSString *,NSDictionary *)=^(NSString *text,NSDictionary *attributes){
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:[text stringByAppendingString:@"\n"] attributes:attributes]];
    };
    if (_routes) {
        NSArray *blocks=[NSArray arrayWithContentsOfFile:ASV_ROUTE_LOG] ?: @[];
        for (NSArray *block in [blocks reverseObjectEnumerator]) {
            if (![block isKindOfClass:NSArray.class] || !block.count) continue;
            add(block.firstObject,header);
            for (NSString *line in [block subarrayWithRange:NSMakeRange(1,block.count-1)]) {
                NSRange space=[line rangeOfString:@" "];
                if (space.location==NSNotFound) continue;
                NSString *route=[line substringToIndex:space.location];
                NSString *identifier=[[line substringFromIndex:space.location] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                if ([route isEqual:@"SKIP"]) add([NSString stringWithFormat:@"SKIP    %@ — %@",[self appLabel:identifier],[self reasonFor:identifier]],skip);
                else add([NSString stringWithFormat:@"%@ %@",[route stringByPaddingToLength:7 withString:@" " startingAtIndex:0],[self appLabel:identifier]],[route isEqual:@"DIRECT"]?direct:normal);
            }
            add(@"",normal);
        }
    } else {
        for (NSString *line in [([NSArray arrayWithContentsOfFile:ASV_LOG] ?: @[]) reverseObjectEnumerator]) add(line,normal);
    }
    if (!body.length) add(L(@"Log is empty",@"Журнал пуст"),skip);
    _textView.attributedText=body;
}
- (void)confirmClear {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:L(@"Clear both logs?",@"Очистить оба журнала?") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:L(@"Cancel",@"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:L(@"Clear",@"Очистить") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a){
        notify_post(ASV_CMD_CLEAR_LOGS);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.2*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [self reload]; });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
@end

#pragma mark - Root

@interface ASVRootController : PSListController <UIDocumentPickerDelegate> {
    NSTimer *_statusTimer;
    NSString *_statusFingerprint;
    NSArray<NSArray<NSString *> *> *_headers; // @[title, info]
    NSAttributedString *_statusText;
}
@end
@implementation ASVRootController
- (NSString *)language { return [L(@"en",@"ru") isEqual:@"ru"] ? @"ru":@"en"; }
- (NSDictionary *)prefs { return [NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{}; }
- (NSUInteger)countFor:(NSString *)key {
    NSArray *items=[self prefs][key];
    return [items isKindOfClass:NSArray.class]?items.count:0;
}
- (NSString *)statusFingerprint {
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    BOOL stale=[NSDate date].timeIntervalSince1970-[state[@"updated"] doubleValue]>90;
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%d",state[@"status"] ?: @"",state[@"error"] ?: @"",
        state[@"rules"] ?: @0,state[@"unresolved"] ?: @[],state[@"vpnName"] ?: @"",stale];
}
- (void)updateStatusIfChanged {
    if (![_statusFingerprint isEqualToString:[self statusFingerprint]]) [self refreshStatus];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [self prefs][[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (![@[@"enabled",@"mode",@"language",ASV_VPN,ASV_DIRECT] containsObject:key]) return;
    NSMutableDictionary *prefs=[[self prefs] mutableCopy];
    prefs[key]=value;
    if (![prefs writeToFile:ASV_PREFS atomically:YES]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:L(@"Could not save",@"Не удалось сохранить") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];return;
    }
    notify_post(ASV_NOTIFY);
    [self refreshStatus];
}
- (PSSpecifier *)setting:(NSString *)name key:(NSString *)key type:(PSCellType)type fallback:(id)fallback detail:(Class)detail {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:detail cell:type edit:nil];
    [s setProperty:key forKey:@"key"];[s setProperty:ASV_DOMAIN forKey:@"defaults"];[s setProperty:fallback forKey:@"default"];
    return s;
}
- (PSSpecifier *)button:(NSString *)name action:(SEL)action {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    if (action) [s setButtonAction:action];
    return s;
}
- (NSAttributedString *)buildStatus:(NSString **)codeOut {
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    NSDictionary *prefs=[self prefs];
    NSString *code=state[@"status"] ?: @"unavailable";
    if ([NSDate date].timeIntervalSince1970-[state[@"updated"] doubleValue]>90) code=@"unavailable";
    if (codeOut) *codeOut=code;
    BOOL enabled=[prefs[@"enabled"] boolValue];
    BOOL tunnel=[prefs[@"mode"] isEqual:@"tunnelOnly"];
    NSString *listName=tunnel?@"VPN":@"DIRECT";
    NSArray *apps=prefs[tunnel?ASV_VPN:ASV_DIRECT];
    NSUInteger total=[apps isKindOfClass:NSArray.class]?apps.count:0;
    BOOL applied=[@[@"active",@"partial"] containsObject:code];
    NSArray *missing=applied?(state[@"unresolved"] ?: @[]):@[];
    NSUInteger offloaded=0,deleted=0,unknown=0;
    for (NSString *identifier in missing) {
        NSDictionary *record=[ASVAppListController recordForIdentifier:identifier];
        if (!record) deleted++; else if ([record[@"state"] isEqual:@"offloaded"]) offloaded++; else unknown++;
    }
    NSMutableAttributedString *text=[NSMutableAttributedString new];
    UIColor *green=UIColor.systemGreenColor, *red=UIColor.systemRedColor, *gray=UIColor.systemGrayColor;
    void (^line)(NSString *,NSString *,UIColor *)=^(NSString *label,NSString *value,UIColor *color){
        if (text.length) [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:[label stringByPaddingToLength:13 withString:@" " startingAtIndex:0] attributes:@{NSFontAttributeName:ASVMono(14),NSForegroundColorAttributeName:gray}]];
        [text appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:@{NSFontAttributeName:ASVMonoBold(14),NSForegroundColorAttributeName:color}]];
    };
    line(L(@"Tweak:",@"Твик:"),enabled?L(@"enabled",@"включён"):L(@"disabled",@"выключен"),enabled?green:red);
    BOOL down=[@[@"waitingVPN",@"unavailable",@"stopped"] containsObject:code];
    NSString *vpnState=[code isEqual:@"waitingVPN"]?L(@"not connected",@"не подключён"):([code isEqual:@"disabled"]?L(@"not used",@"не используется"):L(@"connected",@"подключён"));
    if ([code isEqual:@"unavailable"] || [code isEqual:@"stopped"]) vpnState=L(@"service stopped",@"служба не запущена");
    line(@"VPN:",vpnState,down?red:green);
    line(L(@"Mode:",@"Режим:"),tunnel?@"TUNNEL ONLY":@"BYPASS",UIColor.whiteColor);
    line([listName stringByAppendingString:@":"],[NSString stringWithFormat:L(@"%lu apps",@"%lu прил."),(unsigned long)total],tunnel?green:red);
    if (applied) {
        line(tunnel?L(@"Via VPN:",@"Через VPN:"):L(@"Direct:",@"Напрямую:"),[NSString stringWithFormat:@"%lu",(unsigned long)(total-MIN(total,missing.count))],green);
        line(L(@"Skipped:",@"Пропущено:"),[NSString stringWithFormat:@"%lu",(unsigned long)missing.count],missing.count?UIColor.systemOrangeColor:green);
        if (offloaded) line(L(@" offloaded",@" выгружено"),[NSString stringWithFormat:@"%lu",(unsigned long)offloaded],gray);
        if (deleted) line(L(@" deleted",@" удалено"),[NSString stringWithFormat:@"%lu",(unsigned long)deleted],gray);
        if (unknown) line(L(@" unresolved",@" не опред."),[NSString stringWithFormat:@"%lu",(unsigned long)unknown],gray);
        line(L(@"NECP rules:",@"Правил NECP:"),[state[@"rules"] description] ?: @"0",gray);
    }
    if ([code isEqual:@"error"] || [code isEqual:@"unsupported"]) line(L(@"Error:",@"Ошибка:"),[state[@"error"] length]?state[@"error"]:code,red);
    return text;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items=[NSMutableArray array];
    NSMutableArray *headers=[NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[@"App Split VPN",L(@"Uses the active system VPN of any app. Its own settings and routes still apply.\n\nTUNNEL ONLY: only apps from the VPN list use the tunnel, all others go direct.\nBYPASS: apps from the DIRECT list go direct, all others use the VPN.",@"Работает с активным системным VPN любого приложения. Его собственные настройки и маршруты сохраняются.\n\nTUNNEL ONLY: через туннель идут только приложения из списка VPN, остальные — напрямую.\nBYPASS: приложения из списка DIRECT идут напрямую, остальные — через VPN.")]];
    [items addObject:[self setting:L(@"Enable",@"Включить") key:@"enabled" type:PSSwitchCell fallback:@NO detail:nil]];
    PSSpecifier *mode=[self setting:L(@"Mode",@"Режим") key:@"mode" type:PSLinkListCell fallback:@"bypass" detail:NSClassFromString(@"PSListItemsController")];
    if ([mode respondsToSelector:@selector(setValues:titles:)]) [mode setValues:@[@"tunnelOnly",@"bypass"] titles:@[@"TUNNEL ONLY",@"BYPASS"]];
    else [mode setProperty:@NO forKey:@"enabled"];
    [items addObject:mode];
    PSSpecifier *language=[self setting:L(@"Language",@"Язык") key:@"language" type:PSLinkListCell fallback:@"system" detail:NSClassFromString(@"PSListItemsController")];
    if ([language respondsToSelector:@selector(setValues:titles:)]) [language setValues:@[@"system",@"ru",@"en"] titles:@[L(@"System",@"Системный"),@"Русский",@"English"]];
    [items addObject:language];

    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"App lists",@"Списки приложений"),L(@"The two lists are independent; only the list of the current mode is applied.\n\nAfter changing the rules, reopen the affected apps: already open connections keep their old route.\n\nImport skips apps that are not installed and keeps them in the list for a later reinstall.",@"Списки независимы: применяется только список текущего режима.\n\nПосле изменения правил переоткройте нужные приложения — уже открытые соединения сохраняют прежний маршрут.\n\nПри импорте отсутствующие приложения пропускаются и остаются в списке до установки.")]];
    NSUInteger total=[ASVAppListController installedApplicationCount];
    PSSpecifier *vpn=[self button:@"VPN" action:@selector(openVPNList)];
    [vpn setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_VPN],(unsigned long)total] forKey:@"asvCount"];
    [vpn setProperty:@"green" forKey:@"asvColor"];[items addObject:vpn];
    PSSpecifier *direct=[self button:@"DIRECT" action:@selector(openDirectList)];
    [direct setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_DIRECT],(unsigned long)total] forKey:@"asvCount"];
    [direct setProperty:@"red" forKey:@"asvColor"];[items addObject:direct];
    PSSpecifier *transfer=[PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [transfer setProperty:@YES forKey:@"asvTransfer"];[items addObject:transfer];

    NSString *code=nil;
    _statusText=[self buildStatus:&code];
    _statusFingerprint=[self statusFingerprint];
    BOOL healthy=[@[@"active",@"partial"] containsObject:code];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[[NSString stringWithFormat:@"%@ %@",healthy?@"🟢":@"🔴",L(@"Status",@"Статус")],L(@"Skipped: selected apps that cannot get a rule now. Offloaded and deleted apps have no executable; they are routed again after reinstall.\n\nNECP rules: one system rule per executable, i.e. the app itself plus each of its extensions (widgets, share, notifications, keyboards). That is why there are more rules than apps.",@"Пропущено: выбранные приложения, для которых сейчас нельзя создать правило. У выгруженных и удалённых нет исполняемого файла; после установки правило появится снова.\n\nПравил NECP: одно системное правило на каждый исполняемый файл — само приложение плюс каждое его расширение (виджеты, «Поделиться», уведомления, клавиатуры). Поэтому правил больше, чем приложений.")]];
    PSSpecifier *terminal=[PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [terminal setProperty:@YES forKey:@"asvTerminal"];[items addObject:terminal];
    [items addObject:[self button:L(@"Refresh status",@"Обновить статус") action:@selector(refreshStatus)]];
    [items addObject:[self button:L(@"Routing log",@"Журнал маршрутизации") action:@selector(openRouteLog)]];
    [items addObject:[self button:L(@"Change log",@"Журнал изменений") action:@selector(openChangeLog)]];

    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    NSString *vpnName=state[@"vpnName"];
    BOOL vpnUp=![@[@"waitingVPN",@"unavailable",@"stopped"] containsObject:code];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"Active VPN",@"Активный VPN"),L(@"The name is shown when exactly one VPN configuration is enabled in the system; otherwise the active one cannot be identified reliably.",@"Название показывается, если в системе включена ровно одна конфигурация VPN; иначе активную нельзя надёжно определить.")]];
    NSString *activeName=vpnUp?(vpnName.length?vpnName:L(@"Connected",@"Подключён")):L(@"Not connected",@"Не подключён");
    PSSpecifier *active=[PSSpecifier preferenceSpecifierNamed:activeName target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [active setProperty:vpnUp?@"green":@"gray" forKey:@"asvDot"];[items addObject:active];
    _headers=[headers copy];
    _specifiers=[items copy];return _specifiers;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section>=(NSInteger)_headers.count) return nil;
    UIView *view=[UIView new];
    UILabel *label=[UILabel new];label.text=_headers[section][0];
    label.font=[UIFont systemFontOfSize:20 weight:UIFontWeightBold];label.textColor=UIColor.labelColor;
    UIButton *info=[UIButton buttonWithType:UIButtonTypeInfoLight];info.tag=section;
    [info addTarget:self action:@selector(showInfo:) forControlEvents:UIControlEventTouchUpInside];
    label.translatesAutoresizingMaskIntoConstraints=NO;info.translatesAutoresizingMaskIntoConstraints=NO;
    [view addSubview:label];[view addSubview:info];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.layoutMarginsGuide.leadingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-6],
        [info.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [info.centerYAnchor constraintEqualToAnchor:label.centerYAnchor]]];
    return view;
}
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return section==0?34:40; }
- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section { return 4; }
- (UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)section { return [UIView new]; }
- (void)showInfo:(UIButton *)sender {
    NSArray *header=_headers[sender.tag];
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:header[0] message:header[1] preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (CGFloat)terminalHeight {
    CGFloat width=MAX(200,self.view.bounds.size.width-40-24);
    CGRect box=[_statusText boundingRectWithSize:CGSizeMake(width,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin context:nil];
    return ceil(box.size.height)+24;
}
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier=[self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"asvTerminal"]) return [self terminalHeight];
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier=[self specifierAtIndexPath:indexPath];
    for (UIView *view in [cell.contentView.subviews copy]) if (view.tag==0x5A5) [view removeFromSuperview];
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
    } else if ([specifier propertyForKey:@"asvTransfer"]) {
        cell.textLabel.text=nil;cell.selectionStyle=UITableViewCellSelectionStyleNone;
        UIStackView *row=[UIStackView new];row.tag=0x5A5;row.axis=UILayoutConstraintAxisHorizontal;row.distribution=UIStackViewDistributionFillEqually;
        for (NSArray *item in @[@[L(@"Export",@"Экспорт"),@"square.and.arrow.up",NSStringFromSelector(@selector(exportLists))],@[L(@"Import",@"Импорт"),@"square.and.arrow.down",NSStringFromSelector(@selector(importLists))]]) {
            UIButton *button=[UIButton buttonWithType:UIButtonTypeSystem];
            UIButtonConfiguration *config=[UIButtonConfiguration plainButtonConfiguration];
            config.title=item[0];config.image=[UIImage systemImageNamed:item[1]];config.imagePadding=6;
            button.configuration=config;[button addTarget:self action:NSSelectorFromString(item[2]) forControlEvents:UIControlEventTouchUpInside];
            [row addArrangedSubview:button];
        }
        row.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:row];
        [NSLayoutConstraint activateConstraints:@[[row.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],[row.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],[row.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor],[row.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor]]];
    } else if ([specifier propertyForKey:@"asvTerminal"]) {
        cell.textLabel.text=nil;cell.selectionStyle=UITableViewCellSelectionStyleNone;
        cell.backgroundColor=UIColor.blackColor;
        UILabel *label=[UILabel new];label.tag=0x5A5;label.numberOfLines=0;label.attributedText=_statusText;
        label.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:label];
        [NSLayoutConstraint activateConstraints:@[[label.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:12],[label.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:12],[label.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-12]]];
    } else if ([specifier propertyForKey:@"asvDot"]) {
        BOOL up=[[specifier propertyForKey:@"asvDot"] isEqual:@"green"];
        cell.imageView.image=[UIImage systemImageNamed:up?@"lock.shield.fill":@"shield.slash"];
        cell.imageView.tintColor=up?UIColor.systemGreenColor:UIColor.secondaryLabelColor;
        cell.textLabel.textColor=up?UIColor.labelColor:UIColor.secondaryLabelColor;
    }
    return cell;
}
- (void)refreshStatus { _specifiers=nil;[self reloadSpecifiers];[self fitPage]; }
- (UITableView *)asvTable {
    if ([self.view isKindOfClass:UITableView.class]) return (UITableView *)self.view;
    for (UIView *view in self.view.subviews) if ([view isKindOfClass:UITableView.class]) return (UITableView *)view;
    return nil;
}
// Fixed page: scrolling stays off unless the content cannot fit (small screens, large text).
- (void)fitPage {
    dispatch_async(dispatch_get_main_queue(),^{
        UITableView *table=[self asvTable];
        if (!table) return;
        [table layoutIfNeeded];
        CGFloat visible=table.bounds.size.height-table.adjustedContentInset.top-table.adjustedContentInset.bottom;
        BOOL scroll=table.contentSize.height>visible+1;
        if (table.scrollEnabled!=scroll) table.scrollEnabled=scroll;
        table.alwaysBounceVertical=NO;table.bounces=scroll;
        if (!scroll && table.contentOffset.y!=-table.adjustedContentInset.top) [table setContentOffset:CGPointMake(0,-table.adjustedContentInset.top) animated:NO];
    });
}
- (void)viewDidAppear:(BOOL)animated { [super viewDidAppear:animated];[self fitPage]; }
- (void)openList:(NSString *)key {
    ASVAppListController *controller=[[ASVAppListController alloc] initWithListKey:key language:[self language]];
    [self.navigationController pushViewController:controller animated:YES];
}
- (void)openVPNList { [self openList:ASV_VPN]; }
- (void)openDirectList { [self openList:ASV_DIRECT]; }
- (void)openLog:(BOOL)routes { ASVLogController *page=[ASVLogController new];page.routes=routes;[self.navigationController pushViewController:page animated:YES]; }
- (void)openRouteLog { [self openLog:YES]; }
- (void)openChangeLog { [self openLog:NO]; }
- (void)exportLists {
    NSDictionary *prefs=[self prefs];
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
        NSArray *items=valid?payload[key]:nil;
        if (![items isKindOfClass:NSArray.class] || items.count>2048) valid=NO;
        for (id item in items) if (![item isKindOfClass:NSString.class] || [item length]<1 || [item length]>255 || [item rangeOfCharacterFromSet:bad].location!=NSNotFound) valid=NO;
    }
    if (valid) {
        NSMutableDictionary *prefs=[[self prefs] mutableCopy];
        prefs[ASV_VPN]=[[NSOrderedSet orderedSetWithArray:payload[ASV_VPN]] array];
        prefs[ASV_DIRECT]=[[NSOrderedSet orderedSetWithArray:payload[ASV_DIRECT]] array];
        valid=[prefs writeToFile:ASV_PREFS atomically:YES];
        if (valid) { notify_post(ASV_NOTIFY);[self refreshStatus]; }
    }
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:valid?L(@"Lists imported",@"Списки импортированы"):L(@"Invalid list file",@"Неверный файл списков") message:valid?L(@"Missing apps are kept in the lists and skipped until installed.",@"Отсутствующие приложения сохраняются в списках и пропускаются до установки."):nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];[self refreshStatus];
    [_statusTimer invalidate];
    _statusTimer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(updateStatusIfChanged) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [_statusTimer invalidate];_statusTimer=nil;[super viewWillDisappear:animated]; }
- (void)dealloc { [_statusTimer invalidate]; }
@end

