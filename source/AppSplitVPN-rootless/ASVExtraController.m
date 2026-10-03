#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListItemsController.h>
#import <notify.h>
#import "ASVUI.h"
#import "ASVExtraController.h"
#import "ASVProfileListController.h"
@interface PSSpecifier (ASVExtraValues)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end
@interface PSListController (ASVExtraIndexPath)
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

#pragma mark - Validation

static BOOL ASVDigits(NSString *text) {
    return text.length && text.length<=6 && [text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"0123456789"].invertedSet].location==NSNotFound;
}
static BOOL ASVIPv4(NSString *text) {
    NSArray *parts=[text componentsSeparatedByString:@"."];
    if (parts.count!=4) return NO;
    for (NSString *part in parts) if (!ASVDigits(part) || part.length>3 || part.integerValue>255) return NO;
    return YES;
}
// Fully qualified domain: at least two labels of letters, digits and inner hyphens; the last one is not numeric.
static BOOL ASVDomain(NSString *text) {
    if (!text.length || text.length>253) return NO;
    NSArray *labels=[text componentsSeparatedByString:@"."];
    if (labels.count<2) return NO;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"];
    for (NSString *label in labels) {
        if (!label.length || label.length>63 || [label hasPrefix:@"-"] || [label hasSuffix:@"-"]) return NO;
        if ([label rangeOfCharacterFromSet:allowed.invertedSet].location!=NSNotFound) return NO;
    }
    return !ASVDigits(labels.lastObject);
}
static BOOL ASVHostOK(NSString *text) { return ASVIPv4(text) || ASVDomain(text); }
static BOOL ASVServiceOK(NSString *text) {
    if ([text rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location!=NSNotFound) return NO;
    NSString *lower=text.lowercaseString;
    if (![lower hasPrefix:@"https://"] && ![lower hasPrefix:@"http://"]) return NO;
    NSURLComponents *url=[NSURLComponents componentsWithString:text];
    if (!url || url.user || url.password || !ASVHostOK(url.host ?: @"")) return NO;
    return !url.port || (url.port.integerValue>=1 && url.port.integerValue<=65535);
}

#pragma mark - Event journal

static NSString *ASVEventText(NSDictionary *event,UIColor **color) {
    NSString *code=event[@"code"], *detail=[event[@"detail"] isKindOfClass:NSString.class]?event[@"detail"]:@"";
    UIColor *tint=UIColor.whiteColor;
    NSString *text=code;
    if ([code isEqual:@"lsStop"]) { text=L(@"Lock screen: VPN disconnected",@"Блокировка: VPN отключён");tint=UIColor.systemOrangeColor; }
    else if ([code isEqual:@"lsStart"]) { text=L(@"Unlock: VPN reconnected",@"Разблокировка: VPN подключён");tint=UIColor.systemGreenColor; }
    else if ([code isEqual:@"alwaysOn"]) { text=L(@"Always ON: reconnecting",@"Всегда включать VPN: переподключение");tint=UIColor.systemYellowColor; }
    else if ([code isEqual:@"healthStop"]) { text=[NSString stringWithFormat:@"%@ (%@)",L(@"Health Check: VPN disconnected",@"Health Check: VPN отключён"),detail];tint=UIColor.systemRedColor; }
    else if ([code isEqual:@"hcOK"]) { text=[NSString stringWithFormat:@"Health Check: OK %@ %@",detail,L(@"ms",@"мс")];tint=UIColor.systemGreenColor; }
    else if ([code isEqual:@"hcFail"]) { text=[NSString stringWithFormat:@"Health Check: %@ %@",L(@"fail",@"сбой"),detail];tint=UIColor.systemRedColor; }
    else if ([code isEqual:@"lock"]) { text=L(@"Screen locked",@"Экран заблокирован");tint=UIColor.systemGrayColor; }
    else if ([code isEqual:@"unlock"]) { text=L(@"Screen unlocked",@"Экран разблокирован");tint=UIColor.systemGrayColor; }
    else if ([code isEqual:@"lsMediaHold"]) { text=L(@"LS: VPN retained for media playback / unavailable playback state",@"LS: VPN сохранён для медиа / состояние воспроизведения недоступно");tint=UIColor.systemBlueColor; }
    else if ([code isEqual:@"lsMediaRelease"]) { text=L(@"LS: media stopped, disconnect delay started",@"LS: воспроизведение остановлено, начата задержка отключения");tint=UIColor.systemOrangeColor; }
    else if ([code isEqual:@"vpnUp"]) { text=[L(@"VPN connected",@"VPN подключён") stringByAppendingString:detail.length?[@": " stringByAppendingString:detail]:@""];tint=UIColor.systemGreenColor; }
    else if ([code isEqual:@"vpnDown"]) { text=[L(@"VPN disconnected",@"VPN отключён") stringByAppendingString:detail.length?[@": " stringByAppendingString:detail]:@""];tint=UIColor.systemRedColor; }
    else if ([code isEqual:@"reserveSwitch"]) { text=[L(@"Redundancy: switching to ",@"Резервирование: переключение на ") stringByAppendingString:detail];tint=UIColor.systemBlueColor; }
    else if ([code isEqual:@"circuitOpen"]) { text=[L(@"Automatic recovery stopped: ",@"Автовосстановление остановлено: ") stringByAppendingString:detail];tint=UIColor.systemRedColor; }
    else if ([code isEqual:@"badCycle"]) { text=[L(@"Cycle without a successful check: ",@"Цикл без успешной проверки: ") stringByAppendingString:detail];tint=UIColor.systemOrangeColor; }
    else if (detail.length) text=[NSString stringWithFormat:@"%@ %@",code,detail];
    if (color) *color=tint;
    return text;
}

@interface ASVEventLogController : UIViewController
@end
@implementation ASVEventLogController {
    UITextView *_textView;
    NSTimer *_timer;
    NSDate *_loaded;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor=UIColor.blackColor;
    self.title=L(@"Event log",@"Журнал событий");
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:L(@"Clear",@"Очистить") style:UIBarButtonItemStylePlain target:self action:@selector(clear)];
    _textView=[[UITextView alloc] initWithFrame:CGRectZero];_textView.editable=NO;
    _textView.backgroundColor=UIColor.blackColor;_textView.textContainerInset=UIEdgeInsetsMake(12,10,12,10);
    _textView.translatesAutoresizingMaskIntoConstraints=NO;[self.view addSubview:_textView];
    [NSLayoutConstraint activateConstraints:@[[_textView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],[_textView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],[_textView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],[_textView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]]];
    [self reload];
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_timer invalidate];
    _timer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(reloadIfChanged) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [_timer invalidate];_timer=nil;[super viewWillDisappear:animated]; }
