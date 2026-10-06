// DNS Profile Configurator Settings pane.
//
// Builds a standard encrypted-DNS configuration profile
// (com.apple.dnsSettings.managed) and hands it to iOS's own profile installer.
// Three modes:
//   DoT   - DNS-over-TLS server (ServerName + optional ServerAddresses)
//   DoH   - DNS-over-HTTPS server (ServerURL, custom port goes into the URL)
//   BLOCK - listed domains are routed to a DoT server at 127.0.0.1 where
//           nothing listens, so lookups for them fail.
// The profile is an ordinary, user-removable iOS profile. This tweak runs no
// daemon and changes nothing else.

#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <CommonCrypto/CommonDigest.h>
#import <arpa/inet.h>
#import <netinet/in.h>
#import <sys/socket.h>
#import <unistd.h>
#import <dlfcn.h>

#define CRTScanlineView DPCScanlineView
#import "CRTTheme.h"

static NSString *const DPCPrefsPath = @"/var/mobile/Library/Preferences/com.ratush.dnsprofileconfigurator.plist";
static NSString *const DPCIdentifierBase = @"com.ratush.dnsprofileconfigurator";

typedef NS_ENUM(NSInteger, DPCMode) { DPCModeDoT = 0, DPCModeDoH = 1, DPCModeBlock = 2 };

@interface MCProfileConnection : NSObject
+ (instancetype)sharedConnection;
- (id)queueFileDataForAcceptance:(NSData *)data originalFileName:(NSString *)name forBundleID:(NSString *)bundleID outError:(NSError **)error;
- (id)queueFileDataForAcceptance:(NSData *)data originalFileName:(NSString *)name outError:(NSError **)error;
@end

#pragma mark - Localization

static NSString *gDPCLang = nil;

static NSString *DPCLang(void) {
	if ([gDPCLang isEqualToString:@"ru"] || [gDPCLang isEqualToString:@"en"]) return gDPCLang;
	NSString *dev = [[NSLocale preferredLanguages].firstObject lowercaseString] ?: @"en";
	return [dev hasPrefix:@"ru"] ? @"ru" : @"en";
}

