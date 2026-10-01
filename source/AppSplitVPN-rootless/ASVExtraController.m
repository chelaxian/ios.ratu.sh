#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSListItemsController.h>
#import <notify.h>
#import <objc/message.h>
#import "ASVUI.h"
#import "ASVExtraController.h"
@interface PSSpecifier (ASVExtraValues)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
- (void)setKeyboardType:(UIKeyboardType)type autoCaps:(UITextAutocapitalizationType)caps autoCorrection:(UITextAutocorrectionType)correction;
@end
@interface PSListController (ASVExtraIndexPath)
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

static NSArray<NSString *> *ASVExtraNumericKeys(void) { return @[ASV_LS_DELAY,ASV_HC_PORT,ASV_HC_INTERVAL,ASV_HC_FAILURES]; }

@implementation ASVExtraController {
    NSArray<NSArray<NSString *> *> *_headers;
    NSTimer *_timer;
    NSDate *_stateStamp;
    NSAttributedString *_stateText;
}
+ (NSUInteger)enabledCount {
    NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{};
    NSUInteger count=0;
    for (NSString *key in @[ASV_LS_DISCONNECT,ASV_ALWAYS_ON,ASV_HEALTH]) if ([prefs[key] boolValue]) count++;
    return count;
}
- (NSDictionary *)prefs { return [NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{}; }
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    id value=[self prefs][key];
    if ([ASVExtraNumericKeys() containsObject:key] || [@[ASV_HC_TARGET,ASV_IP_SERVICE] containsObject:key])
        return value ? [value description] : [[specifier propertyForKey:@"default"] description];
    return value ?: [specifier propertyForKey:@"default"];
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
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    NSArray *switches=@[ASV_LS_DISCONNECT,ASV_ALWAYS_ON,ASV_HEALTH];
    if (![switches containsObject:key] && ![ASVExtraNumericKeys() containsObject:key] && ![@[ASV_HC_METHOD,ASV_HC_TARGET,ASV_IP_SERVICE] containsObject:key]) return;
    id stored=value;
    if ([value isKindOfClass:NSString.class]) {
        NSString *text=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        stored=text.length ? text : nil;
        if (stored && [ASVExtraNumericKeys() containsObject:key]) {
            NSDictionary *limits=@{ASV_LS_DELAY:@[@0,@600],ASV_HC_PORT:@[@0,@65535],ASV_HC_INTERVAL:@[@10,@3600],ASV_HC_FAILURES:@[@1,@10]};
            NSScanner *scanner=[NSScanner scannerWithString:text];
            NSInteger number=0;
            if (![scanner scanInteger:&number] || !scanner.atEnd) { [self complain:L(@"Enter a whole number",@"Введите целое число")];[self reloadSpecifier:specifier];return; }
            NSArray *range=limits[key];
            number=MIN([range[1] integerValue],MAX([range[0] integerValue],number));
            stored=([key isEqual:ASV_HC_PORT] && number==0) ? nil : @(number);
        } else if (stored && [key isEqual:ASV_HC_TARGET] && !ASVValidHost(text)) {
            [self complain:L(@"Enter an IP address or a domain name",@"Введите IP-адрес или доменное имя")];[self reloadSpecifier:specifier];return;
        } else if (stored && [key isEqual:ASV_IP_SERVICE]) {
            NSURL *url=[NSURL URLWithString:text];
            if (!([url.scheme isEqual:@"https"] || [url.scheme isEqual:@"http"]) || !url.host.length) {
                [self complain:L(@"Enter a full http(s):// address",@"Введите полный адрес http(s)://")];[self reloadSpecifier:specifier];return;
            }
        }
    }
    if ([self save:^(NSMutableDictionary *prefs){ if (stored) prefs[key]=stored; else [prefs removeObjectForKey:key]; }]) {
        [self reloadSpecifier:specifier];
        if ([key isEqual:ASV_HC_METHOD]) [self reloadSpecifiers];
    }
}
- (PSSpecifier *)setting:(NSString *)name key:(NSString *)key type:(PSCellType)type fallback:(id)fallback {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:type==PSLinkListCell?PSListItemsController.class:nil cell:type edit:nil];
    [s setProperty:key forKey:@"key"];[s setProperty:ASV_DOMAIN forKey:@"defaults"];
    if (fallback) [s setProperty:fallback forKey:@"default"];
    return s;
}
- (PSSpecifier *)field:(NSString *)name key:(NSString *)key fallback:(id)fallback placeholder:(NSString *)placeholder numeric:(BOOL)numeric {
    PSSpecifier *s=[self setting:name key:key type:PSEditTextCell fallback:fallback];
    if (placeholder) [s setProperty:placeholder forKey:@"placeholder"];
    if ([s respondsToSelector:@selector(setKeyboardType:autoCaps:autoCorrection:)])
        [s setKeyboardType:numeric?UIKeyboardTypeNumbersAndPunctuation:UIKeyboardTypeURL autoCaps:UITextAutocapitalizationTypeNone autoCorrection:UITextAutocorrectionTypeNo];
    [s setProperty:@YES forKey:@"asvField"];
    return s;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    self.title=L(@"Extra",@"Дополнительно");
    NSMutableArray *items=[NSMutableArray array], *headers=[NSMutableArray array];
    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"Extra",@"Дополнительно"),L(@"Disconnect VPN on LS: after the delay set below, the lock screen switches the active VPN off; unlocking switches it back on. A VPN you turned off yourself stays off.\n\nAlways ON VPN: watches the connection and reconnects the VPN last selected in iOS when it drops, for example when iOS kills it for memory. While the option is on, a manual disconnect is undone too: turn the option off first to stop the VPN. With \"Disconnect VPN on LS\" on, nothing is reconnected while the phone is locked.\n\nHealth Check Disconnect: while the VPN is connected, periodically checks that traffic passes through the tunnel to a public resource. After several failures in a row it disconnects the broken VPN; together with Always ON the VPN then reconnects at once. No checks run without a VPN, without a network, or on the locked screen when \"Disconnect VPN on LS\" is on.\n\nThese options work with any VPN app and do not depend on the Enable switch.",@"Отключать VPN на LS — через заданную ниже задержку после блокировки экрана отключает активный VPN, после разблокировки подключает его снова. VPN, выключенный вами вручную, остаётся выключенным.\n\nAlways ON VPN — следит за соединением и подключает последний выбранный в iOS VPN, если он отвалился, например когда iOS выгрузила его из-за нехватки памяти. Пока опция включена, ручное отключение VPN тоже отменяется: чтобы выключить VPN, сначала выключите опцию. При включённом «Отключать VPN на LS» на заблокированном телефоне переподключения нет.\n\nHealth Check Disconnect — пока VPN подключён, периодически проверяет, проходит ли через туннель трафик до публичного ресурса. После нескольких неудач подряд отключает неработающий VPN; вместе с Always ON он сразу подключается заново. Без VPN, без сети и на заблокированном экране при включённом «Отключать VPN на LS» проверок нет.\n\nОпции работают с любым VPN-приложением и не зависят от переключателя «Включить».")]];
    [items addObject:[self setting:L(@"Disconnect VPN on LS",@"Отключать VPN на LS") key:ASV_LS_DISCONNECT type:PSSwitchCell fallback:@NO]];
    [items addObject:[self setting:@"Always ON VPN" key:ASV_ALWAYS_ON type:PSSwitchCell fallback:@NO]];
    [items addObject:[self setting:@"Health Check Disconnect" key:ASV_HEALTH type:PSSwitchCell fallback:@NO]];

    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"Tuning",@"Тюнинг"),L(@"LS delay: seconds between locking and disconnecting the VPN (0–600).\n\nMethod: HTTPS — TLS connection and an HTTP reply, the strictest check (default); HTTP — TCP connection and an HTTP reply; TCP — connection only; PING — ICMP echo (some VPNs do not pass ICMP).\n\nTarget: IP address or domain to check. Empty port: 443 for HTTPS and TCP, 80 for HTTP; PING ignores the port.\n\nInterval: how often a working VPN is checked (10–3600 s). After a failure the check repeats in 10 s.\n\nFailures: how many checks in a row must fail before the VPN is disconnected (1–10).\n\nIP service: address used for the public IP on the main page. Cloudflare trace, JSON (ip, country) and plain-text replies are understood. If the default service is unreachable, Yandex is asked instead (IP without a country).\n\nAn empty field restores its default.",@"Задержка LS — сколько секунд после блокировки ждать перед отключением VPN (0–600).\n\nМетод: HTTPS — TLS-соединение и HTTP-ответ, самая строгая проверка (по умолчанию); HTTP — TCP-соединение и HTTP-ответ; TCP — только соединение; PING — ICMP echo (часть VPN не пропускает ICMP).\n\nРесурс — IP-адрес или домен для проверки. Пустой порт: 443 для HTTPS и TCP, 80 для HTTP; PING порт не использует.\n\nИнтервал — как часто проверяется работающий VPN (10–3600 с). После неудачи повтор через 10 с.\n\nНеудач подряд — сколько проверок подряд должно провалиться, чтобы VPN был отключён (1–10).\n\nСервис IP — адрес, по которому определяется белый IP на главной странице. Понимает ответы Cloudflare trace, JSON (ip, country) и простой текст. Если сервис по умолчанию недоступен, используется Яндекс (IP без страны).\n\nПустое поле возвращает значение по умолчанию.")]];
    [items addObject:[self field:L(@"LS delay, s",@"Задержка LS, с") key:ASV_LS_DELAY fallback:@ASV_DEFAULT_LS_DELAY placeholder:nil numeric:YES]];
    PSSpecifier *method=[self setting:L(@"Check method",@"Метод проверки") key:ASV_HC_METHOD type:PSLinkListCell fallback:ASV_DEFAULT_HC_METHOD];
    if ([method respondsToSelector:@selector(setValues:titles:)]) [method setValues:@[@"https",@"http",@"tcp",@"ping"] titles:@[@"HTTPS",@"HTTP",@"TCP",@"PING"]];
    [items addObject:method];
    [items addObject:[self field:L(@"Target",@"Ресурс") key:ASV_HC_TARGET fallback:ASV_DEFAULT_HC_TARGET placeholder:nil numeric:NO]];
    NSString *method0=ASVHealthMethod([self prefs]);
    NSString *autoPort=[method0 isEqual:@"ping"]?@"—":[NSString stringWithFormat:@"%@ (%ld)",L(@"auto",@"авто"),(long)ASVHealthPort(@{ASV_HC_METHOD:method0})];
    [items addObject:[self field:L(@"Port",@"Порт") key:ASV_HC_PORT fallback:@"" placeholder:autoPort numeric:YES]];
    [items addObject:[self field:L(@"Interval, s",@"Интервал, с") key:ASV_HC_INTERVAL fallback:@ASV_DEFAULT_HC_INTERVAL placeholder:nil numeric:YES]];
    [items addObject:[self field:L(@"Failures in a row",@"Неудач подряд") key:ASV_HC_FAILURES fallback:@ASV_DEFAULT_HC_FAILURES placeholder:nil numeric:YES]];
    [items addObject:[self field:L(@"IP service",@"Сервис IP") key:ASV_IP_SERVICE fallback:ASV_DEFAULT_IP_SERVICE placeholder:nil numeric:NO]];
    PSSpecifier *reset=[PSSpecifier preferenceSpecifierNamed:L(@"Reset tuning",@"Сбросить тюнинг") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [reset setButtonAction:@selector(resetTuning)];[items addObject:reset];

    [items addObject:[PSSpecifier groupSpecifierWithName:nil]];
    [headers addObject:@[L(@"State",@"Состояние"),L(@"Current state of the extra options and the latest actions taken by the tweak. Updates automatically.",@"Текущее состояние дополнительных опций и последние действия твика. Обновляется автоматически.")]];
    PSSpecifier *terminal=[PSSpecifier preferenceSpecifierNamed:@"" target:self set:nil get:nil detail:nil cell:PSStaticTextCell edit:nil];
    [terminal setProperty:@YES forKey:@"asvTerminal"];[items addObject:terminal];
    _stateText=[self buildState];
    _headers=[headers copy];
    _specifiers=[items copy];
    return _specifiers;
}
- (void)resetTuning {
    [self.view endEditing:YES];
    if ([self save:^(NSMutableDictionary *prefs){ [prefs removeObjectsForKeys:@[ASV_LS_DELAY,ASV_HC_METHOD,ASV_HC_TARGET,ASV_HC_PORT,ASV_HC_INTERVAL,ASV_HC_FAILURES,ASV_IP_SERVICE]]; }]) [self reloadSpecifiers];
}
- (NSString *)eventText:(NSDictionary *)event {
    NSDictionary *names=@{@"lsStop":L(@"LS: VPN disconnected",@"LS: VPN отключён"),@"lsStart":L(@"Unlock: VPN reconnected",@"Разблокировка: VPN подключён"),
        @"alwaysOn":L(@"Always ON: reconnecting",@"Always ON: переподключение"),@"healthStop":L(@"Health check: VPN disconnected",@"Проверка: VPN отключён")};
    NSDateFormatter *format=[NSDateFormatter new];format.dateFormat=@"HH:mm";
    NSString *time=[format stringFromDate:[NSDate dateWithTimeIntervalSince1970:[event[@"time"] doubleValue]]];
    NSString *text=names[event[@"code"]] ?: event[@"code"];
    return [event[@"detail"] length] ? [NSString stringWithFormat:@"%@ %@ (%@)",time,text,event[@"detail"]] : [NSString stringWithFormat:@"%@ %@",time,text];
}
- (NSAttributedString *)buildState {
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_EXTRA_STATE] ?: @{};
    NSDictionary *prefs=[self prefs];
    NSMutableAttributedString *text=[NSMutableAttributedString new];
    UIColor *green=UIColor.systemGreenColor,*red=UIColor.systemRedColor,*gray=UIColor.systemGrayColor,*white=UIColor.whiteColor;
    BOOL active=[state[@"vpnActive"] boolValue];
    NSString *name=[state[@"vpnName"] length]?state[@"vpnName"]:@"VPN";
    ASVTerminalLine(text,@"VPN:",[NSString stringWithFormat:@"%@ — %@",name,active?L(@"connected",@"подключён"):L(@"off",@"выключен")],active?green:red,11);
    ASVTerminalLine(text,L(@"Screen:",@"Экран:"),[state[@"locked"] boolValue]?L(@"locked",@"заблокирован"):L(@"unlocked",@"разблокирован"),white,11);
    NSString *health=state[@"health"];
    NSString *value=L(@"off",@"выкл");UIColor *color=gray;
    if ([prefs[ASV_HEALTH] boolValue]) {
        NSInteger threshold=ASVIntSetting(prefs,ASV_HC_FAILURES,ASV_DEFAULT_HC_FAILURES,1,10);
        if ([health hasPrefix:@"ok:"]) { value=[NSString stringWithFormat:@"OK %@ %@",[health substringFromIndex:3],L(@"ms",@"мс")];color=green; }
        else if ([health hasPrefix:@"fail:"]) { value=[NSString stringWithFormat:@"%@ %@/%ld: %@",L(@"fail",@"сбой"),state[@"healthFails"],(long)threshold,[health substringFromIndex:5]];color=red; }
        else if ([health isEqual:@"nonet"]) value=L(@"no network",@"нет сети");
        else if ([health isEqual:@"notunnel"]) value=L(@"no tunnel interface",@"нет туннеля");
        else { value=active?L(@"waiting",@"ожидание"):L(@"VPN is off",@"VPN выключен");color=white; }
    }
    ASVTerminalLine(text,L(@"Check:",@"Проверка:"),value,color,11);
    NSArray *events=[state[@"events"] isKindOfClass:NSArray.class]?state[@"events"]:@[];
    if (!events.count) ASVTerminalLine(text,L(@"Events:",@"События:"),L(@"none",@"нет"),gray,11);
    NSUInteger shown=0;
    for (NSDictionary *event in events.reverseObjectEnumerator) {
        if (![event isKindOfClass:NSDictionary.class] || shown++>=3) continue;
        ASVTerminalLine(text,shown==1?L(@"Events:",@"События:"):@"",[self eventText:event],white,11);
    }
    return text;
}
- (void)refreshState {
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
        UITextField *field=nil;
        for (NSString *name in @[@"editableTextField",@"textField"]) {
            SEL selector=NSSelectorFromString(name);
            if ([cell respondsToSelector:selector]) { field=((id(*)(id,SEL))objc_msgSend)(cell,selector);break; }
        }
        if ([field isKindOfClass:UITextField.class]) { field.textAlignment=NSTextAlignmentRight;field.clearButtonMode=UITextFieldViewModeWhileEditing; }
    }
    return cell;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [_timer invalidate];
    _timer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refreshState) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [self.view endEditing:YES];[_timer invalidate];_timer=nil;[super viewWillDisappear:animated]; }
- (void)dealloc { [_timer invalidate]; }
@end