- (void)dealloc { [_timer invalidate]; }
- (void)reloadIfChanged {
    NSDate *modified=[[NSFileManager defaultManager] attributesOfItemAtPath:ASV_EXTRA_LOG error:nil].fileModificationDate;
    if (![modified isEqualToDate:_loaded]) [self reload];
}
- (void)clear {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:L(@"Clear the event log?",@"Очистить журнал событий?") message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:L(@"Cancel",@"Отмена") style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:L(@"Clear",@"Очистить") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action){
        notify_post(ASV_EXTRA_CLEAR);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,(int64_t)(0.5*NSEC_PER_SEC)),dispatch_get_main_queue(),^{ [self reload]; });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)reload {
    _loaded=[[NSFileManager defaultManager] attributesOfItemAtPath:ASV_EXTRA_LOG error:nil].fileModificationDate;
    NSArray *events=[NSArray arrayWithContentsOfFile:ASV_EXTRA_LOG] ?: @[];
    NSDateFormatter *format=[NSDateFormatter new];format.dateFormat=@"dd.MM HH:mm:ss";
    NSMutableAttributedString *body=[NSMutableAttributedString new];
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        if (![event isKindOfClass:NSDictionary.class]) continue;
        UIColor *color=nil;
        NSString *text=ASVEventText(event,&color);
        NSString *time=[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[event[@"time"] doubleValue]]];
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:[time stringByAppendingString:@"  "] attributes:@{NSFontAttributeName:ASVMono(12),NSForegroundColorAttributeName:UIColor.systemGrayColor}]];
        [body appendAttributedString:[[NSAttributedString alloc] initWithString:[text stringByAppendingString:@"\n"] attributes:@{NSFontAttributeName:ASVMonoBold(12),NSForegroundColorAttributeName:color}]];
    }
    if (!body.length) [body appendAttributedString:[[NSAttributedString alloc] initWithString:L(@"No events yet",@"Событий пока нет") attributes:@{NSFontAttributeName:ASVMono(12),NSForegroundColorAttributeName:UIColor.systemGrayColor}]];
    _textView.attributedText=body;
}
@end

#pragma mark - Extra page

