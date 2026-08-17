#import "ABPRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/Preferences.h>
#import <CoreFoundation/CFPreferences.h>
#import <notify.h>
#import <objc/runtime.h>

static NSString *const kDomain         = @"com.ratush.appabetical";
static NSString *const kNotifSortNow      = @"com.ratush.appabetical.sortnow";
static NSString *const kNotifReload       = @"com.ratush.appabetical.reload";
static NSString *const kNotifPresetSave   = @"com.ratush.appabetical.preset.save";
static NSString *const kNotifPresetApply  = @"com.ratush.appabetical.preset.apply";
static NSString *const kNotifPresetDelete = @"com.ratush.appabetical.preset.delete";
static NSString *const kNotifSortDone     = @"com.ratush.appabetical.sortdone";
static NSString *const kKeyLanguage       = @"appLanguage"; // "en" | "ru"

// Presets file lives in the SpringBoard-readable rootfs view.
static NSString *const kPresetsPath = @"/var/mobile/Library/SpringBoard/AppabeticalPresets.plist";
static NSString *const kPresetNameSentinel = @"/var/mobile/Library/SpringBoard/.appab_preset_name";
static int sSortDoneToken = 0;

// specifierAtIndexPath: is the authoritative section+row -> specifier mapping
// PSListController maintains. Declaring it here guarantees the call compiles
// regardless of the installed PSListController.h version. We route all row taps
// through it instead of flat-indexing the specifiers array, which is wrong the
// moment a group specifier splits the list into more than one section (as the
// presets controller does).
@interface PSListController (ABPrivate)
- (PSSpecifier *)specifierAtIndexPath:(NSIndexPath *)indexPath;
@end

// -----------------------------------------------------------------------------
// Localization. NSLocalizedStringFromTable uses [NSBundle mainBundle]
// (Preferences.app), which does NOT contain our strings, so the raw keys were
// showing up. We resolve the strings table from OUR bundle directly.
// -----------------------------------------------------------------------------

// Resolve our own preference bundle. The executable inside the bundle is
// ABPRootListController's class, so bundleForClass: points at our .bundle.
static NSBundle *ABOwnBundle(void) {
    static NSBundle *b = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        b = [NSBundle bundleForClass:[ABPRootListController class]];
    });
    return b;
}

// Load both language tables once (they are small). nil means "not loaded/empty".
static NSDictionary *ABTable(NSString *lang) {
    static NSDictionary *enTable = nil;
    static NSDictionary *ruTable = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBundle *b = ABOwnBundle();
        NSURL *enURL = [b URLForResource:@"Localizable" withExtension:@"strings" subdirectory:@"en.lproj"];
        if (!enURL) enURL = [b URLForResource:@"Localizable" withExtension:@"strings"];
        if (enURL) enTable = [NSDictionary dictionaryWithContentsOfURL:enURL];
        NSURL *ruURL = [b URLForResource:@"Localizable" withExtension:@"strings" subdirectory:@"ru.lproj"];
        if (ruURL) ruTable = [NSDictionary dictionaryWithContentsOfURL:ruURL];
    });
    if ([lang isEqualToString:@"ru"]) return ruTable;
    return enTable;
}

static NSString *ABRawLanguageSetting(void) {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)kKeyLanguage, (__bridge CFStringRef)kDomain));
    if (![v isKindOfClass:[NSString class]]) {
        v = [NSDictionary dictionaryWithContentsOfFile:
             @"/var/mobile/Library/Preferences/com.ratush.appabetical.plist"][kKeyLanguage];
    }
    if ([v isKindOfClass:[NSString class]]) {
        if ([v isEqualToString:@"en"] || [v isEqualToString:@"ru"]) return v;
    }
    return nil;
}

// Effective language: explicit pref > device language > en.
static NSString *ABEffectiveLanguage(void) {
    NSString *explicit = ABRawLanguageSetting();
    if (explicit.length) return explicit;
    NSArray *langs = [NSLocale preferredLanguages];
    NSString *first = langs.firstObject ?: @"en";
    if ([first hasPrefix:@"ru"]) return @"ru";
    return @"en";
}

// Translate a key using the effective language table; fall back to the key
// itself so we never render an empty string.
static NSString *ABL(NSString *key) {
    NSString *lang = ABEffectiveLanguage();
    NSDictionary *t = ABTable(lang) ?: ABTable(@"en");
    NSString *v = t[key];
    if ([v isKindOfClass:[NSString class]] && v.length) return v;
    // Fallback to English table, then to the raw key.
    NSDictionary *en = ABTable(@"en");
    if (lang != nil && en != t) {
        NSString *ev = en[key];
        if ([ev isKindOfClass:[NSString class]] && ev.length) return ev;
    }
    return key;
}

