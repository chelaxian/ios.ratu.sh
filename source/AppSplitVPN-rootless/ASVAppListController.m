#import "ASVAppListController.h"
#import "Shared.h"
#import <notify.h>

@interface LSApplicationWorkspace : NSObject
+ (instancetype)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end
@interface LSApplicationProxy : NSObject
@property(readonly) NSString *applicationIdentifier;
@property(readonly) NSString *itemName;
@property(readonly) NSString *vendorName;
@property(readonly) NSString *genre;
@property(readonly) NSString *applicationType;
@property(readonly) NSURL *bundleURL;
@end
@interface UIImage (ASVPrivateIcons)
+ (UIImage *)_applicationIconImageForBundleIdentifier:(NSString *)identifier format:(int)format scale:(CGFloat)scale;
@end

static UIImage *ASVIcon(NSString *identifier) {
    static NSCache *icons;
    static dispatch_once_t once;
    dispatch_once(&once,^{ icons=[NSCache new]; });
    UIImage *icon=[icons objectForKey:identifier];
    if (icon) return icon;
    if ([UIImage respondsToSelector:@selector(_applicationIconImageForBundleIdentifier:format:scale:)])
        icon=[UIImage _applicationIconImageForBundleIdentifier:identifier format:0 scale:UIScreen.mainScreen.scale];
    if (!icon) icon=[UIImage systemImageNamed:@"app.dashed"];
    UIImage *source=icon;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(29,29)];
    icon=[renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context){ [source drawInRect:CGRectMake(0,0,29,29)]; }];
    [icons setObject:icon forKey:identifier];
    return icon;
}

static NSArray<NSDictionary *> *ASVCatalog(void) {
    static NSArray *cache;
    static NSDate *cachedAt;
    if (cache && [cachedAt timeIntervalSinceNow]>-60) return cache;
    @synchronized([ASVAppListController class]) {
        if (cache && [cachedAt timeIntervalSinceNow]>-60) return cache;
        NSMutableArray *records=[NSMutableArray array];
        id workspace=[NSClassFromString(@"LSApplicationWorkspace") defaultWorkspace];
        for (id proxy in [workspace allInstalledApplications]) {
            NSString *identifier=[proxy respondsToSelector:@selector(applicationIdentifier)] ? [proxy applicationIdentifier] : nil;
            if (!identifier.length) continue;
            NSString *name=[proxy respondsToSelector:@selector(itemName)] ? [proxy itemName] : nil;
            NSString *vendor=[proxy respondsToSelector:@selector(vendorName)] ? [proxy vendorName] : nil;
            NSString *category=[proxy respondsToSelector:@selector(genre)] ? [proxy genre] : nil;
            NSString *type=[proxy respondsToSelector:@selector(applicationType)] ? [proxy applicationType] : nil;
            NSURL *url=[proxy respondsToSelector:@selector(bundleURL)] ? [proxy bundleURL] : nil;
            BOOL installed=url && [NSBundle bundleWithURL:url].executablePath.length>0;
            BOOL expired=NO;
            if (installed && [type isEqualToString:@"User"]) {
                NSString *profile=[[url path] stringByAppendingPathComponent:@"embedded.mobileprovision"];
                NSData *raw=[NSData dataWithContentsOfFile:profile options:NSDataReadingMappedIfSafe error:nil];
                if (raw.length && raw.length<1024*1024) {
                    NSData *start=[@"<plist" dataUsingEncoding:NSUTF8StringEncoding];
                    NSData *end=[@"</plist>" dataUsingEncoding:NSUTF8StringEncoding];
                    NSRange a=[raw rangeOfData:start options:0 range:NSMakeRange(0,raw.length)];
                    if (a.location!=NSNotFound) {
                        NSRange b=[raw rangeOfData:end options:0 range:NSMakeRange(a.location,raw.length-a.location)];
                        if (b.location!=NSNotFound) {
                            NSData *xml=[raw subdataWithRange:NSMakeRange(a.location,NSMaxRange(b)+end.length-a.location)];
                            NSDictionary *plist=[NSPropertyListSerialization propertyListWithData:xml options:NSPropertyListImmutable format:NULL error:nil];
                            NSDate *expiration=plist[@"ExpirationDate"];
                            expired=[expiration isKindOfClass:NSDate.class] && [expiration timeIntervalSinceNow]<0;
                        }
                    }
                }
            }
            [records addObject:@{@"id":identifier,@"name":name.length?name:identifier,
                @"vendor":vendor.length?vendor:@"—",@"category":category.length?category:@"—",
                @"type":type.length?type:@"User",@"state":installed?(expired?@"profileExpired":@"installed"):@"offloaded"}];
        }
        cache=[records copy];
        cachedAt=[NSDate date];
    }
    return cache;
}

