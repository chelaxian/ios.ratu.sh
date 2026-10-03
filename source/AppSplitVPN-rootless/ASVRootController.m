#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <arpa/inet.h>
#import <objc/message.h>
#import "ASVUI.h"
#import "ASVAppListController.h"
#import "ASVExtraController.h"
#import "ASVSettingsTransfer.h"
@interface ASVExtraController (ASVImportValidation)
- (NSString *)problemWith:(NSString *)text key:(NSString *)key;
@end
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
    if ([text isEqual:@"MULTI VPN"] || [text isEqual:@"multiVPN"]) return UIColor.systemBlueColor;
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

// Icon of the app that owns the VPN profile. The service reports the configuration's
// application or its tunnel-provider extension; an extension resolves to its containing app.
@interface UIImage (ASVRootIcons)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end
static id ASVCall(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return object && [object respondsToSelector:selector] ? ((id(*)(id,SEL))objc_msgSend)(object,selector) : nil;
}
static BOOL ASVInstalledApp(NSString *identifier) {
    Class cls=NSClassFromString(@"LSApplicationProxy");
    SEL make=NSSelectorFromString(@"applicationProxyForIdentifier:");
    if (!identifier.length || ![cls respondsToSelector:make]) return NO;
    id proxy=((id(*)(id,SEL,id))objc_msgSend)(cls,make,identifier);
    id appState=ASVCall(proxy,@"appState");
    SEL installed=NSSelectorFromString(@"isInstalled");
    if (appState && [appState respondsToSelector:installed]) return ((BOOL(*)(id,SEL))objc_msgSend)(appState,installed);
    return ASVCall(proxy,@"bundleURL")!=nil;
}
static NSString *ASVOwnerApp(NSString *identifier) {
    if (!identifier.length) return nil;
    Class plugin=NSClassFromString(@"LSPlugInKitProxy");
    SEL make=NSSelectorFromString(@"pluginKitProxyForIdentifier:");
    if ([plugin respondsToSelector:make]) {
        id proxy=((id(*)(id,SEL,id))objc_msgSend)(plugin,make,identifier);
        NSString *owner=ASVCall(ASVCall(proxy,@"containingBundle"),@"bundleIdentifier");
        if ([owner isKindOfClass:NSString.class] && ASVInstalledApp(owner)) return owner;
    }
    NSMutableArray *parts=[[identifier componentsSeparatedByString:@"."] mutableCopy];
    while (parts.count>=2) {
        NSString *candidate=[parts componentsJoinedByString:@"."];
        if (ASVInstalledApp(candidate)) return candidate;
        [parts removeLastObject];
    }
    return nil;
}
static UIImage *ASVVPNIcon(NSString *identifier) {
    static NSMutableDictionary *cache;
    if (!cache) cache=[NSMutableDictionary dictionary];
    if (!identifier.length) return nil;
    id cached=cache[identifier];
    if (cached) return [cached isKindOfClass:UIImage.class] ? cached : nil;
    NSString *app=ASVOwnerApp(identifier);
    UIImage *icon=nil;
    if (app && [UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        icon=[UIImage _applicationIconImageForBundleIdentifier:app format:0 scale:UIScreen.mainScreen.scale];
    if (icon) {
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29,29)];
        icon=[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context){
            [[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,29,29) cornerRadius:6.5] addClip];
            [icon drawInRect:CGRectMake(0,0,29,29)];
        }];
    }
    cache[identifier]=icon ?: (id)NSNull.null;
    return icon;
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
    NSURLSession *_ipSession;
    NSString *_ipRoute;           // VPN/mode state the IP was measured for
}
@end
@implementation ASVRootController
- (NSString *)language { return [L(@"en",@"ru") isEqual:@"ru"] ? @"ru":@"en"; }
- (NSDictionary *)prefs { return [NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{}; }
- (NSUInteger)countFor:(NSString *)key {
    id items=[self prefs][key];
    return [items isKindOfClass:NSArray.class] || [items isKindOfClass:NSDictionary.class]?[items count]:0;
}
- (NSString *)statusFingerprint {
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    BOOL stale=[NSDate date].timeIntervalSince1970-[state[@"updated"] doubleValue]>90;
    NSDictionary *prefs=[self prefs];
    // Include the switch and mode so a change made from Control Center shows up here too.
    NSDictionary *extra=[NSDictionary dictionaryWithContentsOfFile:ASV_EXTRA_STATE];
    return [NSString stringWithFormat:@"%@|%@|%@|%@|%@|%@|%d|%d|%@|%@|%@|%d|%lu|%@",state[@"status"] ?: @"",state[@"error"] ?: @"",
        state[@"rules"] ?: @0,state[@"unresolved"] ?: @[],state[@"vpnName"] ?: @"",state[@"mode"] ?: @"",stale,
        [prefs[@"enabled"] boolValue],prefs[@"mode"] ?: @"",extra[@"vpnName"] ?: @"",extra[@"vpnApp"] ?: @"",[extra[@"vpnActive"] boolValue],(unsigned long)[ASVExtraController enabledCount],state[@"activeProfiles"] ?: @[]];
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
    [_ipSession invalidateAndCancel];_ipSession=nil;
    if(![[self prefs][@"enabled"] boolValue]){++_ipToken;_ipLoading=NO;_ip=nil;[self refreshStatus];return;}
    if(ASVIsMultiMode([self prefs])){++_ipToken;_ipLoading=NO;_ip=nil;notify_post(ASV_IP_REFRESH_NOTIFY);[self refreshStatus];return;}
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
    if (token!=_ipToken || ![[self prefs][@"enabled"] boolValue]) return;
    NSURLSessionConfiguration *configuration=[NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.timeoutIntervalForRequest=8;configuration.timeoutIntervalForResource=10;
    configuration.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;
    NSURLSession *session=[NSURLSession sessionWithConfiguration:configuration];
    _ipSession=session;
    __weak ASVRootController *weakSelf=self;
    [[session dataTaskWithURL:[NSURL URLWithString:service] completionHandler:^(NSData *data,NSURLResponse *response,NSError *error){
        NSInteger code=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse *)response).statusCode:0;
        NSArray *parsed=(!error && code<400)?ASVParseIP(data):nil;
        dispatch_async(dispatch_get_main_queue(),^{
            ASVRootController *controller=weakSelf;
            if (!controller || token!=controller->_ipToken || ![[controller prefs][@"enabled"] boolValue]) return;
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
    BOOL multi=[prefs[@"mode"] isEqual:@"multiVPN"];
    BOOL applied=[@[@"active",@"partial"] containsObject:code];
    NSUInteger vpnApps=[self countFor:ASV_VPN], directApps=[self countFor:ASV_DIRECT];
    NSMutableAttributedString *text=[NSMutableAttributedString new];
    UIColor *green=UIColor.systemGreenColor, *red=UIColor.systemRedColor, *gray=UIColor.systemGrayColor;
    void (^line)(NSString *,NSString *,UIColor *)=^(NSString *label,NSString *value,UIColor *color){ ASVTerminalLine(text,label,value,color,15); };
    line(L(@"Tweak:",@"Твик:"),enabled?L(@"enabled",@"включён"):L(@"disabled",@"выключен"),enabled?green:red);
    BOOL down=[@[@"waitingVPN",@"unavailable",@"stopped"] containsObject:code];
    NSString *vpnState=[code isEqual:@"waitingVPN"]?L(@"not connected",@"не подключён"):L(@"connected",@"подключён");
    if(!enabled){BOOL active=[[NSDictionary dictionaryWithContentsOfFile:ASV_EXTRA_STATE][@"vpnActive"] boolValue];down=!active;vpnState=active?L(@"connected",@"подключён"):L(@"not connected",@"не подключён");}
    if ([code isEqual:@"unavailable"] || [code isEqual:@"stopped"]) vpnState=L(@"service stopped",@"служба не запущена");
    if ([code isEqual:@"connecting"]) {vpnState=L(@"connecting",@"подключается");down=YES;}
    if ([code isEqual:@"recovering"]) {vpnState=L(@"restoring profiles",@"восстановление профилей");down=YES;}
    if ([code isEqual:@"error"] || [code isEqual:@"unsupported"]) {vpnState=L(@"error",@"ошибка");down=YES;}
    line(@"VPN:",vpnState,down?red:green);
    line(L(@"Mode:",@"Режим:"),multi?@"MULTI VPN":(tunnel?@"TUNNEL ONLY":@"BYPASS"),multi?UIColor.systemBlueColor:(tunnel?green:red));
    line(L(@"NECP rules:",@"Правил NECP:"),applied?([state[@"rules"] description] ?: @"0"):@"0",UIColor.whiteColor);
    if(tunnel)line(L(@"VPN list:",@"Список VPN:"),[NSString stringWithFormat:@"%lu",(unsigned long)vpnApps],green);
    if(!tunnel && !multi)line(L(@"DIRECT list:",@"Список DIRECT:"),[NSString stringWithFormat:@"%lu",(unsigned long)directApps],red);
    if(multi)line(@"VPN MATRIX:",[NSString stringWithFormat:@"%lu",(unsigned long)[self countFor:ASV_MATRIX]],UIColor.systemBlueColor);
    NSString *ip=_ipLoading?@"…":(_ip.count?[NSString stringWithFormat:@"%@ %@",_ip[0],_ip.count>1?ASVFlag(_ip[1]):@""]:@"—");
    if(multi){
        NSArray *profiles=[state[@"activeProfiles"] isKindOfClass:NSArray.class]?state[@"activeProfiles"]:@[];
        line(L(@"Active VPNs:",@"Активных VPN:"),[NSString stringWithFormat:@"%lu",(unsigned long)profiles.count],UIColor.systemBlueColor);
        NSUInteger profileNumber=0;
        for(NSDictionary *profile in profiles){
            NSArray *address=[profile[@"publicIP"] isKindOfClass:NSArray.class]?profile[@"publicIP"]:@[];
            NSString *value=address.count?[NSString stringWithFormat:@"%@ %@",address[0],address.count>1?ASVFlag(address[1]):@""]:([profile[@"ipPending"] boolValue]?@"…":L(@"unavailable",@"недоступен"));
            line([NSString stringWithFormat:L(@"Public IP %lu:",@"Белый IP %lu:"),(unsigned long)++profileNumber],value,address.count?UIColor.whiteColor:gray);
        }
    }else line(L(@"Public IP:",@"Белый IP:"),[ip stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet],_ip.count?UIColor.whiteColor:gray);
    if ([code isEqual:@"error"] || [code isEqual:@"unsupported"]) line(L(@"Error:",@"Ошибка:"),[state[@"error"] length]?state[@"error"]:code,red);
    return text;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *items=[NSMutableArray array];
    NSMutableArray *headers=[NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
[headers addObject:@[@"App Split VPN",L(@"Uses the active system VPN of any app. Its own settings and routes still apply.\n\nTUNNEL ONLY: only apps from the VPN list use the tunnel, all others go direct.\nBYPASS: apps from the DIRECT list go direct, all others use the VPN.\n\nExtra: disconnecting the VPN on the lock screen, Always ON VPN and Health Check VPN Disconnect with their tuning, and the event log. Enable and the CC toggle globally stop all routing, VPN automation and checks. Saved options remain for the next activation.",@"Работает с активным системным VPN любого приложения. Его собственные настройки и маршруты сохраняются.\n\nTUNNEL ONLY: через туннель идут только приложения из списка VPN, остальные — напрямую.\nBYPASS: приложения из списка DIRECT идут напрямую, остальные — через VPN.\n\nДополнительно: отключение VPN на экране блокировки, «Всегда включать VPN» и «Отключать VPN по Health Check» с настройкой параметров, журнал событий. «Включить» и кнопка CC глобально останавливают маршрутизацию, всю автоматику VPN и проверки. Настройки сохраняются до следующего включения.")]];
    [items addObject:[self setting:L(@"Enable",@"Включить") key:@"enabled" type:PSSwitchCell fallback:@NO detail:nil]];
    PSSpecifier *mode=[self setting:L(@"Mode",@"Режим") key:@"mode" type:PSLinkListCell fallback:@"bypass" detail:ASVModeListController.class];
    if ([mode respondsToSelector:@selector(setValues:titles:)]) [mode setValues:@[@"tunnelOnly",@"bypass",@"multiVPN"] titles:@[@"TUNNEL ONLY",@"BYPASS",@"MULTI VPN"]];
    else [mode setProperty:@NO forKey:@"enabled"];
    [mode setProperty:@YES forKey:@"asvMode"];
    [items addObject:mode];
    [items addObject:[self setting:L(@"Colored VPN badge",@"Цветной значок VPN") key:@"badgeColor" type:PSSwitchCell fallback:@YES detail:nil]];
    PSSpecifier *language=[self setting:L(@"Language",@"Язык") key:@"language" type:PSLinkListCell fallback:@"system" detail:NSClassFromString(@"PSListItemsController")];
    if ([language respondsToSelector:@selector(setValues:titles:)]) [language setValues:@[@"system",@"ru",@"en"] titles:@[L(@"System (RU/EN)",@"Системный (RU/EN)"),@"Русский",@"English"]];
    [items addObject:language];
    if(ASVIsMultiMode([self prefs])) {
        headers[0]=@[headers[0][0],L(@"MULTI VPN assigns each app to a profile in VPN MATRIX. Unassigned apps use DIRECT. Assigned apps are blocked while their VPN is unavailable. Experimental: ordinary PacketTunnel profiles only; use different VPN providers. Switching off or leaving MULTI restores the original profiles. Extra controls are hidden and inactive in this mode.",@"MULTI VPN назначает каждому приложению профиль из VPN MATRIX. Остальные идут DIRECT. Пока назначенный VPN недоступен, трафик приложения блокируется. Эксперимент: только обычные профили PacketTunnel; выбирайте разные VPN-приложения. При выключении или выходе из MULTI исходные профили восстанавливаются. Дополнительные опции в этом режиме скрыты и не действуют.")];
    }
    if(!ASVIsMultiMode([self prefs]))headers[0]=@[headers[0][0],[headers[0][1] stringByAppendingString:L(@"\n\nExtra → Tuning → Keep VPN for PiP / music on LS: optionally prevents lock-screen disconnection while system media playback is active. It is available only with Disconnect VPN on LS enabled and is off by default.",@"\n\nДополнительно → Тюнинг → PiP / музыка не отключают VPN на LS: по желанию сохраняет VPN при активном системном воспроизведении. Доступно только при включённом отключении VPN на LS; по умолчанию выключено.")]];
    PSSpecifier *extra=[self button:L(@"Extra",@"Дополнительно") action:@selector(openExtra)];
    [extra setProperty:[NSString stringWithFormat:@"%lu/4",(unsigned long)[ASVExtraController enabledCount]] forKey:@"asvCount"];
    [extra setProperty:@"plain" forKey:@"asvColor"];
    // These controls operate on one selected system VPN, not a matrix of sessions.
    if(!ASVIsMultiMode([self prefs]))[items addObject:extra];

    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"App lists",@"Списки приложений"),L(@"The two lists are independent; only the list of the current mode is applied.\n\nAfter changing the rules, reopen the affected apps: already open connections keep their old route.\n\nImport skips missing apps and VPN profiles and applies the remaining settings.",@"Списки независимы: применяется только список текущего режима.\n\nПосле изменения правил переоткройте нужные приложения — уже открытые соединения сохраняют прежний маршрут.\n\nПри импорте отсутствующие приложения и VPN-профили пропускаются, остальные настройки применяются.")]];
    NSUInteger total=[ASVAppListController installedApplicationCount];
    PSSpecifier *vpn=[self button:@"VPN" action:@selector(openVPNList)];
    [vpn setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_VPN],(unsigned long)total] forKey:@"asvCount"];
    [vpn setProperty:@"green" forKey:@"asvColor"];if([[self prefs][@"mode"] isEqual:@"tunnelOnly"])[items addObject:vpn];
    PSSpecifier *direct=[self button:@"DIRECT" action:@selector(openDirectList)];
    [direct setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_DIRECT],(unsigned long)total] forKey:@"asvCount"];
    [direct setProperty:@"red" forKey:@"asvColor"];if(![[self prefs][@"mode"] isEqual:@"tunnelOnly"] && ![[self prefs][@"mode"] isEqual:@"multiVPN"])[items addObject:direct];
    if([[self prefs][@"mode"] isEqual:@"multiVPN"]) {
        PSSpecifier *matrix=[self button:@"VPN MATRIX" action:@selector(openMatrix)];[matrix setProperty:@"blue" forKey:@"asvColor"];
        [matrix setProperty:[NSString stringWithFormat:@"%lu/%lu",(unsigned long)[self countFor:ASV_MATRIX],(unsigned long)total] forKey:@"asvCount"];[items addObject:matrix];
    }
    // A static-text Preferences cell does not reliably forward touches to child controls.
    PSSpecifier *transfer=[PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [transfer setProperty:@YES forKey:@"asvTransfer"];

    NSString *code=nil;
    _statusText=[self buildStatus:&code];
    _statusFingerprint=[self statusFingerprint];
    BOOL healthy=[@[@"active",@"partial"] containsObject:code];

    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    NSDictionary *extraState=[NSDictionary dictionaryWithContentsOfFile:ASV_EXTRA_STATE];
    // The supervisor tracks the profile selected in iOS; fall back to the split service's view.
    BOOL extraFresh=!ASVIsMultiMode([self prefs]) && extraState && [NSDate date].timeIntervalSince1970-[extraState[@"updated"] doubleValue]<3600;
    NSString *vpnName=extraFresh && [extraState[@"vpnName"] length]?extraState[@"vpnName"]:state[@"vpnName"];
    BOOL vpnUp=extraFresh?[extraState[@"vpnActive"] boolValue]:![@[@"waitingVPN",@"unavailable",@"stopped"] containsObject:code];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"Active VPN",@"Активный VPN"),L(@"The VPN profile selected in iOS Settings and the icon of the app it belongs to. Built-in iOS VPN profiles (IKEv2, IPsec) have no app and show a shield.",@"Профиль VPN, выбранный в настройках iOS, и иконка приложения, которому он принадлежит. У встроенных профилей iOS (IKEv2, IPsec) приложения нет — для них показывается щит.")]];
    if(ASVIsMultiMode([self prefs]))headers[headers.count-1]=@[headers.lastObject[0],L(@"All connected MULTI profiles, with the icon of each VPN app. The badge VPN:N counts connected profiles, not assigned apps.",@"Все подключённые профили MULTI с иконками их VPN-приложений. Значок VPN:N считает подключённые профили, не назначенные приложения.")];
    NSArray *activeProfiles=ASVIsMultiMode([self prefs]) && [state[@"activeProfiles"] isKindOfClass:NSArray.class]?state[@"activeProfiles"]:@[];
    if(ASVIsMultiMode([self prefs])){
        NSUInteger profileNumber=0;
        for(NSDictionary *profile in activeProfiles){
            NSString *name=[NSString stringWithFormat:@"%lu. %@",(unsigned long)++profileNumber,profile[@"name"] ?: @"VPN"];
            PSSpecifier *active=[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
            [active setProperty:@"green" forKey:@"asvDot"];[active setProperty:profile[@"owner"] forKey:@"asvApp"];[items addObject:active];
        }
        if(!activeProfiles.count)[items addObject:[PSSpecifier preferenceSpecifierNamed:L(@"Not connected",@"Не подключён") target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil]];
    }else{
    NSString *activeName=vpnUp?(vpnName.length?vpnName:L(@"Connected",@"Подключён")):L(@"Not connected",@"Не подключён");
    PSSpecifier *active=[PSSpecifier preferenceSpecifierNamed:activeName target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [active setProperty:vpnUp?@"green":@"gray" forKey:@"asvDot"];
    if ([extraState[@"vpnApp"] length]) [active setProperty:extraState[@"vpnApp"] forKey:@"asvApp"];
    [items addObject:active];
    }

    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[[NSString stringWithFormat:@"%@ %@",healthy?@"🟢":@"🔴",L(@"Status",@"Статус")],L(@"NECP rules: one system rule per executable, i.e. the app itself plus each of its extensions (widgets, share, notifications, keyboards). That is why there are more rules than apps. Offloaded and deleted apps get no rule until they are installed again.\n\nPublic IP: the address and country with which the Settings app reaches the Internet, so with BYPASS it is usually the VPN address and with TUNNEL ONLY the direct one. It is checked when this page opens and when the VPN or mode changes; the service is set in Extra → Tuning.\n\nThe routing log shows the current route of every app in the active list and updates automatically.",@"Правил NECP: одно системное правило на каждый исполняемый файл — само приложение плюс каждое его расширение (виджеты, «Поделиться», уведомления, клавиатуры). Поэтому правил больше, чем приложений. Выгруженные и удалённые приложения не получают правил до повторной установки.\n\nБелый IP — адрес и страна, с которыми выходит в интернет приложение «Настройки»: при BYPASS это обычно адрес VPN, при TUNNEL ONLY — прямой. Проверяется при открытии страницы и при смене VPN или режима; сервис задаётся в «Дополнительно → Тюнинг».\n\nЖурнал маршрутизации показывает текущий маршрут каждого приложения из активного списка и обновляется автоматически.")]];
    PSSpecifier *terminal=[PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [terminal setProperty:@YES forKey:@"asvTerminal"];[items addObject:terminal];
    if(ASVIsMultiMode([self prefs]))headers[headers.count-1]=@[headers.lastObject[0],L(@"NECP rules count executable identities, including app extensions.\n\nMULTI public IP is checked separately through each connected profile using an assigned app's native routing policy. The connection's local address must match that profile's tunnel; otherwise it is shown as unavailable. Checks run on connection, page opening and Refresh status, not continuously. The default service has a numeric Cloudflare fallback if DNS is unavailable.",@"Правила NECP считают исполняемые файлы, включая расширения приложений.\n\nВ MULTI белый IP проверяется отдельно через каждый подключённый профиль по штатным правилам назначенного приложения. Локальный адрес соединения должен соответствовать туннелю профиля; иначе показывается «недоступен». Проверки выполняются при подключении, открытии страницы и нажатии «Обновить статус», не постоянно. Для стандартного сервиса есть резервный числовой адрес Cloudflare, если DNS недоступен.")];
    [items addObject:[self button:L(@"Refresh status",@"Обновить статус") action:@selector(fetchIP)]];
    [items addObject:[self button:L(@"Routing log",@"Журнал маршрутизации") action:@selector(openRouteLog)]];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"Settings backup",@"Перенос настроек"),L(@"Export/import includes all tweak settings, app lists, VPN MATRIX, primary VPN and ordered reserves. Missing apps and profiles are skipped. Only profile identifiers and display metadata are included; VPN keys and credentials stay in their VPN apps.",@"Экспорт/импорт включает все настройки твика, списки приложений, VPN MATRIX, основной VPN и порядок резервов. Отсутствующие приложения и профили пропускаются. Сохраняются только идентификаторы и названия профилей; ключи и конфигурации остаются в VPN-приложениях.")]];
    [items addObject:transfer];
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
        UIColor *tint=plain?UIColor.labelColor:([color isEqual:@"blue"]?UIColor.systemBlueColor:([color isEqual:@"green"]?UIColor.systemGreenColor:UIColor.systemRedColor));
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
        UIImage *icon=ASVVPNIcon([specifier propertyForKey:@"asvApp"]);
        cell.imageView.image=icon ?: [UIImage systemImageNamed:up?@"lock.shield.fill":@"shield.slash"];
        cell.imageView.tintColor=up?UIColor.systemGreenColor:UIColor.secondaryLabelColor;
        cell.imageView.alpha=(icon && !up)?0.45:1;
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
- (void)openMatrix { [self openList:ASV_MATRIX]; }
- (void)openExtra { [self.navigationController pushViewController:[ASVExtraController new] animated:YES]; }
- (void)openRouteLog { [self.navigationController pushViewController:[ASVLogController new] animated:YES]; }
- (void)exportLists {
    NSDictionary *prefs=[self prefs];
    NSDictionary *payload=ASVExportSettings(prefs,[NSArray arrayWithContentsOfFile:ASV_PROFILE_CATALOG] ?: @[]);
    NSError *error=nil;
    NSData *data=[NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:&error];
    NSURL *url=[[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:@"AppSplitVPN-settings.json"];
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
    NSURL *url=urls.firstObject;
    NSNumber *size=[[[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil] objectForKey:NSFileSize];
    NSData *data=size && size.unsignedLongLongValue<=2*1024*1024?[NSData dataWithContentsOfURL:url options:0 error:nil]:nil;
    id payload=data?[NSJSONSerialization JSONObjectWithData:data options:0 error:nil]:nil;
    NSMutableSet *apps=[NSMutableSet set];
    id workspace=((id(*)(id,SEL))objc_msgSend)(NSClassFromString(@"LSApplicationWorkspace"),@selector(defaultWorkspace));
    NSArray *proxies=((id(*)(id,SEL))objc_msgSend)(workspace,@selector(allInstalledApplications));
    for(id proxy in proxies) {
        if(![proxy respondsToSelector:@selector(applicationIdentifier)] || ![proxy respondsToSelector:@selector(bundleURL)])continue;
        NSString *app=((id(*)(id,SEL))objc_msgSend)(proxy,@selector(applicationIdentifier));
        NSURL *bundle=((id(*)(id,SEL))objc_msgSend)(proxy,@selector(bundleURL));
        if(![bundle isKindOfClass:NSURL.class])continue;
        NSString *executable=[NSBundle bundleWithURL:bundle].executablePath;
        if(app.length && executable.length && [[NSFileManager defaultManager] fileExistsAtPath:executable])[apps addObject:app];
    }
    NSArray *catalog=[NSArray arrayWithContentsOfFile:ASV_PROFILE_CATALOG] ?: @[];
    ASVExtraController *validator=[ASVExtraController new];NSUInteger skipped=0;
    NSMutableDictionary *prefs=ASVImportSettings(payload,[self prefs],apps,catalog,^BOOL(NSString *key,NSString *value){return [validator problemWith:value key:key]==nil;},&skipped);
    BOOL valid=prefs && [prefs writeToFile:ASV_PREFS atomically:YES];
    if(valid){notify_post(ASV_NOTIFY);[self fetchIP];[self refreshStatus];}
    NSString *message=valid?[NSString stringWithFormat:L(@"Settings applied. Unavailable or invalid items skipped: %lu. VPN profiles are matched by UUID or a unique app + profile name. VPN credentials are not imported.",@"Настройки применены. Пропущено недоступных или некорректных пунктов: %lu. VPN сопоставляются по UUID либо уникальному сочетанию приложения и имени профиля. Конфигурации и ключи VPN не импортируются."),(unsigned long)skipped]:nil;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:valid?L(@"Settings imported",@"Настройки импортированы"):L(@"Invalid settings file",@"Неверный файл настроек") message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];[self fetchIP];
    [_statusTimer invalidate];
    _statusTimer=[NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(updateStatusIfChanged) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [_statusTimer invalidate];_statusTimer=nil;[super viewWillDisappear:animated]; }
- (void)dealloc { [_statusTimer invalidate];[_ipSession invalidateAndCancel]; }
@end

