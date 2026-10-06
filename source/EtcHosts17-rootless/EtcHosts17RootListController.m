// EtcHosts17 Settings pane.
//
// Edits a desktop-style hosts list and compiles it into
// /var/jb/var/mobile/Library/EtcHosts17/hosts. The EtcHosts17 dylib inside
// mDNSResponder hands that file to mDNSResponder's own /etc/hosts engine, so the
// entries become local records answered before Wi-Fi / cellular DNS, DoH/DoT
// profiles and VPN DNS. Nothing here touches system DNS configuration: the only
// output is that one file, and without the dylib nothing reads it.

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <dns_sd.h>
#import <arpa/inet.h>
#import <errno.h>
#import <signal.h>
#import <stdio.h>
#import <sys/stat.h>
#import <unistd.h>

#define CRTScanlineView EH17ScanlineView
#import "CRTTheme.h"

static NSString *const EHDirectory = @"/var/jb/var/mobile/Library/EtcHosts17";
static NSString *const EHCompiledPath = @"/var/jb/var/mobile/Library/EtcHosts17/hosts";
static NSString *const EHPrefsPath = @"/var/mobile/Library/Preferences/com.ratush.etchosts17.plist";
static NSString *const EHKeyHosts = @"HostsText";
static NSString *const EHKeyEnabled = @"Enabled";
static NSString *const EHKeyDualStack = @"DualStack";
static NSString *const EHKeyPresets = @"Presets";
static NSString *const EHKeySelectedPreset = @"SelectedPreset";
static NSString *const EHKeyLanguage = @"Language";
static NSString *const EHKeyEditorHeight = @"EditorHeight";
static const char *EHReloadNotification = "com.ratush.etchosts17.reload";
static const char *EHStateNotification = "com.ratush.etchosts17.state";

enum { EHLoaded = 1, EHEngineOn = 2, EHNoFile = 4, EHNoSymbol = 8, EHDisabled = 16, EHRestarting = 32 };

#pragma mark - Localization

static NSString *gEHLang = nil;

static NSString *EHLang(void) {
	if ([gEHLang isEqualToString:@"ru"] || [gEHLang isEqualToString:@"en"]) return gEHLang;
	NSString *dev = [[NSLocale preferredLanguages].firstObject lowercaseString] ?: @"en";
	return [dev hasPrefix:@"ru"] ? @"ru" : @"en";
}