static NSString *DPCL(NSString *key) {
	static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *S = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		S = @{
		  @"subtitle": @{@"en": @"encrypted DNS profile builder // DoT · DoH · block", @"ru": @"конструктор профилей шифрованного DNS // DoT · DoH · блок"},
		  @"mode_dot": @{@"en": @"DoT", @"ru": @"DoT"},
		  @"mode_doh": @{@"en": @"DoH", @"ru": @"DoH"},
		  @"mode_block": @{@"en": @"BLOCK", @"ru": @"БЛОК"},
		  @"ph_server_dot": @{@"en": @"DoT server name, e.g. dns.google", @"ru": @"имя DoT-сервера, напр. dns.google"},
		  @"ph_server_doh": @{@"en": @"https://dns.google/dns-query", @"ru": @"https://dns.google/dns-query"},
		  @"ph_addrs": @{@"en": @"server IPs, comma separated (optional)", @"ru": @"IP сервера через запятую (необяз.)"},
		  @"ph_port_dot": @{@"en": @"port 853 (fixed by iOS for DoT)", @"ru": @"порт 853 (для DoT задан iOS)"},
		  @"ph_port_doh": @{@"en": @"port (default 443)", @"ru": @"порт (по умолчанию 443)"},
		  @"ph_name": @{@"en": @"profile name (optional)", @"ru": @"название профиля (необяз.)"},
		  @"cap_domains": @{@"en": @"// only these domains use the server (empty = all DNS)", @"ru": @"// через сервер идут только эти домены (пусто = весь DNS)"},
		  @"cap_block": @{@"en": @"// domains to block, one per line (required)", @"ru": @"// домены для блокировки, по одному в строке (обязательно)"},
		  @"block_note": @{@"en": @"// matched names go to DoT 127.0.0.1:853, nothing listens there, lookups fail", @"ru": @"// эти имена идут на DoT 127.0.0.1:853, там никто не слушает, запросы не проходят"},
		  @"preset_btn": @{@"en": @"KNOWN SERVERS", @"ru": @"ИЗВЕСТНЫЕ СЕРВЕРЫ"},
		  @"create_btn": @{@"en": @"Create & install profile", @"ru": @"Создать и установить профиль"},
		  @"tip_mode": @{
		    @"en": @"DoT: DNS-over-TLS. iOS always connects on port 853.\nDoH: DNS-over-HTTPS. A custom port is written into the server URL.\nBLOCK: the listed domains are sent to a DoT server at 127.0.0.1 where nothing listens, so those lookups fail and the sites stop opening.\n\nWith match domains only those names use the profile; everything else keeps normal DNS. iOS keeps one DNS profile active at a time: pick it in Settings > General > VPN & Device Management > DNS. Profiles stay installed until you remove them there, with or without this tweak.",
		    @"ru": @"DoT: DNS-over-TLS. iOS всегда подключается на порт 853.\nDoH: DNS-over-HTTPS. Свой порт вписывается в URL сервера.\nБЛОК: перечисленные домены отправляются на DoT-сервер 127.0.0.1, где никто не слушает, поэтому их резолвинг не проходит и сайты не открываются.\n\nЕсли заданы домены, профиль используют только они, остальное идёт обычным DNS. В iOS активен один DNS-профиль: выбор в Настройки > Основные > VPN и управление устройством > DNS. Профили остаются установленными, пока вы не удалите их там, с этим твиком или без него."},
		  @"footer": @{
		    @"en": @"After \"Create\", open Settings: a \"Profile Downloaded\" row appears at the top. Install it, then choose it under General > VPN & Device Management > DNS. Re-creating a profile with the same name updates it.",
		    @"ru": @"После «Создать» откройте главный экран Настроек: вверху появится «Профиль загружен». Установите его и выберите в Основные > VPN и управление устройством > DNS. Повторное создание профиля с тем же названием обновляет его."},
		  @"st_ready": @{@"en": @"> fill the fields, then Create", @"ru": @"> заполните поля и нажмите «Создать»"},
		  @"st_queued": @{@"en": @"> profile queued: Settings > Profile Downloaded", @"ru": @"> профиль в очереди: Настройки > Профиль загружен"},
		  @"st_safari": @{@"en": @"> handing the profile to Safari", @"ru": @"> передаю профиль в Safari"},
		  @"st_failed": @{@"en": @"> could not hand over the profile", @"ru": @"> не удалось передать профиль"},
		  @"err_title": @{@"en": @"Check the fields", @"ru": @"Проверьте поля"},
		  @"err_server_dot": @{@"en": @"Enter the DoT server host name (e.g. dns.google) or at least one server IP.", @"ru": @"Укажите имя DoT-сервера (напр. dns.google) или хотя бы один IP."},
		  @"err_server_doh": @{@"en": @"Enter a DoH URL starting with https://", @"ru": @"Укажите DoH URL, начинающийся с https://"},
		  @"err_addr": @{@"en": @"Not an IP address: %@", @"ru": @"Это не IP-адрес: %@"},
		  @"err_port": @{@"en": @"Port must be 1-65535.", @"ru": @"Порт должен быть 1-65535."},
		  @"err_domain": @{@"en": @"Line %lu: not a domain: %@", @"ru": @"Строка %lu: не домен: %@"},
		  @"err_block_empty": @{@"en": @"BLOCK mode needs at least one domain. An empty list would send all DNS to the dead server.", @"ru": @"Для режима БЛОК нужен хотя бы один домен. Пустой список отправил бы весь DNS на мёртвый сервер."},
		  @"queued_title": @{@"en": @"Profile ready", @"ru": @"Профиль готов"},
		  @"queued_msg": @{@"en": @"Go back to the main Settings screen and tap \"Profile Downloaded\" at the top to install it. Then choose it in General > VPN & Device Management > DNS.", @"ru": @"Вернитесь на главный экран Настроек и нажмите «Профиль загружен» вверху, чтобы установить его. Затем выберите его в Основные > VPN и управление устройством > DNS."},
		  @"fail_title": @{@"en": @"Could not open the installer", @"ru": @"Не удалось открыть установщик"},
		  @"ok_btn": @{@"en": @"OK", @"ru": @"OK"},
		  @"cancel_btn": @{@"en": @"Cancel", @"ru": @"Отмена"},
		};
	});
	NSDictionary *entry = S[key];
	if (!entry) return key;
	return entry[DPCLang()] ?: entry[@"en"] ?: key;
}

#pragma mark - Helpers

static NSString *DPCTrim(NSString *s) { return [s ?: @"" stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet]; }

static BOOL DPCIsIP(NSString *s) {
	struct in_addr a4; struct in6_addr a6;
	const char *c = s.UTF8String;
	return c && (inet_pton(AF_INET, c, &a4) == 1 || inet_pton(AF_INET6, c, &a6) == 1);
}

// Stable UUID from a string, so re-creating a profile with the same name
// replaces the installed one instead of adding a duplicate.
static NSString *DPCStableUUID(NSString *seed) {
	unsigned char d[CC_SHA256_DIGEST_LENGTH];
	NSData *data = [seed dataUsingEncoding:NSUTF8StringEncoding];
	CC_SHA256(data.bytes, (CC_LONG)data.length, d);
	d[6] = (d[6] & 0x0f) | 0x50;
	d[8] = (d[8] & 0x3f) | 0x80;
	return [[[NSUUID alloc] initWithUUIDBytes:d] UUIDString];
}