@implementation ASVExtraController {
    NSArray<NSArray<NSString *> *> *_headers;
    NSTimer *_timer;
    NSDate *_stateStamp;
    NSDate *_prefsStamp;
    NSAttributedString *_stateText;
    UIAlertAction *_okAction;
    UIAlertController *_editor;
    NSString *_editKey;
}
+ (NSUInteger)enabledCount {
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{};
    NSUInteger count=0;
    for (NSString *key in @[ASV_LS_DISCONNECT,ASV_ALWAYS_ON,ASV_HEALTH,ASV_REDUNDANCY]) if (ASVExtraOptionConfigured(prefs,key)) count++;
    return count;
}
- (NSDictionary *)prefs { return [NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{}; }
// Field key -> @[low, high] for whole numbers.
- (NSDictionary *)limits { return @{ASV_RED_CYCLES:@[@1,@10],ASV_LS_DELAY:@[@0,@600],ASV_HC_PORT:@[@1,@65535],ASV_HC_INTERVAL:@[@10,@3600],ASV_HC_FAILURES:@[@1,@10],ASV_HC_TIMEOUT:@[@1,@120]}; }
- (NSString *)fieldValue:(NSString *)key {
    NSDictionary *prefs=[self prefs];
    if ([key isEqual:ASV_RED_CYCLES]) return [@(ASVIntSetting(prefs,key,1,1,10)) stringValue];
    if ([key isEqual:ASV_LS_DELAY]) return [@(ASVIntSetting(prefs,key,ASV_DEFAULT_LS_DELAY,0,600)) stringValue];
    if ([key isEqual:ASV_HC_INTERVAL]) return [@(ASVIntSetting(prefs,key,ASV_DEFAULT_HC_INTERVAL,10,3600)) stringValue];
    if ([key isEqual:ASV_HC_FAILURES]) return [@(ASVIntSetting(prefs,key,ASV_DEFAULT_HC_FAILURES,1,10)) stringValue];
    if ([key isEqual:ASV_HC_PORT]) { NSInteger port=ASVIntSetting(prefs,key,0,0,65535);return port>0?[@(port) stringValue]:@""; }
    if ([key isEqual:ASV_HC_TARGET]) return ASVHealthTarget(prefs);
    if ([key isEqual:ASV_IP_SERVICE]) return ASVIPService(prefs);
    if ([key isEqual:ASV_HC_TIMEOUT]) return [@(ASVIntSetting(prefs,key,ASV_DEFAULT_HC_TIMEOUT,1,120)) stringValue];
    return @"";
}
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if ([specifier propertyForKey:@"asvField"]) {
        NSString *value=[self fieldValue:key];
        return value.length?value:L(@"auto",@"авто");
    }
    return [self prefs][key] ?: [specifier propertyForKey:@"default"];
}
- (void)complain:(NSString *)message {
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:message message:nil preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}
- (BOOL)save:(void (^)(NSMutableDictionary *prefs))change {
    NSMutableDictionary *prefs=[[self prefs] mutableCopy];
    change(prefs);
    if (![prefs writeToFile:ASV_PREFS atomically:YES]) { [self complain:L(@"Could not save",@"Не удалось сохранить")];return NO; }
    notify_post(ASV_NOTIFY);
    return YES;
}
// Switches and the check method; text values go through the editor window.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    BOOL toggle=[@[ASV_LS_DISCONNECT,ASV_ALWAYS_ON,ASV_HEALTH,ASV_REDUNDANCY,ASV_LS_MEDIA] containsObject:key];
    if (!toggle && ![key isEqual:ASV_HC_METHOD] && ![key isEqual:ASV_RED_ALGORITHM]) return;
    if(ASVIsMultiMode([self prefs]))return;
    if (![self save:^(NSMutableDictionary *prefs){
        prefs[key]=value;
        if([key isEqual:ASV_REDUNDANCY] && [value boolValue]){prefs[ASV_HEALTH]=@YES;prefs[ASV_ALWAYS_ON]=@YES;}
        if(( [key isEqual:ASV_HEALTH] || [key isEqual:ASV_ALWAYS_ON]) && ![value boolValue])prefs[ASV_REDUNDANCY]=@NO;
    }]) return;
    // Tuning rows depend on the switches and the method: rebuild the page.
    dispatch_async(dispatch_get_main_queue(),^{ [self reloadSpecifiers]; });
}

#pragma mark Editor