static NSString *EHL(NSString *key) {
	static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *S = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		S = @{
		  @"subtitle": @{@"en": @"native mDNSResponder hosts engine // beats DoH, DoT and VPN", @"ru": @"родной hosts-движок mDNSResponder // главнее DoH, DoT и VPN"},
		  @"nano": @{@"en": @"root@iphone:~# nano /etc/hosts", @"ru": @"root@iphone:~# nano /etc/hosts"},
		  @"engine": @{@"en": @"ENGINE", @"ru": @"ДВИЖОК"},
		  @"eng_on": @{@"en": @"active · mDNSResponder pid %d", @"ru": @"активен · mDNSResponder pid %d"},
		  @"eng_idle": @{@"en": @"off · nothing applied yet · stock mDNSResponder", @"ru": @"выкл · ещё ничего не применено · штатный mDNSResponder"},
		  @"eng_disabled": @{@"en": @"off · stock mDNSResponder (pid %d)", @"ru": @"выкл · штатный mDNSResponder (pid %d)"},
		  @"eng_restarting": @{@"en": @"restarting mDNSResponder as stock...", @"ru": @"перезапуск mDNSResponder в штатном режиме..."},
		  @"eng_nosym": @{@"en": @"unsupported mDNSResponder build · stock DNS", @"ru": @"неподдерживаемая сборка mDNSResponder · штатный DNS"},
		  @"eng_off": @{@"en": @"not loaded · stock DNS (reboot/rejailbreak?)", @"ru": @"не загружен · штатный DNS (перезагрузка/джейл?)"},
		  @"sw_enable": @{@"en": @"Enable hosts entries", @"ru": @"Включить записи hosts"},
		  @"sw_dual": @{@"en": @"Cover both IPv4 and IPv6", @"ru": @"Закрывать и IPv4, и IPv6"},
		  @"tip_engine": @{
		    @"en": @"iOS mDNSResponder ships Apple's full /etc/hosts engine but only switches it on in internal builds. The tweak starts that engine inside mDNSResponder and points it at the file compiled here. Entries become local records that mDNSResponder answers before it asks any DNS server, so they win over Wi-Fi/cellular DNS, DoH/DoT profiles and VPN DNS.\n\nNo system setting is changed. If the tweak is removed, injection is off or the jailbreak is gone, mDNSResponder simply starts as stock.",
		    @"ru": @"В mDNSResponder на iOS есть полноценный движок /etc/hosts от Apple, но включается он только во внутренних сборках. Твик запускает этот движок внутри mDNSResponder и подсовывает ему файл, собранный здесь. Записи становятся локальными, и mDNSResponder отвечает ими раньше, чем спрашивает любой DNS-сервер, поэтому они главнее DNS Wi-Fi/сотовой сети, DoH/DoT-профилей и DNS от VPN.\n\nНикакие системные настройки не меняются. Если твик удалён, инъекция выключена или джейла нет, mDNSResponder просто стартует штатно."},
		  @"tip_enable": @{
		    @"en": @"ON: the hosts engine starts inside mDNSResponder and your entries are live within about a second.\nOFF: mDNSResponder restarts once (about a second) and then runs fully stock: no hooks, no engine. Your text and presets stay saved.",
		    @"ru": @"ВКЛ: внутри mDNSResponder запускается hosts-движок, записи активны примерно через секунду.\nВЫКЛ: mDNSResponder один раз перезапускается (около секунды) и дальше работает полностью штатно: без перехватов и без движка. Текст и пресеты сохраняются."},
		  @"tip_dual": @{
		    @"en": @"Like hosts on Windows: a listed name is fully owned by your entry. For an IPv4-only entry the tweak adds the matching IPv6 record (::ffff:IP, or :: for 0.0.0.0) so the real AAAA answer cannot leak through, and for an IPv6-only entry it adds 0.0.0.0. Turn OFF for classic Unix behaviour where only the listed address family is overridden.",
		    @"ru": @"Как hosts в Windows: имя из списка полностью принадлежит вашей записи. Для записи только с IPv4 твик добавляет парную IPv6-запись (::ffff:IP, или :: для 0.0.0.0), чтобы настоящий AAAA-ответ не просочился, а для записи только с IPv6 добавляет 0.0.0.0. Выключите для классического Unix-поведения, где подменяется только указанное семейство адресов."},
		  @"footer": @{
		    @"en": @"IPv4/IPv6, several names per line, # comments. Apps that run their own DNS (Chrome Secure DNS, c-ares tools like curl) bypass the system resolver, as on a PC.",
		    @"ru": @"IPv4/IPv6, несколько имён в строке, # комментарии. Приложения со своим DNS (Chrome «Безопасный DNS», утилиты на c-ares вроде curl) обходят системный резолвер, как и на ПК."},
		  @"apply_btn": @{@"en": @"Apply", @"ru": @"Применить"},
		  @"done_on_title": @{@"en": @"Applied", @"ru": @"Применено"},
		  @"done_on_msg": @{@"en": @"hosts entries are live: %lu names.\nmDNSResponder pid %d answers them before DoH, DoT and VPN DNS.", @"ru": @"Записи hosts активны: имён %lu.\nmDNSResponder (pid %d) отвечает по ним раньше DoH, DoT и DNS из VPN."},
		  @"done_off_title": @{@"en": @"Disabled", @"ru": @"Выключено"},
		  @"done_off_msg": @{@"en": @"mDNSResponder runs as stock (pid %d). All names use normal DNS.", @"ru": @"mDNSResponder работает штатно (pid %d). Все имена резолвятся обычным DNS."},
		  @"done_wait_title": @{@"en": @"Saved, not confirmed", @"ru": @"Сохранено, но не подтверждено"},
		  @"done_wait_msg": @{@"en": @"The file was written, but mDNSResponder did not confirm within 20 s.\nEngine: %@", @"ru": @"Файл записан, но mDNSResponder не подтвердил применение за 20 с.\nДвижок: %@"},
		  @"st_applying": @{@"en": @"> applying: restarting mDNSResponder...", @"ru": @"> применение: перезапуск mDNSResponder..."},
		  @"done_noload_msg": @{@"en": @"The file was written, but the tweak is not loaded in mDNSResponder, so DNS stays stock. Re-jailbreak or reinstall the package.", @"ru": @"Файл записан, но твик не загружен в mDNSResponder, поэтому DNS работает штатно. Перезапустите джейл или переустановите пакет."},
		  @"show_btn": @{@"en": @"Show compiled hosts", @"ru": @"Показать собранный hosts"},
		  @"preset_prefix": @{@"en": @"PRESET: ", @"ru": @"ПРЕСЕТ: "},
		  @"preset_menu_title": @{@"en": @"Hosts presets", @"ru": @"Пресеты hosts"},
		  @"preset_add": @{@"en": @"Add new preset", @"ru": @"Добавить пресет"},
		  @"preset_rename": @{@"en": @"Rename current preset", @"ru": @"Переименовать пресет"},
		  @"preset_delete": @{@"en": @"Delete current preset", @"ru": @"Удалить пресет"},
		  @"cancel_btn": @{@"en": @"Cancel", @"ru": @"Отмена"},
		  @"save_btn": @{@"en": @"Save", @"ru": @"Сохранить"},
		  @"ok_btn": @{@"en": @"OK", @"ru": @"OK"},
		  @"newpreset_title": @{@"en": @"New preset", @"ru": @"Новый пресет"},
		  @"newpreset_msg": @{@"en": @"The current editor text will be saved into this preset.", @"ru": @"Текущий текст редактора будет сохранён в этот пресет."},
		  @"newpreset_ph": @{@"en": @"Preset name", @"ru": @"Название пресета"},
		  @"rename_title": @{@"en": @"Rename preset", @"ru": @"Переименовать пресет"},
		  @"rename_btn": @{@"en": @"Rename", @"ru": @"Переименовать"},
		  @"rename_exists": @{@"en": @"A preset with that name already exists.", @"ru": @"Пресет с таким именем уже существует."},
		  @"cantdelete_title": @{@"en": @"Cannot delete", @"ru": @"Нельзя удалить"},
		  @"cantdelete_msg": @{@"en": @"Keep at least one preset.", @"ru": @"Оставьте хотя бы один пресет."},
		  @"st_ready": @{@"en": @"> edit, then tap Apply", @"ru": @"> отредактируйте и нажмите «Применить»"},
		  @"st_applied": @{@"en": @"> applied: %lu names live", @"ru": @"> применено: активно имён %lu"},
		  @"st_disabled": @{@"en": @"> disabled: mDNSResponder back to stock", @"ru": @"> выключено: mDNSResponder возвращается к штатному"},
		  @"st_invalid": @{@"en": @"> invalid syntax; nothing applied", @"ru": @"> ошибка синтаксиса; ничего не применено"},
		  @"st_preset_loaded": @{@"en": @"> preset loaded; tap Apply to activate", @"ru": @"> пресет загружен; нажмите «Применить»"},
		  @"st_preset_saved": @{@"en": @"> preset saved; tap Apply to activate", @"ru": @"> пресет сохранён; нажмите «Применить»"},
		  @"st_write_failed": @{@"en": @"> could not write the hosts file", @"ru": @"> не удалось записать файл hosts"},
		  @"invalid_title": @{@"en": @"Invalid hosts syntax", @"ru": @"Неверный синтаксис hosts"},
		  @"invalid_more": @{@"en": @"\n...and %lu more.", @"ru": @"\n...и ещё %lu."},
		  @"invalid_line": @{@"en": @"Line %lu: invalid hostname \"%@\".", @"ru": @"Строка %lu: неверное имя хоста «%@»."},
		  @"invalid_syntax": @{@"en": @"Line %lu: use \"IP hostname [hostname ...]\".", @"ru": @"Строка %lu: формат «IP hostname [hostname ...]»."},
		  @"invalid_ip": @{@"en": @"Line %lu: invalid IP \"%@\".", @"ru": @"Строка %lu: неверный IP «%@»."},
		  @"write_title": @{@"en": @"Could not write hosts", @"ru": @"Не удалось записать hosts"},
		  @"compiled_title": @{@"en": @"Compiled hosts", @"ru": @"Собранный hosts"},
		  @"compiled_empty": @{@"en": @"No compiled file yet. Tap Apply first.", @"ru": @"Собранного файла ещё нет. Сначала нажмите «Применить»."},
		};
	});
	NSDictionary *entry = S[key];
	if (!entry) return key;
	return entry[EHLang()] ?: entry[@"en"] ?: key;
}

#pragma mark - Hosts compiler (pure functions)