static NSString *DPCSlug(NSString *s) {
	NSMutableString *out = [NSMutableString string];
	for (NSUInteger i = 0; i < s.length; i++) {
		unichar c = [s characterAtIndex:i];
		if ((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) [out appendFormat:@"%C", c];
		else if (c >= 'A' && c <= 'Z') [out appendFormat:@"%C", (unichar)(c + 32)];
		else if (out.length && ![out hasSuffix:@"-"]) [out appendString:@"-"];
	}
	while ([out hasSuffix:@"-"]) [out deleteCharactersInRange:NSMakeRange(out.length - 1, 1)];
	return out.length ? out : DPCStableUUID(s).lowercaseString;
}

#pragma mark - One-shot localhost server (fallback installer)

// Serves one file to Safari, then closes. Used only if the native
// ManagedConfiguration queue is unavailable. Lives at most two minutes.
@interface DPCOneShotServer : NSObject
+ (NSURL *)serveData:(NSData *)data fileName:(NSString *)name;
@end

@implementation DPCOneShotServer
+ (NSURL *)serveData:(NSData *)data fileName:(NSString *)name {
	int s = socket(AF_INET, SOCK_STREAM, 0);
	if (s < 0) return nil;
	struct sockaddr_in addr = {0};
	addr.sin_len = sizeof(addr);
	addr.sin_family = AF_INET;
	addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
	addr.sin_port = 0;
	socklen_t len = sizeof(addr);
	if (bind(s, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(s, 4) != 0 || getsockname(s, (struct sockaddr *)&addr, &len) != 0) { close(s); return nil; }
	struct timeval tv = {.tv_sec = 120};
	setsockopt(s, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	UIApplication *app = UIApplication.sharedApplication;
	__block UIBackgroundTaskIdentifier task = [app beginBackgroundTaskWithExpirationHandler:^{ shutdown(s, SHUT_RDWR); }];
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
		// Safari may probe more than once; answer up to three requests.
		for (int served = 0; served < 3; served++) {
			int c = accept(s, NULL, NULL);
			if (c < 0) break;
			struct timeval ctv = {.tv_sec = 5};
			setsockopt(c, SOL_SOCKET, SO_RCVTIMEO, &ctv, sizeof(ctv));
			char buf[2048];
			(void)recv(c, buf, sizeof(buf), 0);
			NSString *head = [NSString stringWithFormat:@"HTTP/1.1 200 OK\r\nContent-Type: application/x-apple-aspen-config\r\nContent-Disposition: attachment; filename=\"%@\"\r\nContent-Length: %lu\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n", name, (unsigned long)data.length];
			NSData *h = [head dataUsingEncoding:NSUTF8StringEncoding];
			send(c, h.bytes, h.length, 0);
			send(c, data.bytes, data.length, 0);
			close(c);
		}
		close(s);
		dispatch_async(dispatch_get_main_queue(), ^{ [app endBackgroundTask:task]; task = UIBackgroundTaskInvalid; });
	});
	return [NSURL URLWithString:[NSString stringWithFormat:@"http://127.0.0.1:%d/%@", ntohs(addr.sin_port), name]];
}
@end

#pragma mark - Controller

@interface DPCRootListController : PSListController <UITextViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UIView *header;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIButton *langButton;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UIButton *modeInfo;
@property (nonatomic, strong) UIButton *presetButton;
@property (nonatomic, strong) UITextField *serverField;
@property (nonatomic, strong) UITextField *addrsField;
@property (nonatomic, strong) UITextField *portField;
@property (nonatomic, strong) UILabel *blockNote;
@property (nonatomic, strong) UILabel *domainsCaption;
@property (nonatomic, strong) UITextView *domainsView;
@property (nonatomic, strong) DPCScanlineView *scanlines;
@property (nonatomic, strong) UIView *resizeHandle;
@property (nonatomic, strong) UITextField *nameField;
@property (nonatomic, strong) UIButton *createButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) NSMutableArray<UIView *> *separators;
@property (nonatomic, strong) UIView *tooltipBubble;
@property (nonatomic, strong) UIControl *tooltipDismisser;
@property (nonatomic, assign) DPCMode mode;
@property (nonatomic, assign) CGFloat editorHeight;
@property (nonatomic, assign) CGFloat resizeStartHeight;
// Per-mode drafts so switching modes never loses what was typed.
@property (nonatomic, strong) NSMutableDictionary *drafts;
@end

@implementation DPCRootListController

- (NSArray *)specifiers {
	if (!_specifiers) _specifiers = [self buildSpecifiers];
	return _specifiers;
}