// nil = valid. An empty value is valid and restores the default (port: auto).
- (NSString *)problemWith:(NSString *)text key:(NSString *)key {
    if (!text.length) return nil;
    NSArray *range=[self limits][key];
    if (range) {
        if (!ASVDigits(text) || text.integerValue<[range[0] integerValue] || text.integerValue>[range[1] integerValue])
            return [NSString stringWithFormat:L(@"Whole number from %@ to %@",@"Целое число от %@ до %@"),range[0],range[1]];
        return nil;
    }
    if ([key isEqual:ASV_HC_TARGET]) return ASVHostOK(text)?nil:L(@"IPv4 address 0.0.0.0–255.255.255.255 or a domain such as example.com",@"IPv4-адрес 0.0.0.0–255.255.255.255 или домен вида example.com");
    if ([key isEqual:ASV_IP_SERVICE]) return ASVServiceOK(text)?nil:L(@"Address like https://example.com/path (http or https, IPv4 or domain)",@"Адрес вида https://example.com/path (http или https, IPv4 или домен)");
    return nil;
}
- (NSString *)hintFor:(NSString *)key {
    NSArray *range=[self limits][key];
    if ([key isEqual:ASV_HC_PORT]) return L(@"1–65535. Empty: auto (443 for HTTPS and TCP, 80 for HTTP).",@"1–65535. Пусто — авто (443 для HTTPS и TCP, 80 для HTTP).");
    if (range) return [NSString stringWithFormat:L(@"%@–%@. Empty: default.",@"%@–%@. Пусто — по умолчанию."),range[0],range[1]];
    if ([key isEqual:ASV_HC_TARGET]) return [NSString stringWithFormat:L(@"IPv4 or domain. Empty: %@.",@"IPv4 или домен. Пусто — %@."),ASV_DEFAULT_HC_TARGET];
    return L(@"http(s):// address. Empty: Cloudflare.",@"Адрес http(s)://. Пусто — Cloudflare.");
}
- (void)editorChanged:(NSNotification *)notification {
    UITextField *field=notification.object;
    if (!_editor || ![_editor.textFields containsObject:field]) return;
    NSString *text=[field.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *problem=[self problemWith:text key:_editKey];
    _okAction.enabled=problem==nil;
    _editor.message=problem?[@"⚠️ " stringByAppendingString:problem]:[self hintFor:_editKey];
}
- (void)editField:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    NSString *previous=[self fieldValue:key];
    BOOL numeric=[self limits][key]!=nil;
    _editKey=key;
    UIAlertController *alert=[UIAlertController alertControllerWithTitle:specifier.name message:[self hintFor:key] preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *field){
        field.text=previous;
        field.placeholder=[key isEqual:ASV_HC_PORT]?L(@"auto",@"авто"):nil;
        field.keyboardType=numeric?UIKeyboardTypeNumberPad:UIKeyboardTypeURL;
        field.autocapitalizationType=UITextAutocapitalizationTypeNone;
        field.autocorrectionType=UITextAutocorrectionTypeNo;
        field.clearButtonMode=UITextFieldViewModeWhileEditing;
    }];
    __weak ASVExtraController *weakSelf=self;
    [alert addAction:[UIAlertAction actionWithTitle:L(@"Cancel",@"Отмена") style:UIAlertActionStyleCancel handler:^(__unused UIAlertAction *action){ [weakSelf closeEditor]; }]];
    UIAlertAction *ok=[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        ASVExtraController *controller=weakSelf;
        NSString *text=[alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        [controller closeEditor];
        NSString *problem=[controller problemWith:text key:key];
        // Invalid input never replaces the last valid value.
        if (problem) { [controller complain:[NSString stringWithFormat:@"%@\n%@",L(@"Invalid value, the previous one is kept.",@"Недопустимое значение, оставлено прежнее."),problem]];return; }
        id stored=nil;
        if (text.length) stored=[controller limits][key]?@(text.integerValue):text;
        if ([controller save:^(NSMutableDictionary *prefs){ if (stored) prefs[key]=stored; else [prefs removeObjectForKey:key]; }]) [controller reloadSpecifier:specifier];
    }];
    [alert addAction:ok];
    alert.preferredAction=ok;
    _okAction=ok;_editor=alert;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(editorChanged:) name:UITextFieldTextDidChangeNotification object:nil];
    [self presentViewController:alert animated:YES completion:nil];
}
- (void)closeEditor {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:UITextFieldTextDidChangeNotification object:nil];
    _okAction=nil;_editor=nil;_editKey=nil;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier=[self specifierAtIndexPath:indexPath];
    if ([specifier propertyForKey:@"asvField"]) { [tableView deselectRowAtIndexPath:indexPath animated:YES];[self editField:specifier];return; }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

#pragma mark Specifiers