@interface ASVAppListController ()
@property(nonatomic,copy) NSString *listKey;
@property(nonatomic,copy) NSString *language;
@property(nonatomic,strong) NSMutableSet<NSString *> *selected;
@property(nonatomic,strong) NSArray<NSString *> *sectionNames;
@property(nonatomic,strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property(nonatomic,strong) UISearchController *searchController;
@property(nonatomic,copy) NSString *groupMode;
@property(nonatomic,copy) NSString *sortMode;
@property(nonatomic,copy) NSString *filterMode;
@end

@implementation ASVAppListController
+ (NSUInteger)installedApplicationCount { return ASVCatalog().count; }
- (NSString *)t:(NSString *)en ru:(NSString *)ru { return [_language isEqualToString:@"ru"]?ru:en; }
- (instancetype)initWithListKey:(NSString *)key language:(NSString *)language {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        _listKey=[key copy];_language=[language copy];_groupMode=@"name";_sortMode=@"asc";_filterMode=@"all";
        NSArray *saved=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][key];
        _selected=[NSMutableSet setWithArray:[saved isKindOfClass:NSArray.class]?saved:@[]];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _searchController=[[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater=self;
    _searchController.obscuresBackgroundDuringPresentation=NO;
    self.navigationItem.searchController=_searchController;
    self.navigationItem.hidesSearchBarWhenScrolling=NO;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:[self t:@"Options" ru:@"Параметры"] style:UIBarButtonItemStylePlain target:self action:@selector(showOptions)];
    [self rebuild];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self rebuild]; }
