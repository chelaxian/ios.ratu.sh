#import "Shared.h"
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>
@interface RPListController : PSListController
@property int notificationToken;
- (NSString*)pageKind;
@end
@interface RPPresetsController : RPListController @end
@interface RPDaemonsController : RPListController @end
@interface RPSettingsController : RPListController @end
@implementation RPListController
- (NSString*)pageKind {return @"menu";}
- (instancetype)init {if((self=[super init])){__weak RPListController *w=self;notify_register_dispatch("com.ratush.daemonpresets.changed",&_notificationToken,dispatch_get_main_queue(),^(int t){[w reloadSpecifiers];w.view.userInteractionEnabled=YES;});}return self;}
- (void)dealloc {notify_cancel(_notificationToken);}
- (void)viewWillAppear:(BOOL)a {[super viewWillAppear:a];NSDictionary *titles=@{@"menu":@"Демоны iOS",@"presets":@"Пресеты",@"jobs":@"Демоны",@"settings":@"Настройки"};self.title=titles[[self pageKind]];Command(@"query");[self reloadSpecifiers];}
- (void)send:(NSString*)c {self.view.userInteractionEnabled=NO;Command(c);dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{self.view.userInteractionEnabled=YES;});}
- (PSSpecifier*)group:(NSString*)name footer:(NSString*)footer {PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:NULL get:NULL detail:Nil cell:PSGroupCell edit:Nil];[s setProperty:footer forKey:@"footerText"];return s;}
- (PSSpecifier*)toggle:(NSString*)name kind:(NSString*)kind jid:(NSString*)jid {PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:name target:self set:@selector(setValue:specifier:) get:@selector(value:) detail:Nil cell:PSSwitchCell edit:Nil];[s setProperty:kind forKey:@"kind"];if(jid)[s setProperty:jid forKey:@"jid"];return s;}
- (NSArray*)planned {NSDictionary *s=Status();if([s[@"preset"] isEqual:@"custom"])return s[@"custom"]?:@[];for(NSDictionary *p in Catalog()[@"presets"])if([p[@"id"] isEqual:s[@"preset"]])return p[@"jobs"];return @[];}
- (id)value:(PSSpecifier*)s {NSString *k=[s propertyForKey:@"kind"];NSDictionary *st=Status();if([k isEqual:@"master"])return st[@"enabled"]?:@NO;if([k isEqual:@"cc"])return @([st[@"ccPresets"] containsObject:[s propertyForKey:@"jid"]]);return @([[self planned] containsObject:[s propertyForKey:@"jid"]]);}
- (void)setValue:(id)v specifier:(PSSpecifier*)s {NSString *k=[s propertyForKey:@"kind"];if([k isEqual:@"master"])[self send:[v boolValue]?@"on":@"off"];else [self send:[([k isEqual:@"cc"]?@"cc.":@"job.") stringByAppendingString:[s propertyForKey:@"jid"]]];}
- (void)choosePreset:(PSSpecifier*)s {[self send:[@"preset." stringByAppendingString:[s propertyForKey:@"jid"]]];}
- (NSArray*)specifiers {
 if(_specifiers)return _specifiers;
 NSDictionary *st=Status();NSMutableArray *a=[NSMutableArray array];
 NSString *page=[self pageKind];
 NSString *health=!st.count?@"Нет ответа управляющей службы":[st[@"verified"] boolValue]?@"Состояния launchd подтверждены":@"Есть ошибка применения: проверьте состояния ниже";
 if([page isEqual:@"menu"]){
  NSString *preset=@"Не выбран";for(NSDictionary *p in Catalog()[@"presets"])if([p[@"id"] isEqual:st[@"preset"]])preset=p[@"name"];
  [a addObject:[self group:@"" footer:[NSString stringWithFormat:@"Твик %@. Набор: %@. %@.",[st[@"enabled"] boolValue]?@"включён":@"выключен",preset,health]]];
  NSArray *names=@[@"Пресеты",@"Демоны",@"Настройки"];NSArray *classes=@[RPPresetsController.class,RPDaemonsController.class,RPSettingsController.class];
  for(NSUInteger i=0;i<names.count;i++){PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:names[i] target:self set:NULL get:NULL detail:classes[i] cell:PSLinkCell edit:Nil];[a addObject:s];}
 }
 if([page isEqual:@"settings"]){
 [a addObject:[self group:@"Реальное управление launchd" footer:[NSString stringWithFormat:@"%@. ВЫКЛ восстанавливает состояния служб до вмешательства твика. Выбор набора при выключенном мастер-переключателе не отключает службы. После полного перезапуска iPhone примените Dopamine для доступа к управлению.",health]]];
 [a addObject:[self toggle:@"Включить твик" kind:@"master" jid:nil]];
 if([st[@"errors"] count])[a addObject:[self group:@"Ошибка" footer:[st[@"errors"] componentsJoinedByString:@"\n"]]];
 }
 if([page isEqual:@"presets"]){
 [a addObject:[self group:@"Готовые наборы" footer:@"Выбор заменяет набор. Фотоанализ включает photoanalysisd, mediaanalysisd и его вспомогательную службу. На время отключения новая индексация и распознавание фото приостанавливаются."]];
 for(NSDictionary *p in Catalog()[@"presets"]){NSString *n=[NSString stringWithFormat:@"%@%@",[p[@"id"] isEqual:st[@"preset"]]?@"✓ ":@"",p[@"name"]];PSSpecifier *s=[PSSpecifier preferenceSpecifierNamed:n target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];s.buttonAction=@selector(choosePreset:);[s setProperty:p[@"id"] forKey:@"jid"];[a addObject:s];}
 [a addObject:[self group:@"Базовый набор" footer:@"Отключает диагностику, сообщения компаниям, ClassKit и две службы Apple Watch. Подходит, если эти функции не используются. Перед сопряжением Apple Watch верните службы часов."]];
 }
 if([page isEqual:@"settings"]){
 [a addObject:[self group:@"Список в пункте управления" footer:@"Долгое нажатие показывает только выбранные здесь наборы. Короткое нажатие включает или выключает мастер-переключатель."]];
 for(NSDictionary *p in Catalog()[@"presets"])[a addObject:[self toggle:p[@"name"] kind:@"cc" jid:p[@"id"]]];
 }
 if([page isEqual:@"jobs"]){
 [a addObject:[self group:@"Отдельные службы" footer:@"Переключатель означает «отключать в наборе». Изменение создаёт индивидуальный набор. Под каждым пунктом показаны реальные запрет запуска и загрузка службы; загруженная служба может ожидать запрос без процесса."]];
 for(NSDictionary *j in Catalog()[@"jobs"]){NSDictionary *live=st[@"jobs"][j[@"id"]];NSString *foot=[NSString stringWithFormat:@"%@\nlaunchd: %@; %@.",j[@"note"],[live[@"disabled"] boolValue]?@"запуск запрещён":@"запуск разрешён",[live[@"loaded"] boolValue]?@"служба загружена":@"служба выгружена"];[a addObject:[self group:@"" footer:foot]];[a addObject:[self toggle:j[@"name"] kind:@"job" jid:j[@"id"]]];}
 }
 _specifiers=a;return a;
}
@end
@implementation RPPresetsController
- (NSString*)pageKind {return @"presets";}
@end
@implementation RPDaemonsController
- (NSString*)pageKind {return @"jobs";}
@end
@implementation RPSettingsController
- (NSString*)pageKind {return @"settings";}
@end
