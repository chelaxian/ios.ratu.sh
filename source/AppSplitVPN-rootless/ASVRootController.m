#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <dlfcn.h>
#import <notify.h>
#import <rootless.h>
#import "Shared.h"
// Theos' deliberately minimal header omits this API, also used by AirKeeper.
// Keep the runtime gate; verify the selector on the target Settings process in QA.
@interface PSSpecifier (ASVListValues)
- (void)setValues:(NSArray *)values titles:(NSArray *)titles;
@end
static NSString *L(NSString *en,NSString *ru) {
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"] ? ru : en;
}
@interface ASVRootController : PSListController
@end
@implementation ASVRootController
- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][[specifier propertyForKey:@"key"]] ?: [specifier propertyForKey:@"default"];
}
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key=[specifier propertyForKey:@"key"];
    if (![@[@"enabled",@"mode",ASV_VPN,ASV_DIRECT] containsObject:key]) return;
    NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[key]=value;
    if (![prefs writeToFile:ASV_PREFS atomically:YES]) {
        UIAlertController *alert=[UIAlertController alertControllerWithTitle:L(@"Could not save",@"Не удалось сохранить") message:nil preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];return;
    }
    notify_post(ASV_NOTIFY);
}
- (PSSpecifier *)setting:(NSString *)name key:(NSString *)key type:(PSCellType)type fallback:(id)fallback detail:(Class)detail {
    PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setPreferenceValue:specifier:) get:@selector(readPreferenceValue:) detail:detail cell:type edit:nil];
    [s setProperty:key forKey:@"key"];[s setProperty:ASV_DOMAIN forKey:@"defaults"];[s setProperty:fallback forKey:@"default"];
    return s;
}
- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    dlopen(ROOT_PATH("/Library/Frameworks/AltList.framework/AltList"),RTLD_NOW);
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
    group=[PSSpecifier groupSpecifierWithName:L(@"Application lists",@"Списки приложений")];
    [group setProperty:L(@"TUNNEL ONLY: only VPN apps use the tunnel. BYPASS: DIRECT apps bypass it. Reopen apps after changing rules.",@"TUNNEL ONLY: туннель только для списка VPN. BYPASS: список DIRECT идёт напрямую. После изменения правил переоткройте приложения.") forKey:@"footerText"];
    [items addObject:group];
    Class picker=NSClassFromString(@"ATLApplicationListMultiSelectionController");
    for (NSString *key in @[ASV_VPN,ASV_DIRECT]) {
        PSSpecifier *s=[self setting:[key isEqual:ASV_VPN]?@"VPN":@"DIRECT" key:key type:PSLinkListCell fallback:@[] detail:picker];
        [s setProperty:@[@{@"sectionType":@"User"},@{@"sectionType":@"System"}] forKey:@"sections"];
        [s setProperty:@YES forKey:@"useSearchBar"];[s setProperty:@YES forKey:@"includeIdentifiersInSearch"];
        [s setProperty:@YES forKey:@"showIdentifiersAsSubtitle"];
        [s setProperty:@NO forKey:@"defaultApplicationSwitchValue"];
        [s setProperty:@(picker!=Nil) forKey:@"enabled"];[items addObject:s];
    }
    NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:ASV_STATE];
    NSString *code=state[@"status"] ?: @"unavailable";
    if ([NSDate date].timeIntervalSince1970-[state[@"updated"] doubleValue]>90) code=@"unavailable";
    NSDictionary *labels=@{
        @"disabled":L(@"Disabled",@"Выключен"),@"waitingVPN":L(@"Waiting for VPN",@"Ожидание VPN"),
        @"active":L(@"Rules applied",@"Правила применены"),@"error":L(@"Rules could not be updated",@"Не удалось обновить правила"),
        @"unsupported":L(@"System API unavailable",@"Системный API недоступен"),
        @"stopped":L(@"Service stopped",@"Служба остановлена"),@"unavailable":L(@"Service has not started",@"Служба ещё не запущена")};
    group=[PSSpecifier groupSpecifierWithName:L(@"Status",@"Статус")];
    NSString *description=labels[code] ?: code;
    NSArray *missing=state[@"unresolved"];
    if (missing.count) description=[description stringByAppendingFormat:L(@". Unavailable apps: %lu",@". Недоступных приложений: %lu"),(unsigned long)missing.count];
    [group setProperty:description forKey:@"footerText"];[items addObject:group];
    PSSpecifier *refresh=[PSSpecifier preferenceSpecifierNamed:L(@"Refresh status",@"Обновить статус") target:self set:nil get:nil detail:nil cell:PSButtonCell edit:nil];
    [refresh setButtonAction:@selector(refreshStatus)];[items addObject:refresh];
    _specifiers=[items copy];return _specifiers;
}
- (void)refreshStatus { _specifiers=nil;[self reloadSpecifiers]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated];[self refreshStatus]; }
@end