- (NSMutableArray *)buildSpecifiers {
	PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
	[group setProperty:DPCL(@"footer") forKey:@"footerText"];
	return [NSMutableArray arrayWithObject:group];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"DNS Profile Configurator";
	self.view.backgroundColor = CRTBackground();
	self.view.tintColor = CRTGreen();
	self.table.backgroundColor = CRTBackground();
	self.table.separatorColor = [CRTBorder() colorWithAlphaComponent:0.35];
	self.table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
	self.table.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
	NSDictionary *p = [self prefs];
	NSString *lang = p[@"Language"];
	gDPCLang = ([lang isEqualToString:@"ru"] || [lang isEqualToString:@"en"]) ? lang : nil;
	self.drafts = [p[@"Drafts"] isKindOfClass:NSDictionary.class] ? [self deepMutable:p[@"Drafts"]] : [NSMutableDictionary dictionary];
	NSInteger m = [p[@"Mode"] integerValue];
	self.mode = (m >= 0 && m <= 2) ? (DPCMode)m : DPCModeDoT;
	NSNumber *h = p[@"EditorHeight"];
	self.editorHeight = ([h isKindOfClass:NSNumber.class] && h.doubleValue >= 80.0) ? h.doubleValue : 170.0;
	[self buildHeader];
	[self loadDraftForMode:self.mode];
}

- (NSMutableDictionary *)deepMutable:(NSDictionary *)d {
	NSMutableDictionary *out = [NSMutableDictionary dictionary];
	for (NSString *k in d) out[k] = [d[k] isKindOfClass:NSDictionary.class] ? [d[k] mutableCopy] : d[k];
	return out;
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutHeader];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self saveDraft];
}

#pragma mark Prefs

- (NSDictionary *)prefs {
	NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:DPCPrefsPath];
	return [p isKindOfClass:NSDictionary.class] ? p : @{};
}

- (void)setPref:(id)value forKey:(NSString *)key {
	NSMutableDictionary *p = [[self prefs] mutableCopy];
	p[key] = value;
	[p writeToFile:DPCPrefsPath atomically:YES];
}

- (NSString *)modeKey:(DPCMode)m { return m == DPCModeDoH ? @"DoH" : (m == DPCModeBlock ? @"Block" : @"DoT"); }

- (void)saveDraft {
	NSMutableDictionary *d = [NSMutableDictionary dictionary];
	d[@"Server"] = self.serverField.text ?: @"";
	d[@"Addrs"] = self.addrsField.text ?: @"";
	d[@"Port"] = self.portField.text ?: @"";
	d[@"Domains"] = self.domainsView.text ?: @"";
	d[@"Name"] = self.nameField.text ?: @"";
	self.drafts[[self modeKey:self.mode]] = d;
	NSMutableDictionary *p = [[self prefs] mutableCopy];
	p[@"Drafts"] = self.drafts;
	p[@"Mode"] = @(self.mode);
	[p writeToFile:DPCPrefsPath atomically:YES];
}

- (void)loadDraftForMode:(DPCMode)m {
	NSDictionary *d = self.drafts[[self modeKey:m]];
	self.serverField.text = d[@"Server"] ?: @"";
	self.addrsField.text = d[@"Addrs"] ?: @"";
	self.portField.text = d[@"Port"] ?: @"";
	self.domainsView.text = d[@"Domains"] ?: @"";
	self.nameField.text = d[@"Name"] ?: @"";
	[self layoutHeader];
}

#pragma mark Header

