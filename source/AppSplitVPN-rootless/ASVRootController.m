#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <arpa/inet.h>
#import "ASVUI.h"
#import "ASVAppListController.h"
#import "ASVExtraController.h"
// Theos' deliberately minimal header omits these runtime APIs.
@interface PSSpecifier (ASVListValues)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end
@interface PSListController (ASVIndexPath)
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end
#import <Preferences/PSListItemsController.h>
// TUNNEL ONLY is green and BYPASS is red everywhere the mode is shown.
static UIColor *ASVModeColor(NSString *text) {
    if ([text isEqual:@"TUNNEL ONLY"] || [text isEqual:@"tunnelOnly"]) return UIColor.systemGreenColor;
    if ([text isEqual:@"BYPASS"] || [text isEqual:@"bypass"]) return UIColor.systemRedColor;
    return nil;
}

// Public IP and country from a Cloudflare trace, a JSON object or plain text.
static NSArray<NSString *> *ASVParseIP(NSData *data) {
    NSString *body=[[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
    if (!body.length) return nil;
    NSString *ip=nil,*country=nil;
    if ([body containsString:@"ip="]) {
        for (NSString *line in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
            if ([line hasPrefix:@"ip="]) ip=[line substringFromIndex:3];
            else if ([line hasPrefix:@"loc="]) country=[line substringFromIndex:4];
        }
    } else {
        id json=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
        if ([json isKindOfClass:NSString.class]) ip=json;
        else if ([json isKindOfClass:NSDictionary.class]) {
            for (NSString *key in @[@"ip",@"query",@"ip_addr",@"address"]) if ([json[key] isKindOfClass:NSString.class]) { ip=json[key];break; }
            for (NSString *key in @[@"country_code",@"countryCode",@"country",@"cc",@"loc"]) if ([json[key] isKindOfClass:NSString.class] && [json[key] length]==2) { country=json[key];break; }
        } else ip=body;
    }
    ip=[ip stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n\""]];
    unsigned char buffer[16];
    if (!ip.length || (inet_pton(AF_INET,ip.UTF8String,buffer)!=1 && inet_pton(AF_INET6,ip.UTF8String,buffer)!=1)) return nil;
    country=country.uppercaseString;
    BOOL letters=country.length==2;
    for (NSUInteger i=0;letters && i<2;i++) letters=[country characterAtIndex:i]>='A' && [country characterAtIndex:i]<='Z';
    return letters ? @[ip,country] : @[ip];
}
static NSString *ASVFlag(NSString *country) {
    if (country.length!=2) return @"";
    uint32_t a=0x1F1E6+[country characterAtIndex:0]-'A', b=0x1F1E6+[country characterAtIndex:1]-'A';
    uint32_t scalars[2]={NSSwapHostIntToLittle(a),NSSwapHostIntToLittle(b)};
    return [[NSString alloc] initWithBytes:scalars length:sizeof scalars encoding:NSUTF32LittleEndianStringEncoding] ?: @"";
}

#pragma mark - Mode picker

@interface ASVModeListController : PSListItemsController
@end
@implementation ASVModeListController
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[super tableView:tableView cellForRowAtIndexPath:indexPath];
    UIColor *color=ASVModeColor(cell.textLabel.text);
    if (color) { cell.textLabel.textColor=color;cell.tintColor=color; }
    return cell;
}
@end

#pragma mark - Log pages

@interface ASVLogController : UIViewController
@property(nonatomic,strong) UITextView *textView;
@property(nonatomic,strong) NSTimer *timer;
@property(nonatomic,strong) NSDate *loaded;
@end
@implementation ASVLogController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.blackColor;
    self.title=L(@"Routing log",@"Журнал маршрутизации");
    _textView=[[UITextView alloc] initWithFrame:CGRectZero];_textView.editable=NO;
    _textView.backgroundColor=UIColor.blackColor;_textView.textColor=UIColor.systemGreenColor;
    _textView.textContainerInset=UIEdgeInsetsMake(12,10,12,10);
    _textView.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:_textView];
    [NSLayoutConstraint activateConstraints:@[[_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    [self reload];
}
// The service rewrites the file whenever the effective rules change; follow it live.
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_timer invalidate];
    _timer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(reloadIfChanged) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [_timer invalidate];_timer=nil;[super viewWillDisappear:animated]; }