- (void)save {
    NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[_listKey]=[[_selected allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    if ([prefs writeToFile:ASV_PREFS atomically:YES]) notify_post(ASV_NOTIFY);
}
- (void)changed:(UISwitch *)sender {
    NSString *identifier=sender.accessibilityIdentifier;
    if (!identifier.length) return;
    if (sender.on) [_selected addObject:identifier]; else [_selected removeObject:identifier];
    [self save];[self rebuild];
}
- (void)rebuild {
    NSMutableArray<NSDictionary *> *all=[ASVCatalog() mutableCopy];
    NSMutableSet *known=[NSMutableSet set];
    for (NSDictionary *record in all) [known addObject:record[@"id"]];
    for (NSString *identifier in _selected) if (![known containsObject:identifier])
        [all addObject:@{@"id":identifier,@"name":identifier,@"vendor":@"—",@"category":@"—",@"type":@"User",@"state":@"deleted"}];
    NSString *query=_searchController.searchBar.text.lowercaseString ?: @"";
    NSMutableDictionary<NSString *,NSMutableArray *> *groups=[NSMutableDictionary dictionary];
    for (NSDictionary *record in all) {
        NSString *identifier=record[@"id"];
        BOOL selected=[_selected containsObject:identifier];
        NSString *displayName=record[@"name"];
        if (query.length && ![displayName.lowercaseString containsString:query] && ![identifier.lowercaseString containsString:query]) continue;
        if ([_filterMode isEqual:@"selected"] && !selected) continue;
        if ([_filterMode isEqual:@"unselected"] && selected) continue;
        if ([@[@"installed",@"offloaded",@"deleted",@"profileExpired"] containsObject:_filterMode] && ![record[@"state"] isEqual:_filterMode]) continue;
        if ([@[@"User",@"System"] containsObject:_filterMode] && ![record[@"type"] isEqual:_filterMode]) continue;
        NSString *group=@"";
        if ([_groupMode isEqual:@"name"]) {
            NSString *name=record[@"name"];
            group=name.length?[[name substringToIndex:1] uppercaseString]:@"#";
            if ([group rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location==NSNotFound) group=@"#";
        } else if ([_groupMode isEqual:@"vendor"]) group=record[@"vendor"];
        else if ([_groupMode isEqual:@"category"]) group=record[@"category"];
        else if ([_groupMode isEqual:@"state"]) group=[self stateLabel:record[@"state"]];
        else if ([_groupMode isEqual:@"type"]) group=record[@"type"];
        else if ([_groupMode isEqual:@"none"]) group=@"";
        else group=selected?[self t:@"Selected" ru:@"Выбрано"]:[self t:@"Not selected" ru:@"Не выбрано"];
        if (!groups[group]) groups[group]=[NSMutableArray array];
        [groups[group] addObject:record];
    }
    _sectionNames=[[groups allKeys] sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
        BOOL aa=!a.length || [a isEqual:@"—"] || [a isEqual:@"#"], bb=!b.length || [b isEqual:@"—"] || [b isEqual:@"#"];
        if (aa!=bb) return aa?NSOrderedDescending:NSOrderedAscending;
        return [a localizedCaseInsensitiveCompare:b];
    }];
    NSMutableArray *sections=[NSMutableArray array];
    for (NSString *name in _sectionNames) {
        NSArray *sorted=[groups[name] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
            BOOL aa=[self.selected containsObject:a[@"id"]], bb=[self.selected containsObject:b[@"id"]];
            if ([_sortMode isEqual:@"selectedFirst"] && aa!=bb) return aa?NSOrderedAscending:NSOrderedDescending;
            if ([_sortMode isEqual:@"selectedLast"] && aa!=bb) return aa?NSOrderedDescending:NSOrderedAscending;
            NSComparisonResult r=[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
            return [_sortMode isEqual:@"desc"] ? -r:r;
        }];
        [sections addObject:sorted];
    }
    _sections=[sections copy];
    self.title=[NSString stringWithFormat:@"%@ %lu/%lu",[_listKey isEqual:ASV_VPN]?@"VPN":@"DIRECT",(unsigned long)_selected.count,(unsigned long)ASVCatalog().count];
    [self.tableView reloadData];
}
- (NSString *)stateLabel:(NSString *)state {
    if ([state isEqual:@"installed"]) return [self t:@"Installed" ru:@"Установлено"];
    if ([state isEqual:@"offloaded"]) return [self t:@"Offloaded" ru:@"Выгружено"];
    if ([state isEqual:@"profileExpired"]) return [self t:@"Profile expired" ru:@"Срок профиля истёк"];
    return [self t:@"Deleted" ru:@"Удалено"];
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return _sections[section].count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    NSString *name=_sectionNames[section];
    if ([_groupMode isEqual:@"none"]) return nil;
    if ([name isEqual:@"—"]) return [_groupMode isEqual:@"vendor"]?[self t:@"Unknown developer" ru:@"Разработчик не указан"]:[self t:@"No category" ru:@"Без категории"];
    return name;
}
- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return [_groupMode isEqual:@"name"] ? _sectionNames:nil;
}
- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index { return index; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    NSDictionary *r=_sections[path.section][path.row];
    cell.textLabel.text=r[@"name"];
    cell.detailTextLabel.text=[NSString stringWithFormat:@"%@ · %@ · %@",r[@"id"],r[@"vendor"],[self stateLabel:r[@"state"]]];
    cell.imageView.image=ASVIcon(r[@"id"]);
    cell.imageView.layer.cornerRadius=6.5;cell.imageView.clipsToBounds=YES;
    NSString *symbol=nil;UIColor *tint=UIColor.secondaryLabelColor;
    if ([r[@"state"] isEqual:@"offloaded"]) { symbol=@"icloud.and.arrow.down";tint=UIColor.systemBlueColor; }
    else if ([r[@"state"] isEqual:@"deleted"]) { symbol=@"trash";tint=UIColor.systemRedColor; }
    else if ([r[@"state"] isEqual:@"profileExpired"]) { symbol=@"exclamationmark.shield";tint=UIColor.systemOrangeColor; }
    UISwitch *sw=[[UISwitch alloc] init];sw.accessibilityIdentifier=r[@"id"];
    sw.on=[_selected containsObject:r[@"id"]];[sw addTarget:self action:@selector(changed:) forControlEvents:UIControlEventValueChanged];
    [sw sizeToFit];
    if (symbol) {
        CGSize size=sw.bounds.size;
        UIImageView *badge=[[UIImageView alloc] initWithImage:[UIImage systemImageNamed:symbol]];
        badge.tintColor=tint;badge.contentMode=UIViewContentModeScaleAspectFit;
        badge.frame=CGRectMake(0,(size.height-20)/2,22,20);
        UIView *box=[[UIView alloc] initWithFrame:CGRectMake(0,0,30+size.width,size.height)];
        sw.frame=CGRectMake(30,0,size.width,size.height);
        [box addSubview:badge];[box addSubview:sw];cell.accessoryView=box;
    } else cell.accessoryView=sw;
    return cell;
}
- (void)choice:(NSString *)title options:(NSArray<NSArray<NSString *> *> *)choices field:(NSString *)field {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSArray *option in choices) [sheet addAction:[UIAlertAction actionWithTitle:option[1] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){
        [self setValue:option[0] forKey:field];[self rebuild];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Cancel" ru:@"Отмена"] style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)showOptions {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:[self t:@"List options" ru:@"Параметры списка"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Group" ru:@"Группировка"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        [self choice:[self t:@"Group by" ru:@"Группировать по"] options:@[@[@"none",[self t:@"Don't group" ru:@"Не группировать"]],@[@"name",[self t:@"Alphabet" ru:@"Алфавит"]],@[@"vendor",[self t:@"Developer" ru:@"Разработчик"]],@[@"category",[self t:@"Category" ru:@"Категория"]],@[@"type",[self t:@"User / system" ru:@"Пользовательское / системное"]],@[@"state",[self t:@"Installation state" ru:@"Состояние установки"]],@[@"selected",[self t:@"Selected / unselected" ru:@"Выбрано / не выбрано"]]] field:@"groupMode"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Sort" ru:@"Сортировка"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        [self choice:[self t:@"Sort by" ru:@"Сортировать по"] options:@[@[@"asc",[self t:@"Name A–Z" ru:@"Имя А–Я"]],@[@"desc",[self t:@"Name Z–A" ru:@"Имя Я–А"]],@[@"selectedFirst",[self t:@"Selected first" ru:@"Выбранные сначала"]],@[@"selectedLast",[self t:@"Selected last" ru:@"Выбранные в конце"]]] field:@"sortMode"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Filter" ru:@"Фильтр"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        [self choice:[self t:@"Show" ru:@"Показывать"] options:@[@[@"all",[self t:@"All" ru:@"Все"]],@[@"selected",[self t:@"Selected" ru:@"Выбранные"]],@[@"unselected",[self t:@"Not selected" ru:@"Не выбранные"]],@[@"installed",[self t:@"Installed" ru:@"Установленные"]],@[@"offloaded",[self t:@"Offloaded" ru:@"Выгруженные"]],@[@"deleted",[self t:@"Deleted" ru:@"Удалённые"]],@[@"profileExpired",[self t:@"Profile expired" ru:@"Срок профиля истёк"]],@[@"User",[self t:@"User apps" ru:@"Приложения пользователя"]],@[@"System",[self t:@"System apps" ru:@"Системные приложения"]]] field:@"filterMode"];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Cancel" ru:@"Отмена"] style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end