- (void)buildHeader {
	UIView *h = [[UIView alloc] initWithFrame:CGRectMake(0, 0, MAX(self.table.bounds.size.width, 320.0), 600)];
	h.backgroundColor = CRTBackground();
	self.header = h;
	self.separators = [NSMutableArray array];

	self.titleLabel = CRTMakeLabel(19, YES, CRTGreen());
	self.titleLabel.text = @"DNS Profile Configurator";
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

	self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"DoT", @"DoH", @"BLOCK"]];
	self.modeControl.selectedSegmentIndex = self.mode;
	[self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
	[h addSubview:self.modeControl];

	self.modeInfo = [UIButton buttonWithType:UIButtonTypeSystem];
	[self.modeInfo setImage:[UIImage systemImageNamed:@"info.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular]] forState:UIControlStateNormal];
	self.modeInfo.tintColor = CRTMidGreen();
	[self.modeInfo addTarget:self action:@selector(infoTapped:) forControlEvents:UIControlEventTouchUpInside];
	[h addSubview:self.modeInfo];

	self.presetButton = CRTMakePanelButton(self, @selector(showPresets));
	[h addSubview:self.presetButton];

	self.serverField = CRTMakeField(self);
	self.serverField.keyboardType = UIKeyboardTypeURL;
	[h addSubview:self.serverField];
	self.addrsField = CRTMakeField(self);
	self.addrsField.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
	[h addSubview:self.addrsField];
	self.portField = CRTMakeField(self);
	self.portField.keyboardType = UIKeyboardTypeNumberPad;
	[h addSubview:self.portField];

	self.blockNote = CRTMakeLabel(10.5, NO, CRTAmber());
	self.blockNote.numberOfLines = 2;
	[h addSubview:self.blockNote];

	self.domainsCaption = CRTMakeLabel(10.5, NO, CRTCommentGreen());
	[h addSubview:self.domainsCaption];
	self.domainsView = CRTMakeEditor(self);
	[h addSubview:self.domainsView];
	self.scanlines = [[DPCScanlineView alloc] initWithFrame:CGRectZero];
	[h addSubview:self.scanlines];
	self.resizeHandle = [[UIView alloc] init];
	UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 34, 4)];
	grip.tag = 7790;
	grip.backgroundColor = [CRTGreen() colorWithAlphaComponent:0.8];
	grip.layer.cornerRadius = 2;
	[self.resizeHandle addSubview:grip];
	[self.resizeHandle addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)]];
	[h addSubview:self.resizeHandle];

	self.nameField = CRTMakeField(self);
	self.nameField.autocapitalizationType = UITextAutocapitalizationTypeSentences;
	[h addSubview:self.nameField];

	self.createButton = CRTMakePanelButton(self, @selector(createTapped));
	[h addSubview:self.createButton];

	self.statusLabel = CRTMakeLabel(10.5, NO, CRTDimGreen());
	self.statusLabel.numberOfLines = 2;
	self.statusLabel.text = DPCL(@"st_ready");
	[h addSubview:self.statusLabel];

	for (int i = 0; i < 4; i++) {
		UIView *line = [[UIView alloc] init];
		line.backgroundColor = [CRTBorder() colorWithAlphaComponent:0.55];
		[h addSubview:line];
		[self.separators addObject:line];
	}
	self.table.tableHeaderView = h;
	[self relocalize];
}

- (void)relocalize {
	self.subtitleLabel.text = DPCL(@"subtitle");
	[self.langButton setTitle:[DPCLang() isEqualToString:@"ru"] ? @"RU" : @"EN" forState:UIControlStateNormal];
	[self.createButton setTitle:DPCL(@"create_btn") forState:UIControlStateNormal];
	[self.presetButton setTitle:[DPCL(@"preset_btn") stringByAppendingString:@"  \u25BE"] forState:UIControlStateNormal];
	self.blockNote.text = DPCL(@"block_note");
	_specifiers = [self buildSpecifiers];
	[self reloadSpecifiers];
	[self layoutHeader];
}

- (void)layoutHeader {
	if (!self.header) return;
	CGFloat width = self.table.bounds.size.width;
	if (width <= 0) width = self.view.bounds.size.width;
	CGFloat margin = 18.0, cw = MAX(width - margin * 2.0, 240.0), fh = 30.0;
	BOOL block = self.mode == DPCModeBlock, doh = self.mode == DPCModeDoH;
	NSUInteger sep = 0;
	CRTThemeSegment(self.modeControl, @[DPCL(@"mode_dot"), DPCL(@"mode_doh"), DPCL(@"mode_block")]);

	CGFloat y = 10.0;
	self.titleLabel.frame = CGRectMake(margin, y, cw - 52, 24);
	self.langButton.frame = CGRectMake(margin + cw - 46, y + 1, 46, 22);
	y += 26;
	self.subtitleLabel.frame = CGRectMake(margin, y, cw, 15); y += 20;
	self.separators[sep++].frame = CGRectMake(0, y, width, 1); y += 8;

	self.modeControl.frame = CGRectMake(margin, y, cw - 30, fh);
	self.modeInfo.frame = CGRectMake(margin + cw - 24, y + 3, 24, 24);
	y += fh + 8;

	self.presetButton.hidden = block;
	self.serverField.hidden = block;
	self.addrsField.hidden = block;
	self.portField.hidden = block;
	self.blockNote.hidden = !block;
	if (block) {
		self.blockNote.frame = CGRectMake(margin, y, cw, 30); y += 34;
	} else {
		self.presetButton.frame = CGRectMake(margin, y, cw, fh); y += fh + 6;
		CRTSetPlaceholder(self.serverField, DPCL(doh ? @"ph_server_doh" : @"ph_server_dot"));
		self.serverField.frame = CGRectMake(margin, y, cw, fh); y += fh + 6;
		CRTSetPlaceholder(self.addrsField, DPCL(@"ph_addrs"));
		self.addrsField.frame = CGRectMake(margin, y, cw, fh); y += fh + 6;
		CRTSetPlaceholder(self.portField, DPCL(doh ? @"ph_port_doh" : @"ph_port_dot"));
		self.portField.enabled = doh;
		self.portField.alpha = doh ? 1.0 : 0.45;
		if (!doh) self.portField.text = @"";
		self.portField.frame = CGRectMake(margin, y, cw, fh); y += fh + 8;
	}
	self.separators[sep++].frame = CGRectMake(0, y, width, 1); y += 6;

	self.domainsCaption.text = DPCL(block ? @"cap_block" : @"cap_domains");
	self.domainsCaption.frame = CGRectMake(margin, y, cw, 14); y += 18;
	CGFloat em = 10.0, ew = MAX(width - em * 2.0, 240.0);
	CGFloat eh = MAX(self.editorHeight, 80.0);
	self.domainsView.frame = CGRectMake(em, y, ew, eh);
	self.scanlines.frame = self.domainsView.frame;
	self.resizeHandle.frame = CGRectMake(em, y + eh - 11, ew, 22);
	[self.resizeHandle viewWithTag:7790].frame = CGRectMake((ew - 34) / 2.0, 9, 34, 4);
	y += eh + 8;

	CRTSetPlaceholder(self.nameField, DPCL(@"ph_name"));
	self.nameField.frame = CGRectMake(margin, y, cw, fh); y += fh + 8;
	self.createButton.frame = CGRectMake(margin, y, cw, 34); y += 40;
	self.separators[sep++].frame = CGRectMake(0, y, width, 1); y += 5;
	self.statusLabel.frame = CGRectMake(margin, y, cw, 26); y += 28;

	CGRect f = self.header.frame;
	if (fabs(f.size.height - y) > 0.5 || fabs(f.size.width - width) > 0.5) {
		f.size.width = width;
		f.size.height = y;
		self.header.frame = f;
		self.table.tableHeaderView = self.header;
	}
}