static NSString *EHNormalize(NSString *text) {
	NSString *v = text ?: @"";
	v = [v stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	v = [v stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
	if (v.length && ![v hasSuffix:@"\n"]) v = [v stringByAppendingString:@"\n"];
	return v;
}

static NSArray<NSString *> *EHTokens(NSString *line) {
	NSUInteger c = [line rangeOfString:@"#"].location;
	NSString *code = c == NSNotFound ? line : [line substringToIndex:c];
	NSMutableArray *out = [NSMutableArray array];
	for (NSString *p in [code componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceCharacterSet]) if (p.length) [out addObject:p];
	return out;
}

static int EHFamily(NSString *ip) {
	const char *raw = ip.UTF8String;
	if (!raw || !raw[0]) return 0;
	struct in_addr a4; struct in6_addr a6;
	if (inet_pton(AF_INET, raw, &a4) == 1) return 4;
	if (inet_pton(AF_INET6, raw, &a6) == 1) return 6;
	return 0;
}

static BOOL EHIsStockName(NSString *name) {
	return [name isEqualToString:@"localhost"] || [name isEqualToString:@"broadcasthost"];
}

// Stock lines are always written first so localhost keeps working exactly as
// the retail daemon's hardcoded records do.
static NSString *const EHStockHeader =
	@"# Compiled by EtcHosts17. Edit in Settings, not here.\n"
	@"127.0.0.1\tlocalhost\n"
	@"255.255.255.255\tbroadcasthost\n"
	@"::1\tlocalhost\n";

// One "address<TAB>name" line per record. mDNSResponder treats extra names on a
// line as CNAME aliases; flattening keeps every name an address record.
static NSString *EHCompile(NSString *text, BOOL enabled, BOOL dualStack, NSUInteger *outNames) {
	NSMutableString *out = [NSMutableString stringWithString:EHStockHeader];
	if (outNames) *outNames = 0;
	if (!enabled) {
		[out appendString:@"# EtcHosts17 is disabled.\n"];
		return out;
	}
	NSMutableArray<NSString *> *order = [NSMutableArray array];
	NSMutableDictionary<NSString *, NSMutableOrderedSet<NSString *> *> *v4 = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, NSMutableOrderedSet<NSString *> *> *v6 = [NSMutableDictionary dictionary];
	for (NSString *line in [EHNormalize(text) componentsSeparatedByString:@"\n"]) {
		NSArray<NSString *> *t = EHTokens(line);
		if (t.count < 2) continue;
		int fam = EHFamily(t[0]);
		if (!fam) continue;
		for (NSUInteger i = 1; i < t.count; i++) {
			NSString *name = [t[i] lowercaseString];
			while ([name hasSuffix:@"."]) name = [name substringToIndex:name.length - 1];
			if (!name.length || EHIsStockName(name)) continue;
			if (!v4[name] && !v6[name]) [order addObject:name];
			NSMutableDictionary *bucket = fam == 4 ? v4 : v6;
			if (!bucket[name]) bucket[name] = [NSMutableOrderedSet orderedSet];
			[bucket[name] addObject:t[0]];
		}
	}
	[out appendString:@"# entries\n"];
	for (NSString *name in order) {
		for (NSString *ip in v4[name]) [out appendFormat:@"%@\t%@\n", ip, name];
		for (NSString *ip in v6[name]) [out appendFormat:@"%@\t%@\n", ip, name];
	}
	if (dualStack) {
		NSMutableString *pairs = [NSMutableString string];
		for (NSString *name in order) {
			if (v4[name].count && !v6[name].count) {
				for (NSString *ip in v4[name]) {
					NSString *mapped = [ip isEqualToString:@"0.0.0.0"] ? @"::" : [@"::ffff:" stringByAppendingString:ip];
					[pairs appendFormat:@"%@\t%@\n", mapped, name];
				}
			} else if (v6[name].count && !v4[name].count) {
				BOOL loop = [v6[name] containsObject:@"::1"];
				[pairs appendFormat:@"%@\t%@\n", loop ? @"127.0.0.1" : @"0.0.0.0", name];
			}
		}
		if (pairs.length) {
			[out appendString:@"# address-family counterparts (Cover both IPv4 and IPv6)\n"];
			[out appendString:pairs];
		}
	}
	if (outNames) *outNames = order.count;
	return out;
}

#pragma mark - Controller

@interface EtcHosts17RootListController : PSListController <UITextViewDelegate>
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *langButton;
@property (nonatomic, strong) UILabel *engineCaption;
@property (nonatomic, strong) UILabel *engineLabel;
@property (nonatomic, strong) UIView *engineDot;
@property (nonatomic, strong) UILabel *enableLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UILabel *dualLabel;
@property (nonatomic, strong) UISwitch *dualSwitch;
@property (nonatomic, strong) NSArray<UIButton *> *infoButtons;
@property (nonatomic, strong) UIButton *presetButton;
@property (nonatomic, strong) UILabel *nanoLabel;
@property (nonatomic, strong) UITextView *hostsTextView;
@property (nonatomic, strong) EH17ScanlineView *scanlines;
@property (nonatomic, strong) UIView *blockCursor;
@property (nonatomic, strong) UIView *resizeHandle;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSMutableArray<UIView *> *separators;
@property (nonatomic, strong) UIView *tooltipBubble;
@property (nonatomic, strong) UIControl *tooltipDismisser;
@property (nonatomic, assign) CGFloat editorHeight;
@property (nonatomic, assign) CGFloat resizeStartHeight;
@property (nonatomic, assign) BOOL applyingHighlight;
@property (nonatomic, assign) int stateToken;
@end

@implementation EtcHosts17RootListController

- (NSArray *)specifiers {
	if (!_specifiers) _specifiers = [self buildSpecifiers];
	return _specifiers;
}

- (NSMutableArray *)buildSpecifiers {
	PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
	[group setProperty:EHL(@"footer") forKey:@"footerText"];
	PSSpecifier *apply = [PSSpecifier preferenceSpecifierNamed:EHL(@"apply_btn") target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
	[apply setButtonAction:@selector(applyChanges)];
	PSSpecifier *show = [PSSpecifier preferenceSpecifierNamed:EHL(@"show_btn") target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
	[show setButtonAction:@selector(showCompiled)];
	return [NSMutableArray arrayWithObjects:group, apply, show, nil];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"/etc/hosts";
	self.view.backgroundColor = CRTBackground();
	self.view.tintColor = CRTGreen();
	self.table.backgroundColor = CRTBackground();
	self.table.separatorColor = [CRTBorder() colorWithAlphaComponent:0.35];
	self.table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
	self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	self.stateToken = -1;
	NSString *lang = [self prefs][EHKeyLanguage];
	gEHLang = ([lang isEqualToString:@"ru"] || [lang isEqualToString:@"en"]) ? lang : nil;
	[self buildHeader];
	[self loadEditor];
	__weak typeof(self) weakSelf = self;
	int token = -1;
	if (notify_register_dispatch(EHStateNotification, &token, dispatch_get_main_queue(), ^(__unused int t) { [weakSelf refreshEngineStatus]; }) == NOTIFY_STATUS_OK) {
		self.stateToken = token;
	}
	[self refreshEngineStatus];
}

- (void)dealloc {
	if (_stateToken >= 0) notify_cancel(_stateToken);
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self refreshEngineStatus];
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutHeader];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self saveEditorShowingError:NO];
}

#pragma mark Header

- (UIView *)addSeparator {
	UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
	line.backgroundColor = [CRTBorder() colorWithAlphaComponent:0.55];
	[self.header addSubview:line];
	[self.separators addObject:line];
	return line;
}

- (UIButton *)makeInfoButton:(NSInteger)tag {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	b.tag = tag;
	[b setImage:[UIImage systemImageNamed:@"info.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
	b.tintColor = CRTMidGreen();
	[b addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
	[self.header addSubview:b];
	return b;
}

- (void)buildHeader {
	UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MAX(self.table.bounds.size.width, 320.0), 600)];
	h.backgroundColor = CRTBackground();
	self.header = h;
	self.separators = [NSMutableArray array];

	self.titleLabel = CRTMakeLabel(19, YES, CRTGreen());
	self.titleLabel.text = @"/etc/hosts";
	[h addSubview:self.titleLabel];
	self.subtitleLabel = CRTMakeLabel(10.5, NO, CRTDimGreen());
	[h addSubview:self.subtitleLabel];

	self.langButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.langButton.titleLabel.font = CRTFont(12, YES);
	[self.langButton setTitleColor:CRTGreen() forState:UIControlStateNormal];
	self.langButton.layer.borderWidth = 1.0;
	self.langButton.layer.borderColor = [CRTBorder() colorWithAlphaComponent:0.7].CGColor;
	self.langButton.layer.cornerRadius = 5;
	[self.langButton addTarget:self action:@selector(toggleLanguage) forControlEvents:UIControlEventTouchUpInside];
	[h addSubview:self.langButton];

	self.engineCaption = CRTMakeLabel(12.5, YES, CRTMidGreen());
	[h addSubview:self.engineCaption];
	self.engineDot = [[UIView alloc] init];
	self.engineDot.layer.cornerRadius = 4;
	[h addSubview:self.engineDot];
	self.engineLabel = CRTMakeLabel(11.5, NO, CRTGreen());
	self.engineLabel.userInteractionEnabled = YES;
	[self.engineLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(refreshEngineStatus)]];
	[h addSubview:self.engineLabel];

	self.enableLabel = CRTMakeLabel(12.5, NO, CRTMidGreen());
	[h addSubview:self.enableLabel];
	self.enabledSwitch = CRTMakeSwitch(self, @selector(switchChanged:));
	[h addSubview:self.enabledSwitch];
	self.dualLabel = CRTMakeLabel(12.5, NO, CRTMidGreen());
	[h addSubview:self.dualLabel];
	self.dualSwitch = CRTMakeSwitch(self, @selector(switchChanged:));
	[h addSubview:self.dualSwitch];

	self.infoButtons = @[[self makeInfoButton:0], [self makeInfoButton:1], [self makeInfoButton:2]];

	self.presetButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.presetButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	self.presetButton.backgroundColor = CRTPanel();
	self.presetButton.layer.cornerRadius = 7;
	self.presetButton.layer.borderWidth = 1.0;
	self.presetButton.layer.borderColor = [CRTBorder() colorWithAlphaComponent:0.7].CGColor;
	self.presetButton.clipsToBounds = YES;
	[self.presetButton addTarget:self action:@selector(showPresetMenu) forControlEvents:UIControlEventTouchUpInside];
	[h addSubview:self.presetButton];

	self.nanoLabel = CRTMakeLabel(11, NO, CRTDimGreen());
	[h addSubview:self.nanoLabel];

	self.hostsTextView = CRTMakeEditor(self);
	[h addSubview:self.hostsTextView];
	self.blockCursor = [[UIView alloc] init];
	self.blockCursor.backgroundColor = [CRTGreen() colorWithAlphaComponent:0.65];
	self.blockCursor.userInteractionEnabled = NO;
	self.blockCursor.hidden = YES;
	[self.hostsTextView addSubview:self.blockCursor];
	CAKeyframeAnimation *blink = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
	blink.values = @[@1.0, @1.0, @0.0, @0.0];
	blink.keyTimes = @[@0.0, @0.5, @0.5, @1.0];
	blink.duration = 1.06;
	blink.repeatCount = HUGE_VALF;
	blink.calculationMode = kCAAnimationDiscrete;
	[self.blockCursor.layer addAnimation:blink forKey:@"blink"];

	self.scanlines = [[EH17ScanlineView alloc] initWithFrame:CGRectZero];
	[h addSubview:self.scanlines];

	self.resizeHandle = [[UIView alloc] init];
	UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 34, 4)];
	grip.tag = 7788;
	grip.backgroundColor = [CRTGreen() colorWithAlphaComponent:0.8];
	grip.layer.cornerRadius = 2;
	[self.resizeHandle addSubview:grip];
	[self.resizeHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)]];
	[h addSubview:self.resizeHandle];

	self.statusLabel = CRTMakeLabel(10.5, NO, CRTDimGreen());
	self.statusLabel.numberOfLines = 2;
	self.statusLabel.text = EHL(@"st_ready");
	[h addSubview:self.statusLabel];

	for (int i = 0; i < 5; i++) [self addSeparator];

	NSDictionary *prefs = [self prefs];
	NSNumber *savedHeight = prefs[EHKeyEditorHeight];
	self.editorHeight = ([savedHeight isKindOfClass:NSNumber.class] && savedHeight.doubleValue >= 100.0) ? savedHeight.doubleValue : 280.0;
	self.enabledSwitch.on = prefs[EHKeyEnabled] ? [prefs[EHKeyEnabled] boolValue] : YES;
	self.dualSwitch.on = prefs[EHKeyDualStack] ? [prefs[EHKeyDualStack] boolValue] : YES;

	self.table.tableHeaderView = h;
	[self relocalize];
}