#pragma mark - Root controller

@implementation ABPRootListController

- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch([kNotifSortDone UTF8String], &sSortDoneToken, dispatch_get_main_queue(), ^(__unused int token) {
        [weakSelf dismissSortProgress];
    });
}

- (void)dealloc {
    if (sSortDoneToken) notify_cancel(sSortDoneToken);
}

- (NSString *)title {
    return ABL(@"app_name");
}

- (PSSpecifier *)toggleForKey:(NSString *)key title:(NSString *)title defaultBool:(BOOL)def {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:title
                                                    target:self
                                                       set:@selector(setPreferenceValue:specifier:)
                                                       get:@selector(readPreferenceValue:)
                                                    detail:nil
                                                      cell:PSSwitchCell
                                                      edit:nil];
    [s setProperty:kDomain forKey:@"defaults"];
    [s setProperty:key    forKey:@"key"];
    [s setProperty:@(def) forKey:@"default"];
    return s;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *specs = [NSMutableArray array];

    [specs addObject:[self toggleForKey:@"enabled"
                                   title:ABL(@"toggle_enabled")
                            defaultBool:YES]];

    [specs addObject:[self toggleForKey:@"placeOffloadedAtEnd"
                                   title:ABL(@"toggle_offloaded")
                            defaultBool:YES]];

    [specs addObject:[self toggleForKey:@"placeBookmarksAtEnd"
                                   title:ABL(@"toggle_bookmarks")
                            defaultBool:NO]];

    [specs addObject:[self toggleForKey:@"ignoreEmoji"
                                   title:ABL(@"toggle_emoji")
                            defaultBool:YES]];

    [specs addObject:[self toggleForKey:@"sortFolders"
                                   title:ABL(@"toggle_sortfolders")
                            defaultBool:YES]];

    [specs addObject:[self toggleForKey:@"sortInsideFolders"
                                   title:ABL(@"toggle_sortinside")
                            defaultBool:YES]];

    [specs addObject:[self toggleForKey:@"includeDock"
                                   title:ABL(@"toggle_dock")
                            defaultBool:NO]];

    [specs addObject:[self toggleForKey:@"autoSortOnRespring"
                                   title:ABL(@"toggle_autosort")
                            defaultBool:YES]];

    // Language selector. This deliberately opens a normal system menu instead
    // of cycling on tap, so the user gets an explicit RU/EN choice.
    PSSpecifier *lang = [PSSpecifier preferenceSpecifierNamed:ABL(@"label_language")
                                                      target:self
                                                         set:NULL
                                                         get:NULL
                                                      detail:nil
                                                        cell:PSButtonCell
                                                        edit:nil];
    [lang setButtonAction:@selector(showLanguageMenu)];
    [lang setProperty:@YES forKey:@"appabLanguageRow"];
    [specs addObject:lang];

    PSSpecifier *btn = [PSSpecifier preferenceSpecifierNamed:ABL(@"button_sortnow")
                                                      target:self
                                                         set:NULL
                                                         get:NULL
                                                      detail:nil
                                                        cell:PSButtonCell
                                                        edit:nil];
    [btn setButtonAction:@selector(sortNow)];
    [btn setProperty:@1 forKey:@"alignment"];
    [btn setProperty:@YES forKey:@"appabSortNowRow"];
    [specs addObject:btn];

    // Link to the Layout Presets sub-controller.
    PSSpecifier *presetsLink = [PSSpecifier preferenceSpecifierNamed:ABL(@"button_presets")
                                                              target:self
                                                                 set:NULL
                                                                 get:NULL
                                                              detail:[NSClassFromString(@"ABPPresetsController") class]
                                                                cell:PSLinkCell
                                                                edit:nil];
    [specs addObject:presetsLink];

    _specifiers = specs;
    return _specifiers;
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    notify_post([kNotifReload UTF8String]);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [super readPreferenceValue:specifier];
}

#pragma mark - Language menu