#pragma mark Actions

- (void)modeChanged:(UISegmentedControl *)seg {
	[self.view endEditing:YES];
	[self saveDraft];
	self.mode = (DPCMode)seg.selectedSegmentIndex;
	[self setPref:@(self.mode) forKey:@"Mode"];
	[self loadDraftForMode:self.mode];
}

- (void)toggleLanguage {
	gDPCLang = [DPCLang() isEqualToString:@"ru"] ? @"en" : @"ru";
	[self setPref:gDPCLang forKey:@"Language"];
	[self hideTooltip];
	[self relocalize];
}

- (void)handleResizePan:(UIPanGestureRecognizer *)pan {
	if (pan.state == UIGestureRecognizerStateBegan) self.resizeStartHeight = self.domainsView.frame.size.height;
	CGFloat avail = self.table.bounds.size.height > 0 ? self.table.bounds.size.height : self.view.bounds.size.height;
	self.editorHeight = MIN(MAX(self.resizeStartHeight + [pan translationInView:self.header].y, 80.0), avail - 200.0);
	[self layoutHeader];
	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) [self setPref:@(self.editorHeight) forKey:@"EditorHeight"];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField { [textField resignFirstResponder]; return YES; }
- (void)textFieldDidEndEditing:(UITextField *)textField { [self saveDraft]; }
- (void)textViewDidEndEditing:(UITextView *)textView { [self saveDraft]; }