- (void)relocalize {
	self.subtitleLabel.text = EHL(@"subtitle");
	self.nanoLabel.text = EHL(@"nano");
	self.engineCaption.text = EHL(@"engine");
	self.enableLabel.text = EHL(@"sw_enable");
	self.dualLabel.text = EHL(@"sw_dual");
	[self.langButton setTitle:[EHLang() isEqualToString:@"ru"] ? @"RU" : @"EN" forState:UIControlStateNormal];
	[self updatePresetButtonTitle];
	[self refreshEngineStatus];
	_specifiers = [self buildSpecifiers];
	[self reloadSpecifiers];
	[self layoutHeader];
}

- (void)layoutSwitchRow:(UILabel *)label switch:(UISwitch *)sw info:(UIButton *)info y:(CGFloat)y margin:(CGFloat)margin width:(CGFloat)contentWidth {
	CGFloat rowH = 32.0, visualW = 51.0 * 0.82;
	CGFloat swLeft = margin + contentWidth - visualW;
	sw.bounds = CGRectMake(0, 0, 51.0, 31.0);
	sw.center = CGPointMake(swLeft + visualW / 2.0, y + rowH / 2.0 + 1.5);
	info.frame = CGRectMake(swLeft - 30, y + rowH / 2.0 - 12.0, 24, 24);
	label.frame = CGRectMake(margin, y, swLeft - 34 - margin, rowH);
}