- (void)setLanguageCode:(NSString *)next {
    // File-backed debug trace (syslog is unreliable to read back here).
    NSString *logLine = [NSString stringWithFormat:@"%@ setLanguage next=%@\n", [NSDate date], next];
    [logLine writeToFile:@"/var/mobile/Library/SpringBoard/.appab_lang_debug.log" atomically:YES encoding:NSUTF8StringEncoding error:nil];

    CFPreferencesSetAppValue((__bridge CFStringRef)kKeyLanguage,
                             (__bridge CFPropertyListRef)next,
                             (__bridge CFStringRef)kDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    // Also drop it on the rootfs copy so the value is consistent everywhere.
    @try {
        NSString *p = @"/var/mobile/Library/Preferences/com.ratush.appabetical.plist";
        NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:p] ?: [NSMutableDictionary dictionary];
        d[kKeyLanguage] = next;
        [d writeToFile:p atomically:YES];
    } @catch (__unused id e) {}

    // Rebuild the whole specifiers list so every row re-translates.
    _specifiers = nil;
    [self reloadSpecifiers];
}

- (void)showLanguageMenu {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ABL(@"label_language")
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Русский (RU)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf setLanguageCode:@"ru"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"English (EN)"
                                              style:UIAlertActionStyleDefault
                                            handler:^(__unused UIAlertAction *action) {
        [weakSelf setLanguageCode:@"en"];
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:ABL(@"cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover) {
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        popover.permittedArrowDirections = 0;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

// Route button rows through the framework's own indexPath->specifier mapping.
// The previous code flat-indexed the specifiers array by indexPath.row, which
// mis-mapped rows (Sort Now resolved to the Language specifier), and it also
// relied on PSButtonCell/setButtonAction: alone, which is unreliable on iOS 17
// RootHide PreferenceLoader — so Sort Now either did nothing or triggered the
// wrong action. We now dispatch explicitly on per-row tags.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
    if ([[specifier propertyForKey:@"appabLanguageRow"] boolValue]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self showLanguageMenu];
        return;
    }
    if ([[specifier propertyForKey:@"appabSortNowRow"] boolValue]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self sortNow];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// Read a boolean pref with default. Used to gate Sort Now on the master toggle
// so the action visibly does nothing when the tweak is disabled.
- (BOOL)boolPref:(NSString *)key defaultValue:(BOOL)def {
    id v = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key, (__bridge CFStringRef)kDomain));
    if (![v respondsToSelector:@selector(boolValue)]) return def;
    return [v boolValue];
}

- (void)sortNow {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);

    // Every setting only takes effect when its toggle is on; Sort Now is gated
    // on the master "Enabled" toggle. If disabled, tell the user instead of
    // spinning a progress alert that resolves to a no-op.
    if (![self boolPref:@"enabled" defaultValue:YES]) {
        UIAlertController *off = [UIAlertController alertControllerWithTitle:ABL(@"app_name")
                                                                     message:ABL(@"alert_disabled")
                                                              preferredStyle:UIAlertControllerStyleAlert];
        [off addAction:[UIAlertAction actionWithTitle:ABL(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:off animated:YES completion:nil];
        return;
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ABL(@"app_name")
                                                                   message:ABL(@"alert_sorting")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    objc_setAssociatedObject(self, @selector(dismissSortProgress), alert, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self presentViewController:alert animated:YES completion:^{
        notify_post([kNotifSortNow UTF8String]);
    }];

    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [weakSelf dismissSortProgress];
    });
}

- (void)dismissSortProgress {
    UIAlertController *alert = objc_getAssociatedObject(self, @selector(dismissSortProgress));
    if (!alert) return;
    objc_setAssociatedObject(self, @selector(dismissSortProgress), nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (alert.presentingViewController) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }
}

@end

#pragma mark - Presets controller

@implementation ABPPresetsController {
    BOOL _loadedOnce;
    int _restoreDoneToken;
    UIAlertController *_restoreAlert;
}

- (NSString *)title {
    return ABL(@"presets_title");
}

// Restoring a preset triggers a SpringBoard respring, but Preferences.app is a
// separate process the respring does NOT restart — so the "Restoring…" alert
// this controller presents would otherwise stay on screen forever. SpringBoard
// posts kNotifSortDone right before it resprings (and on any apply failure), so
// we listen for it here and dismiss the alert. A timeout is the safety net for
// the case where the notification never arrives.
- (void)viewDidLoad {
    [super viewDidLoad];
    __weak typeof(self) weakSelf = self;
    notify_register_dispatch([kNotifSortDone UTF8String], &_restoreDoneToken, dispatch_get_main_queue(), ^(__unused int token) {
        [weakSelf dismissRestoreProgress];
    });
}

- (void)dealloc {
    if (_restoreDoneToken) notify_cancel(_restoreDoneToken);
}