- (void)showPresets {
	// name, DoT ServerName, DoH URL, addresses
	NSArray<NSArray<NSString *> *> *known = @[
		@[@"Cloudflare 1.1.1.1", @"one.one.one.one", @"https://cloudflare-dns.com/dns-query", @"1.1.1.1, 1.0.0.1, 2606:4700:4700::1111"],
		@[@"Google", @"dns.google", @"https://dns.google/dns-query", @"8.8.8.8, 8.8.4.4, 2001:4860:4860::8888"],
		@[@"Quad9", @"dns.quad9.net", @"https://dns.quad9.net/dns-query", @"9.9.9.9, 149.112.112.112, 2620:fe::fe"],
		@[@"AdGuard DNS", @"dns.adguard-dns.com", @"https://dns.adguard-dns.com/dns-query", @"94.140.14.14, 94.140.15.15"],
		@[@"Control D (free, unfiltered)", @"p0.freedns.controld.com", @"https://freedns.controld.com/p0", @"76.76.2.0, 76.76.10.0"],
		@[@"NextDNS (anycast)", @"dns.nextdns.io", @"https://dns.nextdns.io", @""],
	];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:DPCL(@"preset_btn") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	for (NSArray<NSString *> *k in known) {
		[sheet addAction:[UIAlertAction actionWithTitle:k[0] style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
			__strong typeof(weakSelf) s = weakSelf;
			BOOL doh = s.mode == DPCModeDoH;
			s.serverField.text = doh ? k[2] : k[1];
			s.addrsField.text = k[3];
			s.portField.text = @"";
			if (!DPCTrim(s.nameField.text).length) s.nameField.text = [NSString stringWithFormat:@"%@ %@", k[0], doh ? @"DoH" : @"DoT"];
			[s saveDraft];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:DPCL(@"cancel_btn") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.presetButton;
	sheet.popoverPresentationController.sourceRect = self.presetButton.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

#pragma mark Profile

- (NSArray<NSString *> *)domainsOrError:(NSString **)error {
	static NSRegularExpression *shape;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		shape = [NSRegularExpression regularExpressionWithPattern:@"^(\\*\\.)?[a-z0-9_]([a-z0-9_\\-]{0,61}[a-z0-9_])?(\\.[a-z0-9_]([a-z0-9_\\-]{0,61}[a-z0-9_])?)*$" options:0 error:nil];
	});
	NSMutableOrderedSet<NSString *> *out = [NSMutableOrderedSet orderedSet];
	NSArray<NSString *> *lines = [self.domainsView.text ?: @"" componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet];
	for (NSUInteger i = 0; i < lines.count; i++) {
		NSString *line = lines[i];
		NSUInteger hash = [line rangeOfString:@"#"].location;
		if (hash != NSNotFound) line = [line substringToIndex:hash];
		for (NSString *raw in [line componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t,;"]]) {
			NSString *d = DPCTrim(raw).lowercaseString;
			while ([d hasSuffix:@"."]) d = [d substringToIndex:d.length - 1];
			if (!d.length) continue;
			if (d.length > 253 || [shape numberOfMatchesInString:d options:0 range:NSMakeRange(0, d.length)] != 1) {
				*error = [NSString stringWithFormat:DPCL(@"err_domain"), (unsigned long)(i + 1), d];
				return nil;
			}
			[out addObject:d];
		}
	}
	return out.array;
}

- (NSData *)buildProfileOrError:(NSString **)error fileName:(NSString **)fileName {
	NSArray<NSString *> *domains = [self domainsOrError:error];
	if (!domains) return nil;
	NSMutableDictionary *dns = [NSMutableDictionary dictionary];
	NSString *autoName;
	if (self.mode == DPCModeBlock) {
		if (!domains.count) { *error = DPCL(@"err_block_empty"); return nil; }
		dns[@"DNSProtocol"] = @"TLS";
		dns[@"ServerName"] = @"blocked.invalid";
		dns[@"ServerAddresses"] = @[@"127.0.0.1", @"::1"];
		autoName = [NSString stringWithFormat:@"DNS Block (%lu)", (unsigned long)domains.count];
	} else {
		NSMutableArray<NSString *> *addrs = [NSMutableArray array];
		for (NSString *raw in [self.addrsField.text ?: @"" componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", ;"]]) {
			NSString *a = DPCTrim(raw);
			if (!a.length) continue;
			if (!DPCIsIP(a)) { *error = [NSString stringWithFormat:DPCL(@"err_addr"), a]; return nil; }
			[addrs addObject:a];
		}
		NSString *server = DPCTrim(self.serverField.text);
		if (self.mode == DPCModeDoT) {
			if ([server hasPrefix:@"tls://"]) server = [server substringFromIndex:6];
			if (!server.length && !addrs.count) { *error = DPCL(@"err_server_dot"); return nil; }
			if (server.length && ([server containsString:@"/"] || [server containsString:@" "])) { *error = DPCL(@"err_server_dot"); return nil; }
			dns[@"DNSProtocol"] = @"TLS";
			if (server.length) dns[@"ServerName"] = server;
			autoName = [NSString stringWithFormat:@"DoT %@", server.length ? server : addrs.firstObject];
		} else {
			NSURLComponents *u = [NSURLComponents componentsWithString:server];
			if (!u || ![u.scheme.lowercaseString isEqualToString:@"https"] || !u.host.length) { *error = DPCL(@"err_server_doh"); return nil; }
			NSString *portText = DPCTrim(self.portField.text);
			if (portText.length) {
				NSInteger port = portText.integerValue;
				if (port < 1 || port > 65535 || ![portText isEqualToString:[@(port) stringValue]]) { *error = DPCL(@"err_port"); return nil; }
				u.port = port == 443 ? nil : @(port);
			}
			if (!u.path.length) u.path = @"/dns-query";
			dns[@"DNSProtocol"] = @"HTTPS";
			dns[@"ServerURL"] = u.string;
			autoName = [NSString stringWithFormat:@"DoH %@", u.host];
		}
		if (addrs.count) dns[@"ServerAddresses"] = addrs;
	}
	if (domains.count) dns[@"SupplementalMatchDomains"] = domains;

	NSString *name = DPCTrim(self.nameField.text);
	if (!name.length) name = autoName;
	NSString *slug = DPCSlug(name);
	NSString *rootID = [NSString stringWithFormat:@"%@.%@", DPCIdentifierBase, slug];
	NSDictionary *payload = @{
		@"PayloadType": @"com.apple.dnsSettings.managed",
		@"PayloadVersion": @1,
		@"PayloadIdentifier": [rootID stringByAppendingString:@".dns"],
		@"PayloadUUID": DPCStableUUID([rootID stringByAppendingString:@".dns"]),
		@"PayloadDisplayName": name,
		@"DNSSettings": dns,
	};
	NSDictionary *profile = @{
		@"PayloadType": @"Configuration",
		@"PayloadVersion": @1,
		@"PayloadIdentifier": rootID,
		@"PayloadUUID": DPCStableUUID(rootID),
		@"PayloadDisplayName": name,
		@"PayloadDescription": @"Created by DNS Profile Configurator.",
		@"PayloadOrganization": @"DNS Profile Configurator",
		@"PayloadRemovalDisallowed": @NO,
		@"PayloadContent": @[payload],
	};
	NSError *err = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:profile format:NSPropertyListXMLFormat_v1_0 options:0 error:&err];
	if (!data) { *error = err.localizedDescription; return nil; }
	*fileName = [slug stringByAppendingString:@".mobileconfig"];
	return data;
}

- (void)createTapped {
	[self.view endEditing:YES];
	[self saveDraft];
	NSString *error = nil, *fileName = nil;
	NSData *data = [self buildProfileOrError:&error fileName:&fileName];
	if (!data) { [self alert:DPCL(@"err_title") message:error]; return; }

	// Native path: the same ManagedConfiguration queue Safari and Files use.
	// iOS then shows "Profile Downloaded" in Settings with its normal installer.
	Class mc = NSClassFromString(@"MCProfileConnection");
	if (!mc) {
		void *h = dlopen("/System/Library/PrivateFrameworks/ManagedConfiguration.framework/ManagedConfiguration", RTLD_LAZY);
		(void)h;
		mc = NSClassFromString(@"MCProfileConnection");
	}
	MCProfileConnection *conn = [mc respondsToSelector:@selector(sharedConnection)] ? [mc sharedConnection] : nil;
	NSError *queueError = nil;
	id queued = nil;
	@try {
		if ([conn respondsToSelector:@selector(queueFileDataForAcceptance:originalFileName:forBundleID:outError:)]) {
			queued = [conn queueFileDataForAcceptance:data originalFileName:fileName forBundleID:@"com.apple.Preferences" outError:&queueError];
		} else if ([conn respondsToSelector:@selector(queueFileDataForAcceptance:originalFileName:outError:)]) {
			queued = [conn queueFileDataForAcceptance:data originalFileName:fileName outError:&queueError];
		}
	} @catch (__unused NSException *e) {
		queued = nil;
	}
	if (queued && !queueError) {
		self.statusLabel.text = DPCL(@"st_queued");
		[self alert:DPCL(@"queued_title") message:DPCL(@"queued_msg")];
		return;
	}

	// Fallback: serve the file once from localhost and let Safari install it.
	NSURL *url = [DPCOneShotServer serveData:data fileName:fileName];
	if (!url) {
		self.statusLabel.text = DPCL(@"st_failed");
		[self alert:DPCL(@"fail_title") message:queueError.localizedDescription ?: @""];
		return;
	}
	self.statusLabel.text = DPCL(@"st_safari");
	__weak typeof(self) weakSelf = self;
	[UIApplication.sharedApplication openURL:url options:@{} completionHandler:^(BOOL ok) {
		if (ok) return;
		dispatch_async(dispatch_get_main_queue(), ^{
			weakSelf.statusLabel.text = DPCL(@"st_failed");
			[weakSelf alert:DPCL(@"fail_title") message:queueError.localizedDescription ?: @""];
		});
	}];
}

#pragma mark Tooltip / theming

- (void)infoTapped:(UIButton *)sender {
	[self hideTooltip];
	UIView *host = self.navigationController.view ?: self.view;
	CGFloat maxW = MIN(host.bounds.size.width - 32.0, 340.0);
	UILabel *lbl = [[UILabel alloc] init];
	lbl.numberOfLines = 0;
	lbl.font = CRTFont(12, NO);
	lbl.textColor = CRTGreen();
	lbl.text = DPCL(@"tip_mode");
	CGSize sz = [lbl sizeThatFits:CGSizeMake(maxW - 20.0, CGFLOAT_MAX)];
	CGFloat w = sz.width + 20.0, h = sz.height + 16.0;
	UIView *bubble = [[UIView alloc] init];
	bubble.backgroundColor = [UIColor colorWithRed:0.02 green:0.08 blue:0.04 alpha:0.98];
	bubble.layer.borderColor = CRTGreen().CGColor;
	bubble.layer.borderWidth = 1.0;
	bubble.layer.cornerRadius = 8.0;
	bubble.userInteractionEnabled = NO;
	CGRect a = [sender convertRect:sender.bounds toView:host];
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

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section { return 6.0; }

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
	[a addAction:[UIAlertAction actionWithTitle:DPCL(@"ok_btn") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

@end