- (void)layoutHeader {
	if (!self.header) return;
	CGFloat width = self.table.bounds.size.width;
	if (width <= 0) width = self.view.bounds.size.width;
	CGFloat margin = 18.0;
	CGFloat cw = MAX(width - margin * 2.0, 240.0);
	NSUInteger sep = 0;

	CGFloat y = 10.0;
	self.titleLabel.frame = CGRectMake(margin, y, cw - 52, 24);
	self.langButton.frame = CGRectMake(margin + cw - 46, y + 1, 46, 22);
	y += 26;
	self.subtitleLabel.frame = CGRectMake(margin, y, cw, 15); y += 20;
	self.separators[sep++].frame = CGRectMake(0, y, width, 1); y += 6;

	CGFloat capW = [self.engineCaption.text sizeWithAttributes:@{NSFontAttributeName: self.engineCaption.font}].width + 4;
	self.engineCaption.frame = CGRectMake(margin, y, capW, 28);
	self.engineDot.frame = CGRectMake(margin + capW + 6, y + 10, 8, 8);
	self.infoButtons[0].frame = CGRectMake(margin + cw - 24, y + 2, 24, 24);
	self.engineLabel.frame = CGRectMake(margin + capW + 20, y, cw - capW - 20 - 30, 28);
	y += 30;
	self.separators[sep++].frame = CGRectMake(0, y, width, 1); y += 4;

	[self layoutSwitchRow:self.enableLabel switch:self.enabledSwitch info:self.infoButtons[1] y:y margin:margin width:cw]; y += 32;
	[self layoutSwitchRow:self.dualLabel switch:self.dualSwitch info:self.infoButtons[2] y:y margin:margin width:cw]; y += 36;
	CGFloat dualAlpha = self.enabledSwitch.on ? 1.0 : 0.45;
	self.dualSwitch.alpha = dualAlpha;
	self.dualLabel.alpha = dualAlpha;
	self.separators[sep++].frame = CGRectMake(0, y, width, 1); y += 8;

	self.presetButton.frame = CGRectMake(margin, y, cw, 30); y += 36;
	self.nanoLabel.frame = CGRectMake(margin, y, cw, 14); y += 18;

	CGFloat editorMargin = 10.0;
	CGFloat editorWidth = MAX(width - editorMargin * 2.0, 240.0);
	CGFloat available = self.table.bounds.size.height > 0 ? self.table.bounds.size.height : self.view.bounds.size.height;
	CGFloat editorH = self.editorHeight;
	CGFloat maxH = available - 160.0;
	if (editorH > maxH && maxH > 120.0) editorH = maxH;
	if (editorH < 100.0) editorH = 100.0;
	self.hostsTextView.frame = CGRectMake(editorMargin, y, editorWidth, editorH);
	self.scanlines.frame = self.hostsTextView.frame;
	self.resizeHandle.frame = CGRectMake(editorMargin, y + editorH - 11, editorWidth, 22);
	[self.resizeHandle viewWithTag:7788].frame = CGRectMake((editorWidth - 34) / 2.0, 9, 34, 4);
	y += editorH + 6;
	self.separators[sep++].frame = CGRectMake(0, y, width, 1); y += 5;
	self.statusLabel.frame = CGRectMake(margin, y, cw, 26); y += 28;

	CGRect f = self.header.frame;
	if (fabs(f.size.height - y) > 0.5 || fabs(f.size.width - width) > 0.5) {
		f.size.width = width;
		f.size.height = y;
		self.header.frame = f;
		self.table.tableHeaderView = self.header;
	}
	[self updateBlockCursor];
}

#pragma mark Engine status

static uint64_t EHReadEngineState(pid_t *outPid, BOOL *outAlive) {
	int token = -1;
	uint64_t state = 0;
	if (notify_register_check(EHStateNotification, &token) == NOTIFY_STATUS_OK) {
		notify_get_state(token, &state);
		notify_cancel(token);
	}
	pid_t pid = (pid_t)((state >> 16) & 0xffffffffULL);
	if (outPid) *outPid = pid;
	if (outAlive) *outAlive = pid > 0 && (kill(pid, 0) == 0 || errno == EPERM);
	return state;
}

- (void)refreshEngineStatus {
	pid_t pid = 0;
	BOOL alive = NO;
	uint64_t state = EHReadEngineState(&pid, &alive);
	UIColor *color;
	NSString *text;
	if (!(state & EHLoaded) || !alive) {
		color = CRTRed(); text = EHL(@"eng_off");
	} else if (state & EHNoSymbol) {
		color = CRTRed(); text = EHL(@"eng_nosym");
	} else if (state & EHEngineOn) {
		color = CRTGreen(); text = [NSString stringWithFormat:EHL(@"eng_on"), pid];
	} else if (state & EHRestarting) {
		color = CRTAmber(); text = EHL(@"eng_restarting");
	} else if (state & EHDisabled) {
		color = CRTDimGreen(); text = [NSString stringWithFormat:EHL(@"eng_disabled"), pid];
	} else {
		color = CRTAmber(); text = EHL(@"eng_idle");
	}
	self.engineDot.backgroundColor = color;
	self.engineLabel.textColor = color;
	self.engineLabel.text = text;
}

#pragma mark Tooltips

- (void)infoTapped:(UIButton *)sender {
	NSArray *keys = @[@"tip_engine", @"tip_enable", @"tip_dual"];
	if (sender.tag < 0 || sender.tag >= (NSInteger)keys.count) return;
	[self showTooltip:EHL(keys[sender.tag]) fromView:sender];
}

- (void)showTooltip:(NSString *)text fromView:(UIView *)anchor {
	[self hideTooltip];
	UIView *host = self.navigationController.view ?: self.view;
	CGFloat maxW = MIN(host.bounds.size.width - 32.0, 340.0);
	UILabel *lbl = [[UILabel alloc] init];
	lbl.numberOfLines = 0;
	lbl.font = CRTFont(12, NO);
	lbl.textColor = CRTGreen();
	lbl.text = text;
	CGSize sz = [lbl sizeThatFits:CGSizeMake(maxW - 20.0, CGFLOAT_MAX)];
	CGFloat w = sz.width + 20.0, h = sz.height + 16.0;
	UIView *bubble = [[UIView alloc] init];
	bubble.backgroundColor = [UIColor colorWithRed:0.02 green:0.08 blue:0.04 alpha:0.98];
	bubble.layer.borderColor = CRTGreen().CGColor;
	bubble.layer.borderWidth = 1.0;
	bubble.layer.cornerRadius = 8.0;
	bubble.userInteractionEnabled = NO;
	CGRect a = [anchor convertRect:anchor.bounds toView:host];
	CGFloat x = MIN(MAX(a.origin.x + a.size.width / 2.0 - w / 2.0, 12.0), host.bounds.size.width - 12.0 - w);
	CGFloat y = a.origin.y + a.size.height + 6.0;
	if (y + h > host.bounds.size.height - 12.0) y = MAX(a.origin.y - h - 6.0, 12.0);
	bubble.frame = CGRectMake(x, y, w, h);
	lbl.frame = CGRectMake(10.0, 8.0, w - 20.0, h - 16.0);
	[bubble addSubview:lbl];
	UIControl *dismiss = [[UIControl alloc] initWithFrame:host.bounds];
	[dismiss addTarget:self action:@selector(hideTooltip) forControlEvents:UIControlEventTouchUpInside];
	[host addSubview:dismiss];
	[host addSubview:bubble];
	self.tooltipDismisser = dismiss;
	self.tooltipBubble = bubble;
}