- (void)reloadIfChanged {
    NSDate *modified=[[NSFileManager defaultManager] attributesOfItemAtPath:ASV_ROUTE_LOG error:nil].fileModificationDate;
    if (modified && ![modified isEqualToDate:_loaded]) [self reload];
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
    _loaded=[[NSFileManager defaultManager] attributesOfItemAtPath:ASV_ROUTE_LOG error:nil].fileModificationDate;
    NSMutableAttributedString *body=[NSMutableAttributedString new];
    NSDictionary *normal=@{NSFontAttributeName:ASVMono(12),NSForegroundColorAttributeName:UIColor.systemGreenColor};
    NSDictionary *header=@{NSFontAttributeName:ASVMonoBold(12),NSForegroundColorAttributeName:UIColor.whiteColor};
    NSDictionary *direct=@{NSFontAttributeName:ASVMono(12),NSForegroundColorAttributeName:UIColor.systemRedColor};
    NSDictionary *skip=@{NSFontAttributeName:ASVMono(12),NSForegroundColorAttributeName:UIColor.systemGrayColor};
    void (^add)(NSString *,NSDictionary *)=^(NSString *text,NSDictionary *attributes){
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:[text stringByAppendingString:@"\n"] attributes:attributes]];
    };
    {
        NSArray *blocks=[NSArray arrayWithContentsOfFile:ASV_ROUTE_LOG] ?: @[];
        for (NSArray *block in [blocks.lastObject isKindOfClass:NSArray.class]?@[blocks.lastObject]:@[]) {
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
    }
    if (!body.length) add(L(@"No rules are applied yet",@"Правила ещё не применены"),skip);
    CGPoint offset=_textView.contentOffset;
    _textView.attributedText=body;
    [_textView setContentOffset:offset animated:NO];
}
- (void)dealloc { [_timer invalidate]; }
@end

#pragma mark - Root

