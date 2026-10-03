#import "ASVAppListController.h"
#import "Shared.h"
#import "ASVProfileListController.h"
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

@interface ASVValuePicker : UITableViewController
@property(nonatomic,copy) NSArray<NSArray *> *values; // @[value,title,count]
@property(nonatomic,copy) void (^onPick)(NSString *value);
@end
@implementation ASVValuePicker
- (NSInteger)tableView:(UITableView *)t numberOfRowsInSection:(NSInteger)s { return _values.count; }
- (UITableViewCell *)tableView:(UITableView *)t cellForRowAtIndexPath:(NSIndexPath *)p {
    UITableViewCell *cell=[t dequeueReusableCellWithIdentifier:@"v"] ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"v"];
    cell.textLabel.text=_values[p.row][1];cell.detailTextLabel.text=[_values[p.row][2] description];
    return cell;
}
- (void)tableView:(UITableView *)t didSelectRowAtIndexPath:(NSIndexPath *)p {
    if (_onPick) _onPick(_values[p.row][0]);
    [self.navigationController popViewControllerAnimated:YES];
}
@end

@interface ASVAppListController ()
@property(nonatomic,copy) NSString *listKey;
@property(nonatomic,copy) NSString *language;
@property(nonatomic,strong) NSMutableSet<NSString *> *selected;
@property(nonatomic,strong) NSArray<NSString *> *sectionNames;
@property(nonatomic,strong) NSArray<NSArray<NSDictionary *> *> *sections;
@property(nonatomic,strong) UISearchController *searchController;
@property(nonatomic,copy) NSString *groupMode;
@property(nonatomic,copy) NSString *groupSort;
@property(nonatomic,copy) NSString *sortMode;
@property(nonatomic,copy) NSString *filterField;
@property(nonatomic,copy) NSString *filterValue;
@property(nonatomic,strong) NSMutableDictionary *matrix;
@end