- (void)hideTooltip {
	[self.tooltipBubble removeFromSuperview];
	[self.tooltipDismisser removeFromSuperview];
	self.tooltipBubble = nil;
	self.tooltipDismisser = nil;
}

- (void)toggleLanguage {
	gEHLang = [EHLang() isEqualToString:@"ru"] ? @"en" : @"ru";
	NSMutableDictionary *p = [self mutablePrefs];
	p[EHKeyLanguage] = gEHLang;
	[self writePrefs:p];
	[self hideTooltip];
	[self relocalize];
}

#pragma mark Editor

- (void)updateBlockCursor {
	UITextView *tv = self.hostsTextView;
	if (!tv.isFirstResponder || !tv.selectedTextRange || !tv.selectedTextRange.empty) { self.blockCursor.hidden = YES; return; }
	self.blockCursor.hidden = NO;
	CGRect caret = [tv caretRectForPosition:tv.selectedTextRange.start];
	CGFloat charW = [@"M" sizeWithAttributes:@{NSFontAttributeName: CRTEditorFont()}].width;
	self.blockCursor.frame = CGRectMake(caret.origin.x, caret.origin.y, charW < 4 ? 8 : charW, caret.size.height);
}

- (void)handleResizePan:(UIPanGestureRecognizer *)pan {
	if (pan.state == UIGestureRecognizerStateBegan) self.resizeStartHeight = self.hostsTextView.frame.size.height;
	CGFloat h = self.resizeStartHeight + [pan translationInView:self.header].y;
	CGFloat available = self.table.bounds.size.height > 0 ? self.table.bounds.size.height : self.view.bounds.size.height;
	self.editorHeight = MIN(MAX(h, 100.0), available - 160.0);
	[self layoutHeader];
	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		NSMutableDictionary *p = [self mutablePrefs];
		p[EHKeyEditorHeight] = @(self.editorHeight);
		[self writePrefs:p];
	}
}

- (void)textViewDidChangeSelection:(UITextView *)textView { [self updateBlockCursor]; }
- (void)textViewDidBeginEditing:(UITextView *)textView { [self updateBlockCursor]; }
- (void)textViewDidEndEditing:(UITextView *)textView {
	self.blockCursor.hidden = YES;
	[self saveEditorShowingError:NO];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { if (scrollView == self.hostsTextView) [self updateBlockCursor]; }
- (void)textViewDidChange:(UITextView *)textView {
	[self applyHighlightingPreservingSelection:YES];
	[self updateBlockCursor];
}

- (void)applyHighlightingPreservingSelection:(BOOL)preserve {
	if (self.applyingHighlight) return;
	self.applyingHighlight = YES;
	NSRange sel = self.hostsTextView.selectedRange;
	NSString *text = self.hostsTextView.text ?: @"";
	NSMutableAttributedString *value = [[NSMutableAttributedString alloc] initWithString:text attributes:@{NSFontAttributeName: CRTEditorFont(), NSForegroundColorAttributeName: CRTMidGreen()}];
	static NSRegularExpression *tokenRegex;
	static dispatch_once_t once;
	dispatch_once(&once, ^{ tokenRegex = [NSRegularExpression regularExpressionWithPattern:@"\\S+" options:0 error:nil]; });
	[text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired usingBlock:^(__unused NSString *s, NSRange lineRange, __unused NSRange enc, __unused BOOL *stop) {
		NSString *line = [text substringWithRange:lineRange];
		NSUInteger hash = [line rangeOfString:@"#"].location;
		NSUInteger parseLen = line.length;
		if (hash != NSNotFound) {
			[value addAttribute:NSForegroundColorAttributeName value:CRTCommentGreen() range:NSMakeRange(lineRange.location + hash, line.length - hash)];
			parseLen = hash;
		}
		NSArray<NSTextCheckingResult *> *m = [tokenRegex matchesInString:line options:0 range:NSMakeRange(0, parseLen)];
		if (m.count) {
			NSRange ipRange = NSMakeRange(lineRange.location + m[0].range.location, m[0].range.length);
			BOOL ok = EHFamily([line substringWithRange:m[0].range]) != 0;
			[value addAttribute:NSForegroundColorAttributeName value:(ok ? CRTGreen() : CRTRed()) range:ipRange];
		}
	}];
	self.hostsTextView.attributedText = value;
	if (preserve && sel.location <= value.length) self.hostsTextView.selectedRange = sel;
	self.applyingHighlight = NO;
}

- (NSString *)defaultHostsText {
	return @"# One entry per line: IP  name [name ...]\n# 0.0.0.0 ads.example.com      # block\n# 203.0.113.7 my.server.lan    # pin\n";
}

- (void)loadEditor {
	NSString *text = [self prefs][EHKeyHosts];
	if (![text isKindOfClass:NSString.class] || !text.length) text = [self defaultHostsText];
	self.hostsTextView.text = text;
	[self updatePresetButtonTitle];
	[self applyHighlightingPreservingSelection:NO];
}

- (NSArray<NSString *> *)validationErrors:(NSString *)text {
	NSMutableArray<NSString *> *errors = [NSMutableArray array];
	static NSRegularExpression *domainShape;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		domainShape = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9_]([A-Za-z0-9_\\-]{0,61}[A-Za-z0-9_])?(\\.[A-Za-z0-9_]([A-Za-z0-9_\\-]{0,61}[A-Za-z0-9_])?)*\\.?$" options:0 error:nil];
	});
	NSArray<NSString *> *lines = [EHNormalize(text) componentsSeparatedByString:@"\n"];
	for (NSUInteger i = 0; i < lines.count; i++) {
		NSArray<NSString *> *t = EHTokens(lines[i]);
		if (!t.count) continue;
		unsigned long n = i + 1;
		if (t.count < 2) { [errors addObject:[NSString stringWithFormat:EHL(@"invalid_syntax"), n]]; continue; }
		if (!EHFamily(t[0])) { [errors addObject:[NSString stringWithFormat:EHL(@"invalid_ip"), n, t[0]]]; continue; }
		for (NSUInteger k = 1; k < t.count; k++) {
			if (t[k].length > 253 || [domainShape numberOfMatchesInString:t[k] options:0 range:NSMakeRange(0, t[k].length)] != 1)
				[errors addObject:[NSString stringWithFormat:EHL(@"invalid_line"), n, t[k]]];
		}
	}
	return errors;
}

- (void)showValidationErrors:(NSArray<NSString *> *)errors {
	NSUInteger limit = MIN(errors.count, (NSUInteger)8);
	NSString *msg = [[errors subarrayWithRange:NSMakeRange(0, limit)] componentsJoinedByString:@"\n"];
	if (errors.count > limit) msg = [msg stringByAppendingFormat:EHL(@"invalid_more"), (unsigned long)(errors.count - limit)];
	[self alert:EHL(@"invalid_title") message:msg];
}