@interface ASVRootController : PSListController <UIDocumentPickerDelegate> {
    NSTimer *_statusTimer;
    NSString *_statusFingerprint;
    NSArray<NSArray<NSString *> *> *_headers; // @[title, info]
    NSAttributedString *_statusText;
    NSArray<NSString *> *_ip;     // @[address, optional country]
    BOOL _ipLoading;
    NSUInteger _ipToken;
    NSString *_ipRoute;           // VPN/mode state the IP was measured for
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
    NSDictionary *prefs=[self prefs];
    // Include the switch and mode so a change made from Control Center shows up here too.
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%d|%d|%@",state[@"status"] ?: @"",state[@"error"] ?: @"",
        state[@"rules"] ?: @0,state[@"unresolved"] ?: @[],state[@"vpnName"] ?: @"",state[@"mode"] ?: @"",stale,
        [prefs[@"enabled"] boolValue],prefs[@"mode"] ?: @""];
}
- (void)updateStatusIfChanged {
    if (![_statusFingerprint isEqualToString:[self statusFingerprint]]) [self refreshStatus];
    if (_ipRoute && ![_ipRoute isEqualToString:[self ipRoute]]) [self fetchIP];
}
// The public IP changes with the VPN state, its name and the routing mode.
- (NSString *)ipRoute {
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    NSDictionary *prefs=[self prefs];
    return [NSString stringWithFormat:@"%@|%@|%@|%d",state[@"status"] ?: @"",state[@"vpnName"] ?: @"",prefs[@"mode"] ?: @"",[prefs[@"enabled"] boolValue]];
}
- (void)fetchIP {
    _ipRoute=[self ipRoute];
    _ipLoading=YES;
    NSUInteger token=++_ipToken;
    NSString *service=ASVIPService([self prefs]);
    [self refreshStatus];
    // Routes settle a moment after a VPN change.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(1.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{
        [self fetchIPFrom:service token:token fallback:[service isEqual:ASV_DEFAULT_IP_SERVICE]?ASV_FALLBACK_IP_SERVICE:nil];
    });
}
- (void)fetchIPFrom:(NSString *)service token:(NSUInteger)token fallback:(NSString *)fallback {
    if (token!=_ipToken) return;
    NSURLSessionConfiguration *configuration=[NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest=8;configuration.timeoutIntervalForResource=10;
    configuration.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration];
    __weak ASVRootController *weakSelf=self;
    [[session dataTaskWithURL:[NSURL URLWithString:service] completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSInteger code=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
        NSArray *parsed=(!error && code<400)?ASVParseIP(data):nil;
        dispatch_async(dispatch_get_main_queue(),^{
            ASVRootController *controller=weakSelf;
            if (!controller || token!=controller->_ipToken) return;
            if (!parsed && fallback) { [controller fetchIPFrom:fallback token:token fallback:nil];return; }
            controller->_ipLoading=NO;
            controller->_ip=parsed;
            [controller refreshStatus];
        });
    }] resume];
    [session finishTasksAndInvalidate];
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [self prefs][[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (![@[@"enabled",@"mode",@"language",@"badgeColor",ASV_VPN,ASV_DIRECT] containsObject:key]) return;
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
    BOOL applied=[@[@"active",@"partial"] containsObject:code];
    NSUInteger vpnApps=[self countFor:ASV_VPN], directApps=[self countFor:ASV_DIRECT];
    NSMutableAttributedString *text=[NSMutableAttributedString new];
    UIColor *green=UIColor.systemGreenColor, *red=UIColor.systemRedColor, *gray=UIColor.systemGrayColor;
    void (^line)(NSString *,NSString *,UIColor *)=^(NSString *label,NSString *value,UIColor *color){ ASVTerminalLine(text,label,value,color,15); };
    line(L(@"Tweak:",@"Твик:"),enabled?L(@"enabled",@"включён"):L(@"disabled",@"выключен"),enabled?green:red);
    BOOL down=[@[@"waitingVPN",@"unavailable",@"stopped"] containsObject:code];
    NSString *vpnState=[code isEqual:@"waitingVPN"]?L(@"not connected",@"не подключён"):([code isEqual:@"disabled"]?L(@"not used",@"не используется"):L(@"connected",@"подключён"));
    if ([code isEqual:@"unavailable"] || [code isEqual:@"stopped"]) vpnState=L(@"service stopped",@"служба не запущена");
    line(@"VPN:",vpnState,down?red:green);
    line(L(@"Mode:",@"Режим:"),tunnel?@"TUNNEL ONLY":@"BYPASS",tunnel?green:red);
    line(L(@"NECP rules:",@"Правил NECP:"),applied?([state[@"rules"] description] ?: @"0"):@"0",UIColor.whiteColor);
    line(L(@"VPN list:",@"Список VPN:"),[NSString stringWithFormat:@"%lu",(unsigned long)vpnApps],green);
    line(L(@"DIRECT list:",@"Список DIRECT:"),[NSString stringWithFormat:@"%lu",(unsigned long)directApps],red);
    NSString *ip=_ipLoading?@"…":(_ip.count?[NSString stringWithFormat:@"%@ %@",_ip[0],_ip.count>1?ASVFlag(_ip[1]):@""]:@"—");
    line(L(@"Public IP:",@"Белый IP:"),[ip stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet],_ip.count?UIColor.whiteColor:gray);
    if ([code isEqual:@"error"] || [code isEqual:@"unsupported"]) line(L(@"Error:",@"Ошибка:"),[state[@"error"] length]?state[@"error"]:code,red);
    return text;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items=[NSMutableArray array];
    NSMutableArray *headers=[NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[@"App Split VPN",L(@"Uses the active system VPN of any app. Its own settings and routes still apply.\n\nTUNNEL ONLY: only apps from the VPN list use the tunnel, all others go direct.\nBYPASS: apps from the DIRECT list go direct, all others use the VPN.\n\nExtra: disconnecting the VPN on the lock screen, Always ON VPN and Health Check Disconnect with their tuning. They work with any VPN and independently of the Enable switch.",@"Работает с активным системным VPN любого приложения. Его собственные настройки и маршруты сохраняются.\n\nTUNNEL ONLY: через туннель идут только приложения из списка VPN, остальные — напрямую.\nBYPASS: приложения из списка DIRECT идут напрямую, остальные — через VPN.\n\nДополнительно: отключение VPN на экране блокировки, Always ON VPN и Health Check Disconnect с настройкой параметров. Работают с любым VPN и независимо от переключателя «Включить».")]];
    [items addObject:[self setting:L(@"Enable",@"Включить") key:@"enabled" type:PSSwitchCell fallback:@NO detail:nil]];
    PSSpecifier *mode=[self setting:L(@"Mode",@"Режим") key:@"mode" type:PSLinkListCell fallback:@"bypass" detail:ASVModeListController.class];
    if ([mode respondsToSelector:@selector(setValues:titles:)]) [mode setValues:@[@"tunnelOnly",@"bypass"] titles:@[@"TUNNEL ONLY",@"BYPASS"]];
    else [mode setProperty:@NO forKey:@"enabled"];
    [mode setProperty:@YES forKey:@"asvMode"];
    [items addObject:mode];
    [items addObject:[self setting:L(@"Colored VPN½ badge",@"Цветной значок VPN½") key:@"badgeColor" type:PSSwitchCell fallback:@YES detail:nil]];
    PSSpecifier *language=[self setting:L(@"Language",@"Язык") key:@"language" type:PSLinkListCell fallback:@"system" detail:NSClassFromString(@"PSListItemsController")];
    if ([language respondsToSelector:@selector(setValues:titles:)]) [language setValues:@[@"system",@"ru",@"en"] titles:@[L(@"System (RU/EN)",@"Системный (RU/EN)"),@"Русский",@"English"]];
    [items addObject:language];
    PSSpecifier *extra=[self button:L(@"Extra",@"Дополнительно") action:@selector(openExtra)];
    [extra setProperty:[NSString stringWithFormat:@"%lu/3",(unsigned long)[ASVExtraController enabledCount]] forKey:@"asvCount"];
    [extra setProperty:@"plain" forKey:@"asvColor"];[items addObject:extra];

    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"App lists",@"Списки приложений"),L(@"The two lists are independent; only the list of the current mode is applied.\n\nAfter changing the rules, reopen the affected apps: already open connections keep their old route.\n\nImport skips apps that are not installed and keeps them in the list for a later reinstall.",@"Списки независимы: применяется только список текущего режима.\n\nПосле изменения правил переоткройте нужные приложения — уже открытые соединения сохраняют прежний маршрут.\n\nПри импорте отсутствующие приложения пропускаются и остаются в списке до установки.")]];
    NSUInteger total=[ASVAppListController installedApplicationCount];
    PSSpecifier *vpn=[self button:@"VPN" action:@selector(openVPNList)];
    [vpn setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_VPN],(unsigned long)total] forKey:@"asvCount"];
    [vpn setProperty:@"green" forKey:@"asvColor"];[items addObject:vpn];
    PSSpecifier *direct=[self button:@"DIRECT" action:@selector(openDirectList)];
    [direct setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_DIRECT],(unsigned long)total] forKey:@"asvCount"];
    [direct setProperty:@"red" forKey:@"asvColor"];[items addObject:direct];
    // A static-text Preferences cell does not reliably forward touches to child controls.
    PSSpecifier *transfer=[PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [transfer setProperty:@YES forKey:@"asvTransfer"];[items addObject:transfer];

    NSString *code=nil;
    _statusText=[self buildStatus:&code];
    _statusFingerprint=[self statusFingerprint];
    BOOL healthy=[@[@"active",@"partial"] containsObject:code];

    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    NSString *vpnName=state[@"vpnName"];
    BOOL vpnUp=![@[@"waitingVPN",@"unavailable",@"stopped"] containsObject:code];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"Active VPN",@"Активный VPN"),L(@"The name is shown when exactly one VPN configuration is enabled in the system; otherwise the active one cannot be identified reliably.",@"Название показывается, если в системе включена ровно одна конфигурация VPN; иначе активную нельзя надёжно определить.")]];
    NSString *activeName=vpnUp?(vpnName.length?vpnName:L(@"Connected",@"Подключён")):L(@"Not connected",@"Не подключён");
    PSSpecifier *active=[PSSpecifier preferenceSpecifierNamed:activeName target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [active setProperty:vpnUp?@"green":@"gray" forKey:@"asvDot"];[items addObject:active];

    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[[NSString stringWithFormat:@"%@ %@",healthy?@"🟢":@"🔴",L(@"Status",@"Статус")],L(@"NECP rules: one system rule per executable, i.e. the app itself plus each of its extensions (widgets, share, notifications, keyboards). That is why there are more rules than apps. Offloaded and deleted apps get no rule until they are installed again.\n\nPublic IP: the address and country with which the Settings app reaches the Internet, so with BYPASS it is usually the VPN address and with TUNNEL ONLY the direct one. It is checked when this page opens and when the VPN or mode changes; the service is set in Extra → Tuning.\n\nThe routing log shows the current route of every app in the active list and updates automatically.",@"Правил NECP: одно системное правило на каждый исполняемый файл — само приложение плюс каждое его расширение (виджеты, «Поделиться», уведомления, клавиатуры). Поэтому правил больше, чем приложений. Выгруженные и удалённые приложения не получают правил до повторной установки.\n\nБелый IP — адрес и страна, с которыми выходит в интернет приложение «Настройки»: при BYPASS это обычно адрес VPN, при TUNNEL ONLY — прямой. Проверяется при открытии страницы и при смене VPN или режима; сервис задаётся в «Дополнительно → Тюнинг».\n\nЖурнал маршрутизации показывает текущий маршрут каждого приложения из активного списка и обновляется автоматически.")]];
    PSSpecifier *terminal=[PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [terminal setProperty:@YES forKey:@"asvTerminal"];[items addObject:terminal];
    [items addObject:[self button:L(@"Refresh status",@"Обновить статус") action:@selector(fetchIP)]];
    [items addObject:[self button:L(@"Routing log",@"Журнал маршрутизации") action:@selector(openRouteLog)]];
    _headers=[headers copy];
    _specifiers=[items copy];return _specifiers;
}
- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    return section<(NSInteger)_headers.count ? ASVHeaderView(_headers[section][0],section,self,@selector(showInfo:)) : nil;
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
- (CGFloat)terminalHeight { return ASVTerminalHeight(_statusText,self.view.bounds.size.width); }
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
    if ([specifier propertyForKey:@"asvMode"]) {
        UIColor *tint=ASVModeColor([self prefs][@"mode"] ?: @"bypass");
        if (tint) cell.detailTextLabel.textColor=tint;
    } else if (color) {
        BOOL plain=[color isEqual:@"plain"];
        UIColor *tint=plain?UIColor.labelColor:([color isEqual:@"green"]?UIColor.systemGreenColor:UIColor.systemRedColor);
        cell.textLabel.textColor=tint;
        UILabel *count=[UILabel new];count.text=[specifier propertyForKey:@"asvCount"];count.textColor=plain?UIColor.secondaryLabelColor:tint;
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
        cell.userInteractionEnabled=YES;cell.contentView.userInteractionEnabled=YES;
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
        ASVFillTerminal(cell,_statusText,0x5A5);
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
- (void)openExtra { [self.navigationController pushViewController:[ASVExtraController new] animated:YES]; }
- (void)openRouteLog { [self.navigationController pushViewController:[ASVLogController new] animated:YES]; }
- (void)exportLists {
    NSDictionary *prefs=[self prefs];
    NSDictionary *payload=@{@"format":@"appsplitvpn-lists-v1",ASV_VPN:prefs[ASV_VPN] ?: @[],ASV_DIRECT:prefs[ASV_DIRECT] ?: @[]};
    NSError *error=nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    NSURL *url=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"AppSplitVPN-lists.json"];
    if (!data || ![data writeToURL:url options:NSDataWritingAtomic error:&error]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:L(@"Export failed",@"Не удалось экспортировать") message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];return;
    }
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
    [super viewWillAppear:animated];[self fetchIP];
    [_statusTimer invalidate];
    _statusTimer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(updateStatusIfChanged) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [_statusTimer invalidate];_statusTimer=nil;[super viewWillDisappear:animated]; }
- (void)dealloc { [_statusTimer invalidate]; }
@end