@implementation ASVAppListController
+ (NSUInteger)installedApplicationCount { return ASVCatalog().count; }
+ (NSDictionary *)recordForIdentifier:(NSString *)identifier {
    for (NSDictionary *record in ASVCatalog()) if ([record[@"id"] isEqualToString:identifier]) return record;
    return nil;
}
- (NSString *)t:(NSString *)en ru:(NSString *)ru { return [_language isEqualToString:@"ru"]?ru:en; }
- (instancetype)initWithListKey:(NSString *)key language:(NSString *)language {
    if ((self=[super initWithStyle:UITableViewStyleInsetGrouped])) {
        _listKey=[key copy];_language=[language copy];_groupMode=@"name";_groupSort=@"asc";_sortMode=@"asc";
        id saved=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][key];
        if([key isEqual:ASV_MATRIX]) { _matrix=[NSMutableDictionary dictionaryWithDictionary:[saved isKindOfClass:NSDictionary.class]?saved:@{}];saved=_matrix.allKeys; }
        _selected=[NSMutableSet setWithArray:[saved isKindOfClass:NSArray.class]?saved:@[]];
    }
    return self;
}
- (void)viewDidLoad {
    [super viewDidLoad];
    _searchController=[[UISearchController alloc] initWithSearchResultsController:nil];
    _searchController.searchResultsUpdater=self;
    _searchController.obscuresBackgroundDuringPresentation=NO;
    self.definesPresentationContext=YES;
    self.navigationItem.searchController=_searchController;
    self.navigationItem.hidesSearchBarWhenScrolling=NO;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc] initWithTitle:[self t:@"Options" ru:@"Параметры"] style:UIBarButtonItemStylePlain target:self action:@selector(showOptions)];
    [self rebuild];
}
- (void)updateSearchResultsForSearchController:(UISearchController *)searchController { [self rebuild]; }
- (void)save {
    NSMutableDictionary *prefs=[[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] mutableCopy] ?: [NSMutableDictionary dictionary];
    prefs[_listKey]=_matrix ?: (id)[[_selected allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    if ([prefs writeToFile:ASV_PREFS atomically:YES]) notify_post(ASV_NOTIFY);
}
- (void)changed:(UISwitch *)sender {
    NSString *identifier=sender.accessibilityIdentifier;
    if (!identifier.length) return;
    if(_matrix && sender.on) { sender.on=NO;[self pickProfile:identifier];return; }
    if (sender.on) [_selected addObject:identifier]; else { [_selected removeObject:identifier];[_matrix removeObjectForKey:identifier]; }
    [self save];[self rebuild];
}
- (void)pickProfile:(NSString *)identifier {
    __weak typeof(self) weakSelf=self;
    ASVProfileListController *picker=[[ASVProfileListController alloc] initWithSelection:_matrix[identifier] completion:^(NSString *uuid){
        weakSelf.matrix[identifier]=uuid;[weakSelf.selected addObject:identifier];[weakSelf save];[weakSelf rebuild];
    }];
    [self.navigationController pushViewController:picker animated:YES];
}
- (NSString *)profileName:(NSString *)uuid {
    for(NSDictionary *r in [NSArray arrayWithContentsOfFile:ASV_PROFILE_CATALOG]) if([r[@"id"] isEqual:uuid]) return r[@"name"];
    return uuid.length?[self t:@"Profile unavailable" ru:@"Профиль недоступен"]:[self t:@"No VPN" ru:@"Без VPN"];
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)path {
    [tableView deselectRowAtIndexPath:path animated:YES];
    NSDictionary *record=[self recordAtIndexPath:path];
    if(_matrix && record)[self pickProfile:record[@"id"]];
}
- (NSDictionary *)recordAtIndexPath:(NSIndexPath *)path {
    if(path.section<0 || path.section>=(NSInteger)_sections.count)return nil;
    NSArray *rows=_sections[path.section];
    return path.row>=0 && path.row<(NSInteger)rows.count?rows[path.row]:nil;
}
- (NSString *)stateLabel:(NSString *)state {
    if ([state isEqual:@"installed"]) return [self t:@"Installed" ru:@"Установлено"];
    if ([state isEqual:@"offloaded"]) return [self t:@"Offloaded" ru:@"Выгружено"];
    if ([state isEqual:@"profileExpired"]) return [self t:@"Profile expired" ru:@"Срок профиля истёк"];
    return [self t:@"Deleted" ru:@"Удалено"];
}
- (NSArray<NSDictionary *> *)allRecords {
    NSMutableArray<NSDictionary *> *all=[ASVCatalog() mutableCopy];
    NSMutableSet *known=[NSMutableSet set];
    for (NSDictionary *record in all) [known addObject:record[@"id"]];
    for (NSString *identifier in _selected) if (![known containsObject:identifier])
        [all addObject:@{@"id":identifier,@"name":identifier,@"vendor":@"—",@"category":@"—",@"type":@"User",@"state":@"deleted"}];
    return all;
}
// Group/filter key of a record for a field. "—" and "#" mean "unnamed" and always go last.
- (NSString *)keyFor:(NSDictionary *)record field:(NSString *)field {
    if([field isEqual:@"vpnProfile"])return _matrix[record[@"id"]] ?: @"—";
    if ([field isEqual:@"name"]) {
        NSString *name=record[@"name"];
        NSString *letter=name.length?[[name substringToIndex:1] uppercaseString]:@"#";
        return [letter rangeOfCharacterFromSet:NSCharacterSet.letterCharacterSet].location==NSNotFound?@"#":letter;
    }
    if ([field isEqual:@"vendor"]) return record[@"vendor"];
    if ([field isEqual:@"category"]) return record[@"category"];
    if ([field isEqual:@"state"]) return [self stateLabel:record[@"state"]];
    if ([field isEqual:@"type"]) return [record[@"type"] isEqual:@"System"]?[self t:@"System" ru:@"Системные"]:[self t:@"User" ru:@"Пользовательские"];
    if ([field isEqual:@"selected"]) return [_selected containsObject:record[@"id"]]?[self t:@"Selected" ru:@"Выбрано"]:[self t:@"Not selected" ru:@"Не выбрано"];
    return @"";
}
- (NSString *)titleForKey:(NSString *)key field:(NSString *)field {
    if([field isEqual:@"vpnProfile"])return [self profileName:[key isEqual:@"—"]?nil:key];
    if ([key isEqual:@"—"]) return [field isEqual:@"vendor"]?[self t:@"Unknown developer" ru:@"Разработчик не указан"]:[self t:@"No category" ru:@"Без категории"];
    return key;
}
static BOOL ASVUnnamed(NSString *key) { return !key.length || [key isEqual:@"—"] || [key isEqual:@"#"]; }
- (NSArray<NSString *> *)sortedKeys:(NSArray<NSString *> *)keys descending:(BOOL)descending {
    return [self sortedKeys:keys descending:descending field:self.groupMode];
}
- (NSArray<NSString *> *)sortedKeys:(NSArray<NSString *> *)keys descending:(BOOL)descending field:(NSString *)field {
    return [keys sortedArrayUsingComparator:^NSComparisonResult(NSString *a,NSString *b){
        BOOL aa=ASVUnnamed(a), bb=ASVUnnamed(b);
        if (aa!=bb) return aa?NSOrderedDescending:NSOrderedAscending;
        NSComparisonResult r=[([field isEqual:@"vpnProfile"]?[self profileName:a]:a) localizedCaseInsensitiveCompare:([field isEqual:@"vpnProfile"]?[self profileName:b]:b)];
        return descending?-r:r;
    }];
}
- (void)rebuild {
    NSString *query=_searchController.searchBar.text.lowercaseString ?: @"";
    NSMutableDictionary<NSString *,NSMutableArray *> *groups=[NSMutableDictionary dictionary];
    for (NSDictionary *record in [self allRecords]) {
        NSString *identifier=record[@"id"];
        if (query.length && ![[record[@"name"] lowercaseString] containsString:query] && ![identifier.lowercaseString containsString:query]) continue;
        if (_filterField && ![[self keyFor:record field:_filterField] isEqualToString:_filterValue]) continue;
        NSString *group=[_groupMode isEqual:@"none"]?@"":[self keyFor:record field:_groupMode];
        if (!groups[group]) groups[group]=[NSMutableArray array];
        [groups[group] addObject:record];
    }
    NSArray *sectionNames=[self sortedKeys:groups.allKeys descending:[_groupSort isEqual:@"desc"]];
    NSString *mode=_sortMode;
    NSMutableArray *sections=[NSMutableArray array];
    for (NSString *name in sectionNames) {
        [sections addObject:[groups[name] sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
            int ra=0, rb=0; // rank: lower first
            if ([mode hasPrefix:@"selected"]) { ra=![self.selected containsObject:a[@"id"]];rb=![self.selected containsObject:b[@"id"]]; }
            else if ([mode hasPrefix:@"installed"]) { ra=![a[@"state"] isEqual:@"installed"];rb=![b[@"state"] isEqual:@"installed"]; }
            else if ([mode hasPrefix:@"user"]) { ra=[a[@"type"] isEqual:@"System"];rb=[b[@"type"] isEqual:@"System"]; }
            if ([mode hasSuffix:@"Last"]) { ra=!ra;rb=!rb; }
            if (ra!=rb) return ra<rb?NSOrderedAscending:NSOrderedDescending;
            NSComparisonResult r=[a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]];
            return [mode isEqual:@"desc"]?-r:r;
        }]];
    }
    // Publish matching names/rows without UIKit calls between them. Reload before
    // changing the header: setTableHeaderView synchronously queries cached sections.
    _sectionNames=sectionNames;
    _sections=[sections copy];
    [self.tableView reloadData];
    self.title=[NSString stringWithFormat:@"%@ %lu/%lu",_matrix?@"VPN MATRIX":([_listKey isEqual:ASV_VPN]?@"VPN":@"DIRECT"),(unsigned long)_selected.count,(unsigned long)ASVCatalog().count];
    [self updateFilterBanner];
}
- (void)updateFilterBanner {
    if (!_filterField) { if(self.tableView.tableHeaderView)self.tableView.tableHeaderView=nil;return; }
    UIButton *chip=[UIButton buttonWithType:UIButtonTypeSystem];
    UIButtonConfiguration *config=[UIButtonConfiguration tintedButtonConfiguration];
    config.title=[NSString stringWithFormat:@"%@: %@",[self fieldTitle:_filterField],[self titleForKey:_filterValue field:_filterField]];
    config.image=[UIImage systemImageNamed:@"xmark.circle.fill"];config.imagePlacement=NSDirectionalRectEdgeTrailing;config.imagePadding=6;
    config.cornerStyle=UIButtonConfigurationCornerStyleCapsule;
    chip.configuration=config;[chip addTarget:self action:@selector(clearFilter) forControlEvents:UIControlEventTouchUpInside];
    UIView *box=[[UIView alloc] initWithFrame:CGRectMake(0,0,self.tableView.bounds.size.width,48)];
    chip.translatesAutoresizingMaskIntoConstraints=NO;[box addSubview:chip];
    [NSLayoutConstraint activateConstraints:@[[chip.centerXAnchor constraintEqualToAnchor:box.centerXAnchor],[chip.centerYAnchor constraintEqualToAnchor:box.centerYAnchor],[chip.widthAnchor constraintLessThanOrEqualToAnchor:box.widthAnchor constant:-32]]];
    self.tableView.tableHeaderView=box;
}
- (void)clearFilter { _filterField=nil;_filterValue=nil;[self rebuild]; }
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return _sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section>=0 && section<(NSInteger)_sections.count?_sections[section].count:0; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if ([_groupMode isEqual:@"none"] || section<0 || section>=(NSInteger)_sectionNames.count) return nil;
    return [self titleForKey:_sectionNames[section] field:_groupMode];
}
- (NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView {
    return [_groupMode isEqual:@"name"] ? _sectionNames:nil;
}
- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index { return index; }
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)path {
    UITableViewCell *cell=[tableView dequeueReusableCellWithIdentifier:@"app"];
    if (!cell) cell=[[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"app"];
    NSDictionary *r=[self recordAtIndexPath:path];
    if(!r){cell.textLabel.text=nil;cell.detailTextLabel.text=nil;cell.imageView.image=nil;cell.accessoryView=nil;return cell;}
    cell.textLabel.text=r[@"name"];
    cell.detailTextLabel.text=_matrix && _matrix[r[@"id"]]?[NSString stringWithFormat:@"%@ · %@",r[@"id"],[self profileName:_matrix[r[@"id"]]]]:r[@"id"];
    cell.detailTextLabel.textColor=UIColor.secondaryLabelColor;
    cell.imageView.image=ASVIcon(r[@"id"]);
    cell.imageView.layer.cornerRadius=6.5;cell.imageView.clipsToBounds=YES;
    NSString *symbol=nil;UIColor *tint=UIColor.secondaryLabelColor;
    if ([r[@"state"] isEqual:@"offloaded"]) { symbol=@"icloud.and.arrow.down";tint=UIColor.systemBlueColor; }
    else if ([r[@"state"] isEqual:@"deleted"]) { symbol=@"trash";tint=UIColor.systemRedColor; }
    else if ([r[@"state"] isEqual:@"profileExpired"]) { symbol=@"exclamationmark.shield";tint=UIColor.systemOrangeColor; }
    UISwitch *sw=[[UISwitch alloc] init];sw.accessibilityIdentifier=r[@"id"];
    if(_matrix)sw.onTintColor=UIColor.systemBlueColor;
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
- (NSArray<NSArray<NSString *> *> *)fields {
    NSArray *fields=@[@[@"name",[self t:@"Alphabet" ru:@"Алфавит"]],@[@"vendor",[self t:@"Developer" ru:@"Разработчик"]],@[@"category",[self t:@"Category" ru:@"Категория"]],@[@"type",[self t:@"User / system" ru:@"Пользовательское / системное"]],@[@"state",[self t:@"Installation state" ru:@"Состояние установки"]],@[@"selected",[self t:@"Selected / unselected" ru:@"Выбрано / не выбрано"]]];
    return _matrix?[fields arrayByAddingObject:@[@"vpnProfile",[self t:@"VPN profile" ru:@"VPN-профиль"]]]:fields;
}
- (NSString *)fieldTitle:(NSString *)field {
    for (NSArray *f in [self fields]) if ([f[0] isEqual:field]) return f[1];
    return field;
}
- (void)sheet:(NSString *)title options:(NSArray<NSArray<NSString *> *> *)choices current:(NSString *)current pick:(void (^)(NSString *value))pick {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:title message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSArray *option in choices) {
        NSString *label=[option[0] isEqual:current]?[@"✓ " stringByAppendingString:option[1]]:option[1];
        [sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action){ pick(option[0]); }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Cancel" ru:@"Отмена"] style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
- (void)pickFilterValueForField:(NSString *)field {
    NSMutableDictionary<NSString *,NSNumber *> *counts=[NSMutableDictionary dictionary];
    for (NSDictionary *record in [self allRecords]) {
        NSString *key=[self keyFor:record field:field];
        counts[key]=@(counts[key].integerValue+1);
    }
    NSMutableArray *values=[NSMutableArray array];
    for (NSString *key in [self sortedKeys:counts.allKeys descending:NO field:field]) [values addObject:@[key,[self titleForKey:key field:field],counts[key]]];
    ASVValuePicker *picker=[[ASVValuePicker alloc] initWithStyle:UITableViewStyleInsetGrouped];
    picker.title=[self fieldTitle:field];picker.values=values;
    __weak typeof(self) weakSelf=self;
    picker.onPick=^(NSString *value){ weakSelf.filterField=field;weakSelf.filterValue=value;[weakSelf rebuild]; };
    [self.navigationController pushViewController:picker animated:YES];
}
- (void)showOptions {
    UIAlertController *sheet=[UIAlertController alertControllerWithTitle:[self t:@"List options" ru:@"Параметры списка"] message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Group" ru:@"Группировка"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        NSArray *options=[@[@[@"none",[self t:@"Don't group" ru:@"Не группировать"]]] arrayByAddingObjectsFromArray:[self fields]];
        [self sheet:[self t:@"Group by" ru:@"Группировать по"] options:options current:self.groupMode pick:^(NSString *v){ self.groupMode=v;[self rebuild]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Filter" ru:@"Фильтр"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        NSArray *options=[@[@[@"all",[self t:@"All" ru:@"Все"]]] arrayByAddingObjectsFromArray:[self fields]];
        [self sheet:[self t:@"Filter" ru:@"Фильтр"] options:options current:self.filterField ?: @"all" pick:^(NSString *v){
            if ([v isEqual:@"all"]) [self clearFilter]; else [self pickFilterValueForField:v];
        }];
    }]];
    if(![_groupMode isEqual:@"none"])[sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Sort groups" ru:@"Сортировка групп"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        [self sheet:[self t:@"Sort groups" ru:@"Сортировка групп"] options:@[@[@"asc",[self t:@"A–Z" ru:@"А–Я"]],@[@"desc",[self t:@"Z–A" ru:@"Я–А"]]] current:self.groupSort pick:^(NSString *v){ self.groupSort=v;[self rebuild]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Sort apps" ru:@"Сортировка приложений"] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a){
        [self sheet:[self t:@"Sort apps in groups" ru:@"Сортировка приложений в группах"] options:@[
            @[@"asc",[self t:@"Name A–Z" ru:@"Имя А–Я"]],@[@"desc",[self t:@"Name Z–A" ru:@"Имя Я–А"]],
            @[@"selectedFirst",[self t:@"Selected first" ru:@"Выбранные в начале"]],@[@"selectedLast",[self t:@"Selected last" ru:@"Выбранные в конце"]],
            @[@"installedFirst",[self t:@"Installed first" ru:@"Установленные в начале"]],@[@"installedLast",[self t:@"Installed last" ru:@"Установленные в конце"]],
            @[@"userFirst",[self t:@"User apps first" ru:@"Пользовательские в начале"]],@[@"userLast",[self t:@"User apps last" ru:@"Пользовательские в конце"]]]
            current:self.sortMode pick:^(NSString *v){ self.sortMode=v;[self rebuild]; }];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:[self t:@"Cancel" ru:@"Отмена"] style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.barButtonItem=self.navigationItem.rightBarButtonItem;
    [self presentViewController:sheet animated:YES completion:nil];
}
@end