#pragma mark Prefs

- (NSDictionary *)prefs {
	NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:EHPrefsPath];
	return [p isKindOfClass:NSDictionary.class] ? p : @{};
}

- (NSMutableDictionary *)mutablePrefs {
	NSMutableDictionary *p = [[self prefs] mutableCopy];
	// Drop keys that only the retired DNS-profile/daemon design used.
	for (NSString *k in @[@"GlobalMode", @"FallbackSystemDNS", @"CreateDNSProfile", @"UseDNSProfile", @"ProfileTransport", @"ProfileMode", @"ProfileUpstream",
	                     @"PBTransport", @"PBServer", @"PBAddrs", @"PBDomains", @"PBName", @"PBUseLocalCA", @"PBPort", @"PBDomainsHeight"]) [p removeObjectForKey:k];
	if (![p[EHKeySelectedPreset] isKindOfClass:NSString.class]) p[EHKeySelectedPreset] = @"Default";
	if (![p[EHKeyPresets] isKindOfClass:NSDictionary.class]) p[EHKeyPresets] = @{p[EHKeySelectedPreset]: p[EHKeyHosts] ?: [self defaultHostsText]};
	return p;
}

- (void)writePrefs:(NSDictionary *)p {
	[p writeToFile:EHPrefsPath atomically:YES];
}

- (BOOL)saveEditorShowingError:(BOOL)showError {
	NSString *text = EHNormalize(self.hostsTextView.text);
	NSArray *errors = [self validationErrors:text];
	if (errors.count) {
		self.statusLabel.text = EHL(@"st_invalid");
		if (showError) [self showValidationErrors:errors];
		return NO;
	}
	NSMutableDictionary *p = [self mutablePrefs];
	p[EHKeyHosts] = text;
	p[EHKeyEnabled] = @(self.enabledSwitch.on);
	p[EHKeyDualStack] = @(self.dualSwitch.on);
	NSMutableDictionary *presets = [p[EHKeyPresets] mutableCopy];
	presets[p[EHKeySelectedPreset]] = text;
	p[EHKeyPresets] = presets;
	[self writePrefs:p];
	return YES;
}

#pragma mark Apply

// Atomic replace: mDNSResponder watches the file and reloads it on its own.
- (BOOL)writeCompiled:(NSString *)compiled error:(NSError **)error {
	NSFileManager *fm = NSFileManager.defaultManager;
	if (![fm fileExistsAtPath:EHDirectory]) {
		if (![fm createDirectoryAtPath:EHDirectory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0755} error:error]) return NO;
	}
	NSString *tmp = [EHDirectory stringByAppendingPathComponent:@".hosts.tmp"];
	if (![compiled writeToFile:tmp atomically:NO encoding:NSUTF8StringEncoding error:error]) return NO;
	chmod(tmp.fileSystemRepresentation, 0644);
	if (rename(tmp.fileSystemRepresentation, EHCompiledPath.fileSystemRepresentation) != 0) {
		if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
		unlink(tmp.fileSystemRepresentation);
		return NO;
	}
	return YES;
}

- (void)applyEnabled:(BOOL)enabled showErrors:(BOOL)showErrors {
	NSUInteger names = 0;
	NSString *compiled = EHCompile(self.hostsTextView.text, enabled, self.dualSwitch.on, &names);
	NSError *error = nil;
	if (![self writeCompiled:compiled error:&error]) {
		self.statusLabel.text = EHL(@"st_write_failed");
		[self alert:EHL(@"write_title") message:error.localizedDescription ?: EHCompiledPath];
		return;
	}
	// Starts the engine if mDNSResponder came up before the file existed.
	notify_post(EHReloadNotification);
	self.statusLabel.text = enabled ? [NSString stringWithFormat:EHL(@"st_applied"), (unsigned long)names] : EHL(@"st_disabled");
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf refreshEngineStatus]; });
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ [weakSelf refreshEngineStatus]; });
	if (showErrors) [self confirmApplied:enabled names:names hash:EHHash16(compiled) attempt:0];
}

// Same fold of FNV-1a over the file bytes as the hook publishes in bits 48-63.
static uint16_t EHHash16(NSString *compiled) {
	NSData *d = [compiled dataUsingEncoding:NSUTF8StringEncoding];
	const uint8_t *p = d.bytes;
	uint32_t h = 2166136261u;
	for (NSUInteger i = 0; i < d.length; i++) { h ^= p[i]; h *= 16777619u; }
	return (uint16_t)((h >> 16) ^ h);
}

// mDNSResponder is launched on demand; opening a dns_sd connection starts it.
static void EHWakeResponder(void) {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		DNSServiceRef ref = NULL;
		if (DNSServiceCreateConnection(&ref) == kDNSServiceErr_NoError && ref) DNSServiceRefDeallocate(ref);
	});
}

// Polls the state word published by the hook until mDNSResponder reports the
// requested mode (and, when enabled, has loaded exactly this file), then tells
// the user what actually happened.
- (void)confirmApplied:(BOOL)enabled names:(NSUInteger)names hash:(uint16_t)hash attempt:(int)attempt {
	pid_t pid = 0;
	BOOL alive = NO;
	uint64_t state = EHReadEngineState(&pid, &alive);
	BOOL loaded = alive && (state & EHLoaded);
	BOOL settled = loaded && !(state & EHRestarting);
	if (settled && enabled && (state & EHEngineOn) && (uint16_t)(state >> 48) == hash) {
		[self refreshEngineStatus];
		self.statusLabel.text = [NSString stringWithFormat:EHL(@"st_applied"), (unsigned long)names];
		[self alert:EHL(@"done_on_title") message:[NSString stringWithFormat:EHL(@"done_on_msg"), (unsigned long)names, pid]];
		return;
	}
	if (settled && !enabled && !(state & EHEngineOn) && (state & (EHDisabled | EHNoFile))) {
		[self refreshEngineStatus];
		self.statusLabel.text = EHL(@"st_disabled");
		[self alert:EHL(@"done_off_title") message:[NSString stringWithFormat:EHL(@"done_off_msg"), pid]];
		return;
	}
	if (attempt >= 66) {
		[self refreshEngineStatus];
		if (!loaded) [self alert:EHL(@"done_wait_title") message:EHL(@"done_noload_msg")];
		else [self alert:EHL(@"done_wait_title") message:[NSString stringWithFormat:EHL(@"done_wait_msg"), self.engineLabel.text ?: @"?"]];
		return;
	}
	if (!alive || (state & EHRestarting)) {
		self.statusLabel.text = EHL(@"st_applying");
		[self refreshEngineStatus];
	}
	if (!alive && attempt % 3 == 0) EHWakeResponder();
	__weak typeof(self) weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
		[weakSelf confirmApplied:enabled names:names hash:hash attempt:attempt + 1];
	});
}