- (void)dismissRestoreProgress {
    UIAlertController *alert = _restoreAlert;
    _restoreAlert = nil;
    if (alert.presentingViewController) {
        [alert dismissViewControllerAnimated:YES completion:nil];
    }
}

// Read presets from the rootfs file SpringBoard wrote. PreferenceLoader runs in
// Preferences.app, which sees the same rootfs view as SpringBoard for this
// path, so this is consistent.
- (NSDictionary *)presets {
    return [NSDictionary dictionaryWithContentsOfFile:kPresetsPath] ?: @{};
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;
    NSMutableArray *specs = [NSMutableArray array];

    // "Preserve CC layout" toggle: when ON, saving a preset also snapshots the
    // Control Center layout (toggle order + enabled/disabled module list), and
    // restoring a preset also restores that CC layout.
    PSSpecifier *ccToggle = [PSSpecifier preferenceSpecifierNamed:ABL(@"toggle_preservecc")
                                                          target:self
                                                             set:@selector(setPreferenceValue:specifier:)
                                                             get:@selector(readPreferenceValue:)
                                                          detail:nil
                                                            cell:PSSwitchCell
                                                            edit:nil];
    [ccToggle setProperty:kDomain forKey:@"defaults"];
    [ccToggle setProperty:@"preserveCC" forKey:@"key"];
    [ccToggle setProperty:@YES forKey:@"default"];
    [specs addObject:ccToggle];

    // "Save current layout as…" text-field action.
    PSSpecifier *saveSpec = [PSSpecifier preferenceSpecifierNamed:ABL(@"presets_save")
                                                           target:self
                                                              set:NULL
                                                              get:NULL
                                                           detail:nil
                                                             cell:PSButtonCell
                                                             edit:nil];
    [saveSpec setButtonAction:@selector(saveNewPreset)];
    [saveSpec setProperty:@1 forKey:@"alignment"];
    [saveSpec setProperty:@YES forKey:@"appabSaveRow"];
    [specs addObject:saveSpec];

    NSDictionary *presets = [self presets];
    NSArray *names = [presets.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    if (names.count) {
        PSSpecifier *group = [PSSpecifier groupSpecifierWithName:nil];
        [group setProperty:ABL(@"presets_saved_footer") forKey:@"footerText"];
        [specs addObject:group];
        for (NSString *name in names) {
            PSSpecifier *p = [PSSpecifier preferenceSpecifierNamed:name
                                                            target:self
                                                               set:NULL
                                                               get:NULL
                                                            detail:nil
                                                              cell:PSButtonCell
                                                              edit:nil];
            [p setButtonAction:@selector(applyPreset:)];
            [p setProperty:name forKey:@"name"];
            [specs addObject:p];
        }
    } else {
        PSSpecifier *empty = [PSSpecifier groupSpecifierWithName:nil];
        [empty setProperty:ABL(@"presets_empty_footer") forKey:@"footerText"];
        [specs addObject:empty];
    }

    _specifiers = specs;
    return _specifiers;
}

// Refresh the specifiers list AFTER the view has appeared and its table view is
// fully set up. Calling -reload / -reloadSpecifiers during the navigation push
// (in viewWillAppear) crashed Preferences with an estimatedHeight deref on a
// nil specifier array. We defer to the next runloop and only after the first
// appearance, so the initial load uses specifiers from -specifiers normally.
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_loadedOnce) {
        _specifiers = nil;
        [self reloadSpecifiers];
    }
    _loadedOnce = YES;
}