- (PSSpecifier *)setting:(NSString *)name key:(NSString *)key type:(PSCellType)type fallback:(id)fallback {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:type==PSLinkListCell?PSListItemsController.class:nil cell:type edit:nil];
    [s setProperty:key forKey:@"key"];[s setProperty:ASV_DOMAIN forKey:@"defaults"];
    if (fallback) [s setProperty:fallback forKey:@"default"];
    return s;
}
- (PSSpecifier *)field:(NSString *)name key:(NSString *)key {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:nil get:@selector(readPreferenceValue:) detail:nil cell:PSTitleValueCell edit:nil];
    [s setProperty:key forKey:@"key"];[s setProperty:@YES forKey:@"asvField"];
    return s;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=L(@"Extra",@"Дополнительно");
    NSDictionary *prefs=[self prefs];
    BOOL ls=ASVExtraOptionConfigured(prefs,ASV_LS_DISCONNECT), health=ASVExtraOptionConfigured(prefs,ASV_HEALTH);
    BOOL redundancy=ASVExtraOptionConfigured(prefs,ASV_REDUNDANCY);
    NSMutableArray *items=[NSMutableArray array], *headers=[NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"Extra",@"Дополнительно"),L(@"Disconnect VPN on LS: after the delay set in Tuning, locking the screen switches the active VPN off; unlocking switches it back on. A VPN you turned off yourself stays off.\n\nAlways ON VPN: reconnects the VPN last selected in iOS whenever it drops, for example when iOS kills it for memory. While the option is on, a manual disconnect is undone too: turn the option off first to stop the VPN. With \"Disconnect VPN on LS\" on, nothing is reconnected while the phone is locked.\n\nHealth Check VPN Disconnect: while the VPN is connected, periodically checks that traffic passes through the tunnel to a public resource. After several failures in a row it disconnects the broken VPN; together with Always ON the VPN then reconnects at once. No checks run without a VPN, without a network, or on the locked screen when \"Disconnect VPN on LS\" is on.\n\nThe global Enable switch and CC toggle suspend all options while off; their saved settings remain.",@"Отключать VPN на LS — через заданную в «Тюнинге» задержку после блокировки экрана отключает активный VPN, после разблокировки подключает снова. VPN, выключенный вами вручную, остаётся выключенным.\n\nВсегда включать VPN — подключает последний выбранный в iOS VPN, если он отвалился, например когда iOS выгрузила его из-за нехватки памяти. Пока опция включена, ручное отключение VPN тоже отменяется: чтобы выключить VPN, сначала выключите опцию. При включённом «Отключать VPN на LS» на заблокированном телефоне переподключения нет.\n\nОтключать VPN по Health Check — пока VPN подключён, периодически проверяет, проходит ли через туннель трафик до публичного ресурса. После нескольких неудач подряд отключает неработающий VPN; вместе с «Всегда включать VPN» он сразу подключается заново. Без VPN, без сети и на заблокированном экране при включённом «Отключать VPN на LS» проверок нет.\n\nГлобальный переключатель «Включить» и кнопка CC останавливают все опции; их настройки сохраняются.")]];
    [items addObject:[self setting:L(@"Disconnect VPN on LS",@"Отключать VPN на LS") key:ASV_LS_DISCONNECT type:PSSwitchCell fallback:@NO]];
    [items addObject:[self setting:L(@"Always ON VPN",@"Всегда включать VPN") key:ASV_ALWAYS_ON type:PSSwitchCell fallback:@NO]];
    [items addObject:[self setting:L(@"Health Check VPN Disconnect",@"Отключать VPN по Health Check") key:ASV_HEALTH type:PSSwitchCell fallback:@NO]];
    [items addObject:[self setting:L(@"Redundancy",@"Резервирование") key:ASV_REDUNDANCY type:PSSwitchCell fallback:@NO]];
    headers[0]=@[headers[0][0],[headers[0][1] stringByAppendingString:L(@"\n\nRedundancy is available only in BYPASS and TUNNEL ONLY. Enabling it enables Health Check and Always ON. Reserve profiles are tried in selection order (Round-Robin) or in a random order without repeats. If every reserve fails, VPN, Redundancy and Always ON are stopped until you intervene.\n\nWithout Redundancy, the same failure threshold also limits consecutive reconnect cycles with no successful check. Reaching it disables Health Check and Always ON. A successful check breaks the failed-cycle sequence.",@"\n\nРезервирование доступно только в BYPASS и TUNNEL ONLY. Включение активирует Health Check и «Всегда включать VPN». Резервные профили проверяются в порядке выбора (Round-Robin) или в случайном порядке без повторов. Если не работает ни один резерв, VPN, резервирование и автоматическое подключение выключаются до вашего вмешательства.\n\nБез резервирования тот же порог неудач ограничивает последовательные циклы переподключения без успешной проверки. По достижении порога Health Check и автоматическое подключение выключаются. Успешная проверка прерывает последовательность неудачных циклов.")]];
    if(redundancy) {
        PSSpecifier *reserves=[PSSpecifier preferenceSpecifierNamed:L(@"Reserve VPNs",@"Резервные VPN") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];[reserves setButtonAction:@selector(openReserves)];[items addObject:reserves];
    }

    void (^section)(NSString *,NSString *)=^(NSString *title,NSString *help){
        [items addObject:[PSSpecifier groupSpecifierWithName:nil]];[headers addObject:@[title,help]];
    };
    if(ls) {
        section(L(@"Tuning: Lock screen",@"Тюнинг: Экран блокировки"),L(@"LS delay: 0–600 seconds. PiP/music protection keeps VPN connected while media plays; pausing starts the delay.",@"Задержка LS: 0–600 секунд. Защита PiP/музыки сохраняет VPN при воспроизведении; после паузы начинается задержка."));
        [items addObject:[self field:L(@"LS delay, s",@"Задержка LS, с") key:ASV_LS_DELAY]];
        [items addObject:[self setting:L(@"Keep VPN for PiP/music on LS",@"PiP/музыка не ВЫКЛ VPN на LS") key:ASV_LS_MEDIA type:PSSwitchCell fallback:@NO]];
    }
    if(health) {
        section(L(@"Tuning: Health Check",@"Тюнинг: Health Check"),L(@"Checks are shared with Redundancy. Failures before OFF counts individual failed probes (1–10, default 3); reaching it disconnects VPN. Timeout: 1–120 s; interval: 10–3600 s. HTTPS/HTTP check a reply, TCP checks connection, PING uses ICMP without a port. Empty port means auto: 443 for HTTPS/TCP, 80 for HTTP.",@"Проверки общие с резервированием. «Неудач подряд для ВЫКЛ» — число неудачных проверок (1–10, по умолчанию 3), после которого VPN отключается. Таймаут: 1–120 с; интервал: 10–3600 с. HTTPS/HTTP проверяют ответ, TCP — соединение, PING — ICMP без порта. Пустой порт — авто: 443 для HTTPS/TCP, 80 для HTTP."));
        PSSpecifier *method=[self setting:L(@"Check method",@"Метод проверки") key:ASV_HC_METHOD type:PSLinkListCell fallback:ASV_DEFAULT_HC_METHOD];
        [method setValues:@[@"https",@"http",@"tcp",@"ping"] titles:@[@"HTTPS",@"HTTP",@"TCP",@"PING"]];[items addObject:method];
        [items addObject:[self field:L(@"Health Check target",@"Ресурс Health Check") key:ASV_HC_TARGET]];
        if(![ASVHealthMethod(prefs) isEqual:@"ping"])[items addObject:[self field:L(@"Port",@"Порт") key:ASV_HC_PORT]];
        [items addObject:[self field:L(@"Interval, s",@"Интервал, с") key:ASV_HC_INTERVAL]];
        [items addObject:[self field:L(@"Timeout, s",@"Таймаут, с") key:ASV_HC_TIMEOUT]];
        [items addObject:[self field:L(@"Failures before OFF",@"Неудач подряд для ВЫКЛ") key:ASV_HC_FAILURES]];
    }
    if(redundancy) {
        section(L(@"Tuning: Redundancy",@"Тюнинг: Резервирование"),L(@"Cycles before switching: 1–10, default 1. A cycle ends when Health Check disconnects VPN. With 3, the first two cycles restart the same VPN, the third selects the next reserve. A successful check resets the counter. Connection failures/timeouts also count. Select the primary VPN in Reserve VPNs; auto uses the current system selection. If every reserve exhausts its cycles, automatic reconnect and redundancy stop.",@"Циклов до переключения: 1–10, по умолчанию 1. Цикл заканчивается отключением по Health Check. При 3 первые два цикла переподключают тот же VPN, третий выбирает следующий резерв. Успешная проверка сбрасывает счётчик. Ошибка или таймаут подключения тоже считается циклом. Основной VPN выбирается в «Резервные VPN»; авто использует текущий системный выбор. Если все резервы исчерпали циклы, автоматическое подключение и резервирование останавливаются."));
        [items addObject:[self field:L(@"Cycles before switching",@"Циклов до переключения") key:ASV_RED_CYCLES]];
        PSSpecifier *algorithm=[self setting:L(@"Redundancy Switch Algorithm",@"Алгоритм резервирования") key:ASV_RED_ALGORITHM type:PSLinkListCell fallback:@"roundRobin"];
        [algorithm setValues:@[@"roundRobin",@"random"] titles:@[@"Round-Robin",@"Random"]];[items addObject:algorithm];
    }
    {
        section(L(@"Tuning: General",@"Тюнинг: Общие"),L(@"Public IP service: an HTTP(S) URL returning Cloudflare trace, JSON or plain IP. Reset tuning restores defaults for all tuning sections; app lists and VPN selections remain saved.",@"Сервис белого IP: HTTP(S)-адрес с ответом Cloudflare trace, JSON или IP текстом. Сброс тюнинга возвращает значения по умолчанию во всех секциях; списки приложений и выбранные VPN сохраняются."));
        [items addObject:[self field:L(@"IP check service",@"Сервис проверки IP") key:ASV_IP_SERVICE]];
        PSSpecifier *reset=[PSSpecifier preferenceSpecifierNamed:L(@"Reset tuning",@"Сбросить тюнинг") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
        [reset setButtonAction:@selector(resetTuning)];[items addObject:reset];
    }
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"State",@"Состояние"),L(@"The VPN profile selected in iOS, its connection state, the latest Health Check result and the extra options that are on. Updates automatically.\n\n\"No link\" means the VPN is connected but the last checks failed.\n\nThe event log keeps the last 300 events: VPN connections and disconnections, Health Check results, reconnects and screen locks.",@"Профиль VPN, выбранный в iOS, состояние его подключения, последний результат Health Check и включённые дополнительные опции. Обновляется автоматически.\n\n«Нет связи» — VPN подключён, но последние проверки не прошли.\n\nЖурнал событий хранит последние 300 событий: подключения и отключения VPN, результаты Health Check, переподключения и блокировки экрана.")]];
    PSSpecifier *terminal=[PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [terminal setProperty:@YES forKey:@"asvTerminal"];[items addObject:terminal];
    // Keep the journal reachable after the safety breaker switches all options off.
    PSSpecifier *log=[PSSpecifier preferenceSpecifierNamed:L(@"Event log",@"Журнал событий") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [log setButtonAction:@selector(openEventLog)];[items addObject:log];
    _stateText=[self buildState];
    _headers=[headers copy];
    _specifiers=[items copy];
    return _specifiers;
}
- (void)openEventLog { [self.navigationController pushViewController:[ASVEventLogController new] animated:YES]; }
- (void)openReserves {
    if(ASVExtraOptionConfigured([self prefs],ASV_REDUNDANCY))
        [self.navigationController pushViewController:[[ASVProfileListController alloc] initForReserves] animated:YES];
}
- (void)resetTuning {
    if ([self save:^(NSMutableDictionary *prefs){ [prefs removeObjectsForKeys:@[ASV_LS_DELAY,ASV_LS_MEDIA,ASV_HC_METHOD,ASV_HC_TARGET,ASV_HC_PORT,ASV_HC_INTERVAL,ASV_HC_FAILURES,ASV_IP_SERVICE,ASV_HC_TIMEOUT,ASV_RED_ALGORITHM,ASV_RED_CYCLES]]; }]) [self reloadSpecifiers];
}
- (NSAttributedString *)buildState {
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_EXTRA_STATE] ?: @{};
    NSDictionary *prefs=[self prefs];
    NSMutableAttributedString *text=[NSMutableAttributedString new];
    UIColor *green=UIColor.systemGreenColor,*red=UIColor.systemRedColor,*gray=UIColor.systemGrayColor,*white=UIColor.whiteColor,*orange=UIColor.systemOrangeColor;
    BOOL active=[state[@"vpnActive"] boolValue], health=ASVExtraOptionActive(prefs,ASV_HEALTH);
    NSString *healthText=state[@"health"];
    ASVTerminalLine(text,L(@"Profile:",@"Профиль:"),[state[@"vpnName"] length]?state[@"vpnName"]:@"—",[state[@"vpnName"] length]?white:gray,10);
    // ne_session status: 1 disconnected, 2 connecting, 3 connected, 4 reasserting, 5 disconnecting.
    NSInteger status=[state[@"vpnStatus"] integerValue];
    NSString *value;UIColor *color;
    if (status==2) { value=L(@"connecting",@"подключается");color=orange; }
    else if (status==4) { value=L(@"reconnecting",@"переподключается");color=orange; }
    else if (status==5) { value=L(@"disconnecting",@"отключается");color=orange; }
    else if (active || status==3) {
        BOOL noLink=health && [healthText hasPrefix:@"fail:"];
        value=noLink?L(@"no link",@"нет связи"):L(@"connected",@"подключён");color=noLink?red:green;
    } else { value=L(@"disconnected",@"отключён");color=red; }
    ASVTerminalLine(text,L(@"Status:",@"Статус:"),value,color,10);
    value=L(@"off",@"выкл");color=gray;
    if (health) {
        NSInteger threshold=ASVIntSetting(prefs,ASV_HC_FAILURES,ASV_DEFAULT_HC_FAILURES,1,10);
        if ([healthText hasPrefix:@"ok:"]) { value=[NSString stringWithFormat:@"OK %@ %@",[healthText substringFromIndex:3],L(@"ms",@"мс")];color=green; }
        else if ([healthText hasPrefix:@"fail:"]) { value=[NSString stringWithFormat:@"%@ %@/%ld: %@",L(@"fail",@"сбой"),state[@"healthFails"],(long)threshold,[healthText substringFromIndex:5]];color=red; }
        else if ([healthText isEqual:@"nonet"]) { value=L(@"no network",@"нет сети");color=orange; }
        else if ([healthText isEqual:@"notunnel"]) { value=L(@"no tunnel",@"нет туннеля");color=orange; }
        else { value=active?L(@"waiting",@"ожидание"):L(@"VPN is off",@"VPN выключен");color=white; }
    }
    if(health)ASVTerminalLine(text,L(@"Check:",@"Проверка:"),value,color,10);
    NSMutableArray *options=[NSMutableArray array];
    if (ASVExtraOptionActive(prefs,ASV_LS_DISCONNECT)) [options addObject:@"LS"];
    if (ASVExtraOptionActive(prefs,ASV_ALWAYS_ON)) [options addObject:@"Always ON"];
    if (health) [options addObject:@"Health Check"];
    if (ASVExtraOptionActive(prefs,ASV_REDUNDANCY)) [options addObject:L(@"Redundancy",@"Резервирование")];
    ASVTerminalLine(text,L(@"Options:",@"Опции:"),options.count?[options componentsJoinedByString:@", "]:L(@"none",@"нет"),options.count?green:gray,10);
    return text;
}
- (void)refreshState {
    NSDate *prefsStamp=[[NSFileManager defaultManager] attributesOfItemAtPath:ASV_PREFS error:nil].fileModificationDate;
    if(![prefsStamp isEqual:_prefsStamp]){_prefsStamp=prefsStamp;_specifiers=nil;[self reloadSpecifiers];}
    NSDate *stamp=[[NSFileManager defaultManager] attributesOfItemAtPath:ASV_EXTRA_STATE error:nil].fileModificationDate;
    if (stamp && [stamp isEqualToDate:_stateStamp]) return;
    _stateStamp=stamp;
    _stateText=[self buildState];
    for (PSSpecifier *specifier in _specifiers) if ([specifier propertyForKey:@"asvTerminal"]) [self reloadSpecifier:specifier];
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
- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    if ([[self specifierAtIndexPath:indexPath] propertyForKey:@"asvTerminal"]) return ASVTerminalHeight(_stateText,self.view.bounds.size.width);
    return [super tableView:tableView heightForRowAtIndexPath:indexPath];
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell=[super tableView:tableView cellForRowAtIndexPath:indexPath];
    PSSpecifier *specifier=[self specifierAtIndexPath:indexPath];
    for (UIView *view in [cell.contentView.subviews copy]) if (view.tag==0x5A6) [view removeFromSuperview];
    if ([specifier propertyForKey:@"asvTerminal"]) ASVFillTerminal(cell,_stateText,0x5A6);
    else if ([specifier propertyForKey:@"asvField"]) {
        cell.selectionStyle=UITableViewCellSelectionStyleDefault;
        cell.userInteractionEnabled=YES;
        cell.detailTextLabel.lineBreakMode=NSLineBreakByTruncatingMiddle;
        cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    }
    return cell;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_timer invalidate];
    _timer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refreshState) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [_timer invalidate];_timer=nil;[super viewWillDisappear:animated]; }
- (void)dealloc { [_timer invalidate];[[NSNotificationCenter defaultCenter] removeObserver:self]; }
@end

