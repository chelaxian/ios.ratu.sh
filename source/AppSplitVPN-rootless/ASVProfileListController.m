#import "ASVProfileListController.h"
#import "ASVUI.h"
#import <notify.h>
@implementation ASVProfileListController {
 BOOL _ordered,_descending,_groupDescending;NSString *_selection,*_group,*_filterField,*_filterValue,*_primary;void(^_pick)(NSString*);
 NSMutableArray *_selected;NSArray *_keys,*_sections;UISearchController *_search;NSTimer *_timer;NSDate *_stamp;
}
- (instancetype)initForReserves { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_ordered=YES;_group=@"owner";NSArray *old=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][ASV_RESERVES];_selected=[NSMutableArray arrayWithArray:[old isKindOfClass:NSArray.class]?old:@[]];}return self; }
- (instancetype)initWithSelection:(NSString *)uuid completion:(void (^)(NSString *))completion { if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){_selection=uuid;_pick=[completion copy];_group=@"owner";}return self; }
- (NSArray *)records { NSArray *items=[NSArray arrayWithContentsOfFile:ASV_PROFILE_CATALOG];return [items isKindOfClass:NSArray.class]?items:@[]; }
- (NSString *)owner:(NSDictionary *)r { NSString *idValue=r[@"owner"];id proxy=[NSClassFromString(@"LSApplicationProxy") performSelector:@selector(applicationProxyForIdentifier:) withObject:idValue];NSString *name=[proxy respondsToSelector:@selector(itemName)]?[proxy performSelector:@selector(itemName)]:nil;return name.length?name:(idValue.length?idValue:L(@"Built-in VPN",@"Встроенный VPN")); }
- (void)viewDidLoad { [super viewDidLoad];self.title=_ordered?L(@"Reserve VPNs",@"Резервные VPN"):L(@"VPN profile",@"Профиль VPN");_search=[[UISearchController alloc] initWithSearchResultsController:nil];_search.searchResultsUpdater=self;_search.obscuresBackgroundDuringPresentation=NO;self.navigationItem.searchController=_search;self.navigationItem.hidesSearchBarWhenScrolling=NO;self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:L(@"Options",@"Параметры") style:UIBarButtonItemStylePlain target:self action:@selector(options)];[self rebuild]; }
- (void)viewWillAppear:(BOOL)animated { [super viewWillAppear:animated];_timer=[NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(refresh) userInfo:nil repeats:YES]; }
- (void)viewWillDisappear:(BOOL)animated { [_timer invalidate];_timer=nil;[super viewWillDisappear:animated]; }
- (void)dealloc { [_timer invalidate]; }
- (void)refresh { NSDate *stamp=[[NSFileManager defaultManager] attributesOfItemAtPath:ASV_PROFILE_CATALOG error:nil].fileModificationDate;if(![stamp isEqual:_stamp]){_stamp=stamp;[self rebuild];} }
- (void)updateSearchResultsForSearchController:(UISearchController *)controller { [self rebuild]; }
- (NSString *)valueFor:(NSDictionary *)record field:(NSString *)field {
 if([field isEqual:@"owner"])return [self owner:record];
 if([field isEqual:@"selected"])return (_ordered?[_selected containsObject:record[@"id"]]:[record[@"id"] isEqual:_selection])?L(@"Selected",@"Выбрано"):L(@"Not selected",@"Не выбрано");
 NSString *name=record[@"name"];return name.length?[[name substringToIndex:1] uppercaseString]:@"#";
}
- (void)rebuild {
 if(_ordered)_primary=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][ASV_PRIMARY];
 NSMutableDictionary *groups=[NSMutableDictionary dictionary];NSString *query=_search.searchBar.text.lowercaseString ?: @"";
 for(NSDictionary *r in [self records]) {
   if(_ordered && [r[@"id"] isEqual:_primary])continue;
   NSString *owner=[self owner:r],*name=r[@"name"];
   if(query.length && ![name.lowercaseString containsString:query] && ![owner.lowercaseString containsString:query])continue;
   if(_filterValue && ![[self valueFor:r field:_filterField] isEqual:_filterValue])continue;
   NSString *key=[_group isEqual:@"none"]?@"":[self valueFor:r field:_group];
   if(!groups[key])groups[key]=[NSMutableArray array];[groups[key] addObject:r];
 }
 _keys=[groups.allKeys sortedArrayUsingComparator:^NSComparisonResult(id a,id b){NSComparisonResult result=[a localizedCaseInsensitiveCompare:b];return self->_groupDescending?-result:result;}];
 NSMutableArray *sections=[NSMutableArray array];for(NSString *key in _keys)[sections addObject:[groups[key] sortedArrayUsingComparator:^NSComparisonResult(id a,id b){NSComparisonResult result=[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];return self->_descending?-result:result;}]];_sections=sections;[self.tableView reloadData];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table { return _sections.count+(_ordered?1:0); }
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)s { return _ordered && s==0?1:[_sections[s-(_ordered?1:0)] count]; }
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)s { if(_ordered && s==0)return L(@"Starting profile",@"Исходный профиль");return [_group isEqual:@"none"]?nil:_keys[s-(_ordered?1:0)]; }
- (NSInteger)tableView:(UITableView *)table sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index { return index+(_ordered?1:0); }
- (NSArray *)sectionIndexTitlesForTableView:(UITableView *)table { return [_group isEqual:@"name"]?_keys:nil; }
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)p {
 if(_ordered && p.section==0){
   UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"primary"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"primary"];
   cell.textLabel.text=L(@"Primary VPN",@"Основной VPN");NSString *name=nil;for(NSDictionary *r in [self records])if([r[@"id"] isEqual:_primary])name=r[@"name"];
   cell.detailTextLabel.text=name ?: L(@"System selection (auto)",@"Системный (авто)");cell.accessoryType=UITableViewCellAccessoryDisclosureIndicator;return cell;
 }
 UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"vpn"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"vpn"];
 NSDictionary *r=_sections[p.section-(_ordered?1:0)][p.row];NSUInteger position=[_selected indexOfObject:r[@"id"]];
 cell.textLabel.text=_ordered && position!=NSNotFound?[NSString stringWithFormat:@"%lu. %@",(unsigned long)position+1,r[@"name"]]:r[@"name"];
 cell.detailTextLabel.text=[self owner:r];cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
 cell.accessoryType=(_ordered?position!=NSNotFound:[r[@"id"] isEqual:_selection])?UITableViewCellAccessoryCheckmark:UITableViewCellAccessoryNone;
 cell.tintColor=UIColor.systemBlueColor;return cell;
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)p {
 if(_ordered && p.section==0){
   __weak ASVProfileListController *weakSelf=self;
   ASVProfileListController *picker=[[ASVProfileListController alloc] initWithSelection:_primary completion:^(NSString *uuid){
      ASVProfileListController *controller=weakSelf;if(!controller)return;
      NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];
      if(uuid.length)prefs[ASV_PRIMARY]=uuid;else [prefs removeObjectForKey:ASV_PRIMARY];
      [controller->_selected removeObject:uuid ?: @""];prefs[ASV_RESERVES]=controller->_selected;
      if([prefs writeToFile:ASV_PREFS atomically:YES]){notify_post(ASV_NOTIFY);[controller rebuild];}
   }];
   picker.navigationItem.leftBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:L(@"Auto",@"Авто") style:UIBarButtonItemStylePlain target:picker action:@selector(selectAutomaticPrimary)];
   [self.navigationController pushViewController:picker animated:YES];return;
 }
 NSString *uuid=_sections[p.section-(_ordered?1:0)][p.row][@"id"];
 if(!_ordered){if(_pick)_pick(uuid);[self.navigationController popViewControllerAnimated:YES];return;}
 if([_selected containsObject:uuid])[_selected removeObject:uuid];else {
   if(_selected.count>=64){UIAlertController *a=[UIAlertController alertControllerWithTitle:L(@"Up to 64 reserve profiles",@"Не более 64 резервных профилей") message:nil preferredStyle:UIAlertControllerStyleAlert];[a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];[self presentViewController:a animated:YES completion:nil];return;}
   [_selected addObject:uuid];
 }
 NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];prefs[ASV_RESERVES]=_selected;
 if([prefs writeToFile:ASV_PREFS atomically:YES])notify_post(ASV_NOTIFY);[self rebuild];
}
- (void)selectAutomaticPrimary { if(_pick)_pick(nil);[self.navigationController popViewControllerAnimated:YES]; }
- (void)sheet:(NSString *)title choices:(NSArray *)choices action:(void(^)(NSString*))action {
 UIAlertController *sheet=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
 for(NSArray *choice in choices)[sheet addAction:[UIAlertAction actionWithTitle:choice[1] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){action(choice[0]);}]];
 [sheet addAction:[UIAlertAction actionWithTitle:L(@"Cancel",@"Отмена") style:UIAlertActionStyleCancel handler:nil]];sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;[self presentViewController:sheet animated:YES completion:nil];
}
- (void)options {
 NSMutableArray *menu=[NSMutableArray arrayWithArray:@[@[@"group",L(@"Group",@"Группировка")],@[@"filter",L(@"Filter",@"Фильтр")],@[@"sort",L(@"Profiles order",@"Порядок профилей")]]];
 if(![_group isEqual:@"none"])[menu addObject:@[@"groupSort",L(@"Groups order",@"Порядок групп")]];
 [self sheet:L(@"Options",@"Параметры") choices:menu action:^(NSString *v){
   if([v isEqual:@"sort"] || [v isEqual:@"groupSort"])[self sheet:L(@"Sort",@"Сортировка") choices:@[@[@"asc",L(@"A–Z",@"А–Я")],@[@"desc",L(@"Z–A",@"Я–А")]] action:^(NSString *key){if([v isEqual:@"sort"])self->_descending=[key isEqual:@"desc"];else self->_groupDescending=[key isEqual:@"desc"];[self rebuild];}];
   else {
     BOOL filter=[v isEqual:@"filter"];
     NSMutableArray *fields=[NSMutableArray arrayWithArray:@[@[@"none",filter?L(@"All",@"Все"):L(@"Don't group",@"Не группировать")],@[@"owner",L(@"VPN app",@"VPN-приложение")],@[@"name",L(@"Alphabet",@"Алфавит")]]];
     if(self->_ordered)[fields addObject:@[@"selected",L(@"Selected / not selected",@"Выбрано / не выбрано")]];
     [self sheet:filter?L(@"Filter",@"Фильтр"):L(@"Group",@"Группировка") choices:fields action:^(NSString *field){
       if(!filter){self->_group=field;[self rebuild];return;}
       if([field isEqual:@"none"]){self->_filterField=nil;self->_filterValue=nil;[self rebuild];return;}
       NSMutableSet *values=[NSMutableSet set];for(NSDictionary *r in [self records])[values addObject:[self valueFor:r field:field]];
       NSMutableArray *choices=[NSMutableArray array];for(NSString *value in [values.allObjects sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)])[choices addObject:@[value,value]];
       [self sheet:L(@"Choose a filter",@"Выберите фильтр") choices:choices action:^(NSString *value){self->_filterField=field;self->_filterValue=value;[self rebuild];}];
     }];
   }
 }];
}
@end