- (void)writePresetName:(NSString *)name {
    // Write to the rootfs-side sentinel SpringBoard reads. cfprefsd writes
    // land in the jbroot namespace, invisible to SpringBoard, so use a file.
    [@"" writeToFile:kPresetNameSentinel atomically:YES encoding:NSUTF8StringEncoding error:nil];
    [name writeToFile:kPresetNameSentinel atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

// The Preserve CC toggle lives on this controller, so it needs the same
// prefs-sync + reload-notification behavior as the root controller: every
// toggle write is mirrored into cfprefsd, synchronized, and a Darwin reload
// notification is posted so the live SpringBoard reads the new value before
// the next preset save/restore.
- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    notify_post([kNotifReload UTF8String]);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [super readPreferenceValue:specifier];
}

- (void)saveNewPreset {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ABL(@"presets_save_title")
                                                                   message:ABL(@"presets_save_msg")
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.placeholder = ABL(@"presets_save_placeholder");
    }];
    [alert addAction:[UIAlertAction actionWithTitle:ABL(@"cancel") style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) ws = self;
    [alert addAction:[UIAlertAction actionWithTitle:ABL(@"save") style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
        NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (!name.length) return;
        [ws writePresetName:name];
        notify_post([kNotifPresetSave UTF8String]);
        UIAlertController *done = [UIAlertController alertControllerWithTitle:ABL(@"app_name")
                                                                      message:[NSString stringWithFormat:ABL(@"presets_saved_done"), name]
                                                               preferredStyle:UIAlertControllerStyleAlert];
        [done addAction:[UIAlertAction actionWithTitle:ABL(@"ok") style:UIAlertActionStyleDefault handler:nil]];
        [ws presentViewController:done animated:YES completion:nil];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            __strong typeof(ws) s = ws;
            if (s) { s->_specifiers = nil; [s reloadSpecifiers]; }
        });
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)applyPreset:(PSSpecifier *)specifier {
    NSString *name = [specifier propertyForKey:@"name"];
    if (!name.length) return;
    [self writePresetName:name];
    notify_post([kNotifPresetApply UTF8String]);
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:ABL(@"app_name")
                                                                   message:[NSString stringWithFormat:ABL(@"presets_restoring"), name]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    _restoreAlert = alert;
    [self presentViewController:alert animated:YES completion:nil];
    // Safety net: dismiss even if SpringBoard never posts sortDone (e.g. it
    // died before posting). Normal success/failure dismisses far sooner via
    // the kNotifSortDone handler registered in viewDidLoad.
    __weak typeof(self) ws = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [ws dismissRestoreProgress];
    });
}

// Tapping a preset row restores it. The apply is dispatched here (via the
// framework's indexPath->specifier mapping) rather than through the row's
// PSButtonCell action, which is unreliable on iOS 17 RootHide PreferenceLoader.
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *sp = [self specifierAtIndexPath:indexPath];
    NSString *name = [sp propertyForKey:@"name"];
    if (name.length) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self applyPreset:sp];
        return;
    }
    if ([[sp propertyForKey:@"appabSaveRow"] boolValue]) {
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        [self saveNewPreset];
        return;
    }
    [super tableView:tableView didSelectRowAtIndexPath:indexPath];
}

// Delete the named preset from the shared file, then refresh the list. The
// file is written directly here (Preferences.app shares SpringBoard's rootfs
// view of this path — it already reads it to list presets) so the row is gone
// immediately with no async race against the SpringBoard notification. We also
// post the notification so any live SpringBoard state stays consistent; its
// handler is a harmless no-op once the key is already gone.
- (void)performDeletePreset:(NSString *)name {
    if (!name.length) return;
    NSMutableDictionary *presets = [NSMutableDictionary dictionaryWithContentsOfFile:kPresetsPath] ?: [NSMutableDictionary dictionary];
    if (presets[name]) {
        [presets removeObjectForKey:name];
        [presets writeToFile:kPresetsPath atomically:YES];
    }
    [self writePresetName:name];
    notify_post([kNotifPresetDelete UTF8String]);
    _specifiers = nil;
    [self reloadSpecifiers];
}

// Only preset rows (those carrying a "name") are editable; the Preserve CC
// toggle and the Save action are not. Section-aware via specifierAtIndexPath:.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *sp = [self specifierAtIndexPath:indexPath];
    return [[sp propertyForKey:@"name"] length] > 0;
}

// Red trailing swipe with a trash-can icon for deleting a preset. We rebuild
// the specifiers ourselves and return completion(NO) so PSListController's data
// source stays in sync (returning YES would make the table animate a delete
// against a row count we already changed, throwing an inconsistency exception).
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *sp = [self specifierAtIndexPath:indexPath];
    NSString *name = [sp propertyForKey:@"name"];
    if (!name.length) return nil;

    __weak typeof(self) ws = self;
    UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                      title:nil
                                                                    handler:^(UIContextualAction *action,
                                                                              UIView *sourceView,
                                                                              void (^completion)(BOOL)) {
        [ws performDeletePreset:name];
        completion(NO);
    }];
    del.image = [UIImage systemImageNamed:@"trash"];
    del.backgroundColor = [UIColor systemRedColor];
    UISwipeActionsConfiguration *cfg = [UISwipeActionsConfiguration configurationWithActions:@[del]];
    cfg.performsFirstActionWithFullSwipe = YES;
    return cfg;
}

// Fallback for the classic edit path (older PreferenceLoader table styles that
// call commitEditingStyle: instead of the swipe-actions delegate).
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    PSSpecifier *sp = [self specifierAtIndexPath:indexPath];
    [self performDeletePreset:[sp propertyForKey:@"name"]];
}

@end