- (void)applyChanges {
	[self.view endEditing:YES];
	if (![self saveEditorShowingError:YES]) return;
	[self applyEnabled:self.enabledSwitch.on showErrors:YES];
}

- (void)switchChanged:(UISwitch *)sender {
	NSMutableDictionary *p = [self mutablePrefs];
	p[EHKeyEnabled] = @(self.enabledSwitch.on);
	p[EHKeyDualStack] = @(self.dualSwitch.on);
	[self writePrefs:p];
	[self layoutHeader];
	// Turning off must always work, even with a half-edited invalid text.
	if (!self.enabledSwitch.on) { [self applyEnabled:NO showErrors:NO]; return; }
	if ([self saveEditorShowingError:YES]) [self applyEnabled:YES showErrors:NO];
}

- (void)showCompiled {
	NSString *text = [NSString stringWithContentsOfFile:EHCompiledPath encoding:NSUTF8StringEncoding error:nil];
	if (!text.length) text = EHL(@"compiled_empty");
	if (text.length > 6000) text = [[text substringToIndex:6000] stringByAppendingString:@"\n..."];
	[self alert:EHL(@"compiled_title") message:text];
}

#pragma mark Presets

- (void)updatePresetButtonTitle {
	NSString *selected = [self mutablePrefs][EHKeySelectedPreset];
	NSString *titleText = [EHL(@"preset_prefix") stringByAppendingString:selected];
	UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
	config.attributedTitle = [[NSAttributedString alloc] initWithString:titleText attributes:@{NSFontAttributeName: CRTFont(13, YES), NSForegroundColorAttributeName: CRTGreen()}];
	config.image = [UIImage systemImageNamed:@"chevron.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightBold]];
	config.imagePlacement = NSDirectionalRectEdgeTrailing;
	config.imagePadding = 8.0;
	config.baseForegroundColor = CRTGreen();
	config.contentInsets = NSDirectionalEdgeInsetsMake(6, 11, 6, 11);
	self.presetButton.configuration = config;
}

- (void)showPresetMenu {
	[self saveEditorShowingError:NO];
	NSDictionary *presets = [self mutablePrefs][EHKeyPresets];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:EHL(@"preset_menu_title") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	for (NSString *name in [presets.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
		[sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [weakSelf loadPresetNamed:name]; }]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:EHL(@"preset_add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [weakSelf promptAddPreset]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:EHL(@"preset_rename") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) { [weakSelf promptRenamePreset]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:EHL(@"preset_delete") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *a) { [weakSelf deleteCurrentPreset]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:EHL(@"cancel_btn") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.presetButton;
	sheet.popoverPresentationController.sourceRect = self.presetButton.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)loadPresetNamed:(NSString *)name {
	NSMutableDictionary *p = [self mutablePrefs];
	NSString *text = p[EHKeyPresets][name];
	if (![text isKindOfClass:NSString.class]) return;
	self.hostsTextView.text = text;
	p[EHKeySelectedPreset] = name;
	p[EHKeyHosts] = text;
	[self writePrefs:p];
	[self updatePresetButtonTitle];
	[self applyHighlightingPreservingSelection:NO];
	self.statusLabel.text = EHL(@"st_preset_loaded");
}

- (void)promptAddPreset {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:EHL(@"newpreset_title") message:EHL(@"newpreset_msg") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.placeholder = EHL(@"newpreset_ph"); }];
	[alert addAction:[UIAlertAction actionWithTitle:EHL(@"cancel_btn") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	__weak UIAlertController *weakAlert = alert;
	[alert addAction:[UIAlertAction actionWithTitle:EHL(@"save_btn") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *name = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!name.length) return;
		__strong typeof(weakSelf) s = weakSelf;
		if (![s saveEditorShowingError:YES]) return;
		NSMutableDictionary *p = [s mutablePrefs];
		NSMutableDictionary *presets = [p[EHKeyPresets] mutableCopy];
		presets[name] = EHNormalize(s.hostsTextView.text);
		p[EHKeyPresets] = presets;
		p[EHKeySelectedPreset] = name;
		[s writePrefs:p];
		[s updatePresetButtonTitle];
		s.statusLabel.text = EHL(@"st_preset_saved");
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)promptRenamePreset {
	NSString *current = [self mutablePrefs][EHKeySelectedPreset];
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:EHL(@"rename_title") message:current preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = current; }];
	[alert addAction:[UIAlertAction actionWithTitle:EHL(@"cancel_btn") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	__weak UIAlertController *weakAlert = alert;
	[alert addAction:[UIAlertAction actionWithTitle:EHL(@"rename_btn") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		NSString *newName = [weakAlert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		__strong typeof(weakSelf) s = weakSelf;
		if (!newName.length || [newName isEqualToString:current]) return;
		NSMutableDictionary *p = [s mutablePrefs];
		NSMutableDictionary *presets = [p[EHKeyPresets] mutableCopy];
		if (presets[newName]) { [s alert:EHL(@"rename_title") message:EHL(@"rename_exists")]; return; }
		presets[newName] = presets[current] ?: EHNormalize(s.hostsTextView.text);
		[presets removeObjectForKey:current];
		p[EHKeyPresets] = presets;
		p[EHKeySelectedPreset] = newName;
		[s writePrefs:p];
		[s updatePresetButtonTitle];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteCurrentPreset {
	NSMutableDictionary *p = [self mutablePrefs];
	NSMutableDictionary *presets = [p[EHKeyPresets] mutableCopy];
	if (presets.count <= 1) { [self alert:EHL(@"cantdelete_title") message:EHL(@"cantdelete_msg")]; return; }
	[presets removeObjectForKey:p[EHKeySelectedPreset]];
	NSString *next = [[presets.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] firstObject];
	p[EHKeyPresets] = presets;
	p[EHKeySelectedPreset] = next;
	[self writePrefs:p];
	[self loadPresetNamed:next];
}

#pragma mark Table theming

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath { return 40.0; }
- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return section == 0 ? 6.0 : UITableViewAutomaticDimension; }

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([PSListController instancesRespondToSelector:@selector(tableView:willDisplayCell:forRowAtIndexPath:)]) [super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
	cell.backgroundColor = CRTPanel();
	cell.textLabel.font = CRTFont(15, YES);
	cell.textLabel.textColor = CRTGreen();
	UIView *selection = [[UIView alloc] initWithFrame:cell.bounds];
	selection.backgroundColor = [CRTBorder() colorWithAlphaComponent:0.25];
	cell.selectedBackgroundView = selection;
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([PSListController instancesRespondToSelector:@selector(tableView:willDisplayFooterView:forSection:)]) [super tableView:tableView willDisplayFooterView:view forSection:section];
	if ([view isKindOfClass:UITableViewHeaderFooterView.class]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.font = CRTFont(10.5, NO);
		footer.textLabel.textColor = CRTDimGreen();
	}
}

- (void)alert:(NSString *)title message:(NSString *)message {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:EHL(@"ok_btn") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

@end
