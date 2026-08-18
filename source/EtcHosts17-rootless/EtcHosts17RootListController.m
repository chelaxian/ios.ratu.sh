#import <UIKit/UIKit.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>
#import <notify.h>
#import <spawn.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <sys/types.h>
#import <sys/wait.h>
#import <unistd.h>
#import <string.h>

extern char **environ;

@interface SBSRelaunchAction : NSObject
+ (instancetype)actionWithReason:(NSString *)reason options:(NSUInteger)options targetURL:(NSURL *)targetURL;
@end

@interface FBSSystemService : NSObject
+ (instancetype)sharedService;
- (void)sendActions:(NSSet *)actions withResult:(id)result;
@end

static NSString *const EtcHosts17Directory = @"/var/mobile/Library/EtcHosts17";
static NSString *const EtcHosts17ExtraPath = @"/var/mobile/Library/EtcHosts17/hosts.extra";
static NSString *const EtcHosts17MergedPath = @"/var/mobile/Library/EtcHosts17/hosts.merged";
static NSString *const EtcHosts17PrefsPath = @"/var/mobile/Library/Preferences/com.ratush.etchosts17.plist";
static NSString *const EtcHosts17PrefsHostsKey = @"HostsText";
static NSString *const EtcHosts17PrefsEnabledKey = @"Enabled";
static NSString *const EtcHosts17PrefsGlobalModeKey = @"GlobalMode";
static NSString *const EtcHosts17PrefsFallbackKey = @"FallbackSystemDNS";
static NSString *const EtcHosts17PrefsCreateProfileKey = @"CreateDNSProfile";
static NSString *const EtcHosts17PrefsUseProfileKey = @"UseDNSProfile";
// Profile transport + mode (read by the daemon to shape the .mobileconfig and
// how matched hosts are answered).
static NSString *const EtcHosts17PrefsProfileTransportKey = @"ProfileTransport";  // "tls" | "https"
static NSString *const EtcHosts17PrefsProfileModeKey = @"ProfileMode";             // "block" | "upstream"
static NSString *const EtcHosts17PrefsProfileUpstreamKey = @"ProfileUpstream";     // DoT server name, e.g. dns.google
// Profile Builder (generic .mobileconfig constructor) saved fields
static NSString *const EtcHosts17PrefsPBTransportKey = @"PBTransport";       // "TLS" | "HTTPS"
static NSString *const EtcHosts17PrefsPBServerKey = @"PBServer";             // DoT ServerName or DoH ServerURL
static NSString *const EtcHosts17PrefsPBAddrsKey = @"PBAddrs";               // comma-sep ServerAddresses (optional)
static NSString *const EtcHosts17PrefsPBDomainsKey = @"PBDomains";           // comma-sep SupplementalMatchDomains (empty=global)
static NSString *const EtcHosts17PrefsPBNameKey = @"PBName";                 // PayloadDisplayName
static NSString *const EtcHosts17PrefsPBUseLocalCAKey = @"PBUseLocalCA";     // BOOL: bundle our CA
static NSString *const EtcHosts17PrefsPBPortKey = @"PBPort";               // custom port (1-65535, 0=protocol default)
static NSString *const EtcHosts17PrefsPresetsKey = @"Presets";
static NSString *const EtcHosts17PrefsSelectedPresetKey = @"SelectedPreset";
static NSString *const EtcHosts17PrefsLanguageKey = @"Language";   // "en" | "ru"
static NSString *const EtcHosts17BasePath = @"/etc/hosts";
static NSString *const EtcHosts17ApplyToolPath = @"/usr/libexec/etchosts17ctl";
static NSString *const EtcHosts17DNSToolPath = @"/usr/libexec/etchosts17dns";
static NSString *const EtcHosts17DaemonServer = @"127.0.0.1";
// The daemon serves the freshly-generated scoped DoT .mobileconfig here; opening
// it in Safari drops the user straight into the iOS profile-install sheet.
static NSString *const EtcHosts17ProfileURL = @"http://127.0.0.1:53580/EtcHosts17.mobileconfig";
static const in_port_t EtcHosts17ControlPort = 53535;
static const char *EtcHosts17ApplyNotification = "com.ratush.etchosts17.apply";
static const NSUInteger SBSRelaunchActionOptionsFadeToBlackTransition = 1ULL << 0;

static UIColor *EH17Green(void) { return [UIColor colorWithRed:0.25 green:1.00 blue:0.45 alpha:1.0]; }
static UIColor *EH17MidGreen(void) { return [UIColor colorWithRed:0.16 green:0.82 blue:0.35 alpha:1.0]; }
static UIColor *EH17DimGreen(void) { return [UIColor colorWithRed:0.34 green:0.60 blue:0.40 alpha:1.0]; }
static UIColor *EH17CommentGreen(void) { return [UIColor colorWithRed:0.24 green:0.44 blue:0.30 alpha:1.0]; }
static UIColor *EH17Background(void) { return [UIColor colorWithRed:0.008 green:0.030 blue:0.015 alpha:1.0]; }
static UIColor *EH17Panel(void) { return [UIColor colorWithRed:0.020 green:0.075 blue:0.038 alpha:1.0]; }
static UIColor *EH17Border(void) { return [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:1.0]; }
static UIColor *EH17FieldBG(void) { return [UIColor colorWithRed:0.004 green:0.020 blue:0.010 alpha:1.0]; }

// A tiled scanline pattern image used as the background of UITextField inputs
// so they match the CRT scanline overlay of the big text editors. Cached once.
static UIColor *EH17ScanlineBG(void) {
	static UIColor *color = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		// 3pt tall tile: dark background + 1pt black scanline stripe.
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 3), YES, 0);
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		[EH17FieldBG() setFill]; CGContextFillRect(ctx, CGRectMake(0, 0, 4, 3));
		[[UIColor colorWithRed:0 green:0 blue:0 alpha:0.18] setFill];
		CGContextFillRect(ctx, CGRectMake(0, 0, 4, 1));
		UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		color = [UIColor colorWithPatternImage:img];
	});
	return color;
}

// A thin vertical divider image (1pt wide, semi-transparent green) used between
// segment segments so they don't merge into one block.
static UIImage *EH17DividerImage(void) {
	static UIImage *img = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, 30), NO, 0);
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		[[EH17Border() colorWithAlphaComponent:0.6] setFill];
		CGContextFillRect(ctx, CGRectMake(0, 0, 1, 30));
		img = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	});
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(14, 0, 14, 0)];
}

// Theme + relabel a UISegmentedControl for the green CRT look. iOS renders
// segments with the system grey pill by default. We clear the square-corner
// background images, draw a rounded green border around the whole control, and
// insert a thin green divider between segments so they read as separate pills.
// Titles are refreshed on every call so language switches update segment text.
static void EH17ThemeSegment(UISegmentedControl *seg, NSArray<NSString *> *titles) {
	if (titles.count) {
		for (NSUInteger i = 0; i < titles.count && i < seg.numberOfSegments; i++) {
			[seg setTitle:titles[i] forSegmentAtIndex:i];
		}
	}
	UIFont *norm = [UIFont fontWithName:@"CourierNewPSMT" size:12.0] ?: [UIFont fontWithName:@"Menlo-Regular" size:12.0] ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	UIFont *bold = [UIFont fontWithName:@"CourierNewPS-BoldMT" size:12.0] ?: [UIFont fontWithName:@"Menlo-Bold" size:12.0] ?: [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightBold];
	[seg setTitleTextAttributes:@{
		NSForegroundColorAttributeName: EH17DimGreen(),
		NSFontAttributeName: norm,
	} forState:UIControlStateNormal];
	[seg setTitleTextAttributes:@{
		NSForegroundColorAttributeName: EH17Green(),
		NSFontAttributeName: bold,
	} forState:UIControlStateSelected];
	// Clear the system background; keep a thin green divider so segments stay
	// visually separate inside our rounded border.
	[seg setBackgroundImage:[UIImage new] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	[seg setBackgroundImage:[UIImage new] forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
	[seg setDividerImage:EH17DividerImage() forLeftSegmentState:UIControlStateNormal rightSegmentState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	seg.tintColor = UIColor.clearColor;
	seg.backgroundColor = EH17Panel();
	seg.layer.cornerRadius = 7;
	seg.layer.borderWidth = 1.0;
	seg.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.7].CGColor;
	seg.layer.masksToBounds = YES;
	[seg setNeedsLayout];
}

#pragma mark - Localization (EN / RU)

static NSString *gEH17Lang = nil;

static NSString *EH17CurrentLang(void) {
	if ([gEH17Lang isEqualToString:@"ru"] || [gEH17Lang isEqualToString:@"en"]) return gEH17Lang;
	NSString *dev = [[NSLocale preferredLanguages].firstObject lowercaseString] ?: @"en";
	return [dev hasPrefix:@"ru"] ? @"ru" : @"en";
}

static NSString *EH17L(NSString *key) {
	static NSDictionary<NSString *, NSDictionary<NSString *, NSString *> *> *S = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		S = @{
		  @"subtitle": @{@"en": @"local DNS override // toggles apply instantly", @"ru": @"локальный DNS-override // тумблеры применяются сразу"},
		  @"subtitle_builder": @{@"en": @"DoT/DoH profile constructor // build .mobileconfig for any DNS server", @"ru": @"конструктор профилей DoT/DoH // сборка .mobileconfig для любого DNS-сервера"},
		  @"nano": @{@"en": @"root@iphone:~# nano /etc/hosts", @"ru": @"root@iphone:~# nano /etc/hosts"},
		  @"tab_hosts": @{@"en": @"HOSTS", @"ru": @"HOSTS"},
		  @"tab_builder": @{@"en": @"BUILDER", @"ru": @"КОНСТРУКТОР"},
		  @"sw_enable": @{@"en": @"Enable", @"ru": @"Включить"},
		  @"sw_global": @{@"en": @"Global mode (all DNS)", @"ru": @"Глобальный режим (весь DNS)"},
		  @"sw_forward": @{@"en": @"Forward non-listed upstream", @"ru": @"Форвардить не из списка"},
		  @"sw_profile": @{@"en": @"Create / update DNS profile", @"ru": @"Создать / обновить DNS-профиль"},
		  @"sw_profile_use": @{@"en": @"Use DoH/DoT profile (beats other DNS profiles)", @"ru": @"Профиль DoH/DoT (бьёт другие DNS-профили)"},
		  @"seg_transport_dot": @{@"en": @"DoT", @"ru": @"DoT"},
		  @"seg_transport_doh": @{@"en": @"DoH", @"ru": @"DoH"},
		  @"seg_mode_block": @{@"en": @"Block / map", @"ru": @"Блок / карта"},
		  @"seg_mode_upstream": @{@"en": @"Upstream", @"ru": @"Upstream"},
		  @"lbl_upstream": @{@"en": @"DoT upstream server (matched hosts)", @"ru": @"DoT upstream (для хостов из списка)"},
		  // --- Profile Builder section ---
		  @"pb_title": @{@"en": @"PROFILE BUILDER", @"ru": @"КОНСТРУКТОР ПРОФИЛЕЙ"},
		  @"pb_hint": @{
		    @"en": @"Build a managed-DNS .mobileconfig for ANY DoT/DoH server, then install it via Safari. Use it to create a ControlD DoT profile, a scoped override on this daemon, or any public resolver.",
		    @"ru": @"Соберите managed-DNS .mobileconfig для ЛЮБОГО DoT/DoH-сервера и установите через Safari. Например профиль ControlD DoT, scoped-override на этот демон или любой публичный резолвер."},
		  @"pb_server_dot": @{@"en": @"DoT ServerName (e.g. dns.google)", @"ru": @"DoT ServerName (напр. dns.google)"},
		  @"pb_server_doh": @{@"en": @"DoH ServerURL (https://...dns-query)", @"ru": @"DoH ServerURL (https://...dns-query)"},
		  @"pb_addrs": @{@"en": @"ServerAddresses (comma-sep IPs, optional)", @"ru": @"ServerAddresses (IP через запятую, опц.)"},
		  @"pb_port": @{@"en": @"Port 1-65535 (DoT: 853, DoH: 443)", @"ru": @"Порт 1-65535 (DoT: 853, DoH: 443)"},
		  @"pb_domains": @{@"en": @"Match domains (one per line; empty = global/primary)", @"ru": @"Хосты (по 1 на строку; пусто = global/primary)"},
		  @"pb_name": @{@"en": @"Profile display name", @"ru": @"Название профиля"},
		  @"pb_use_local_ca": @{@"en": @"Bundle our local CA (self-signed servers)", @"ru": @"Добавить наш CA (self-signed серверы)"},
		  @"pb_create": @{@"en": @"Create & install profile", @"ru": @"Создать и установить профиль"},
		  @"pb_created": @{@"en": @"> opening Safari to install the profile", @"ru": @"> открываю Safari для установки профиля"},
		  @"pb_invalid": @{@"en": @"> fill server/URL first", @"ru": @"> заполните server/URL"},
		  @"pb_expand": @{@"en": @"Show", @"ru": @"Открыть"},
		  @"pb_collapse": @{@"en": @"Hide", @"ru": @"Скрыть"},
		  @"tip_transport": @{
		    @"en": @"Encrypted transport the managed-DNS profile uses to reach this daemon. DoT (DNS-over-TLS, :853) is the default and lighter. DoH (DNS-over-HTTPS, :8443) is useful if a network middleboxes :853. Switching transport requires re-installing the profile.",
		    @"ru": @"Шифрованный транспорт, которым managed-DNS профиль ходит к этому демону. DoT (DNS-over-TLS, :853) — по умолчанию и легче. DoH (DNS-over-HTTPS, :8443) полезен, если сеть режет :853. Смена транспорта требует переустановки профиля."},
		  @"tip_mode": @{
		    @"en": @"How matched (listed) hosts are answered.\n\nBlock / map: answer from your editor map (0.0.0.0 etc.) — true /etc/hosts blocking.\n\nUpstream: forward the matched host to a real DoT server (set below). The host is still routed to us (so we win over DoH/VPN for it) but resolved through the chosen upstream instead of a static address.",
		    @"ru": @"Как отвечать на хосты из списка.\n\nБлок / карта: ответ из вашего редактора (0.0.0.0 и т.п.) — настоящая блокировка /etc/hosts.\n\nUpstream: форвардить хост на реальный DoT-сервер (укажите ниже). Хост всё равно идёт к нам (мы бьём DoH/VPN для него), но резолвится через выбранный upstream, а не статический адрес."},
		  @"vpn_info": @{
		    @"en": @"// local resolver beats Wi-Fi / cellular / Ethernet / VPN DNS · under VPN non-listed names are forwarded to the VPN's own DNS · profile mode is only for beating other DoH/DoT profiles",
		    @"ru": @"// локальный резолвер бьёт DNS Wi-Fi / сотовой сети / Ethernet / VPN · под VPN имена не из списка форвардятся в DNS самого VPN · режим профиля — только чтобы перебить другие DoH/DoT профили"},
		  @"reinstall_info": @{
		    @"en": @"// edit IP = live · add/remove a host in profile mode = re-tap \"Create / update DNS profile\" · Global mode = all edits live",
		    @"ru": @"// правка IP = на лету · добавить/убрать хост в режиме профиля = снова тап \"Создать / обновить DNS-профиль\" · Глобальный режим = все правки на лету"},
		  @"tip_enable": @{
		    @"en": @"Master switch. ON points the system resolver at the local daemon so your listed hosts beat plain Wi-Fi / cellular / Ethernet / VPN DNS (true /etc/hosts behavior); non-listed names are forwarded normally. OFF fully restores stock DNS — nothing is left changed. Only the global resolver is touched, never per-service DNS, so this is always reversible.",
		    @"ru": @"Главный выключатель. ВКЛ направляет системный резолвер на локальный демон — ваши хосты бьют обычный DNS Wi-Fi / сотовой сети / Ethernet / VPN (поведение /etc/hosts); имена не из списка форвардятся как обычно. ВЫКЛ полностью возвращает штатный DNS, ничего не остаётся изменённым. Трогается только глобальный резолвер, пер-сервисный DNS — никогда, поэтому это всегда обратимо."},
		  @"tip_global": @{
		    @"en": @"OFF (Scoped): only the hosts listed in the editor are routed to the tweak; the hostname set is baked into the profile at install, so adding/removing a hostname needs a profile re-install.\n\nON (Global): ALL DNS goes through the local resolver, so every editor change is live with no re-install; non-listed names are forwarded upstream (or blocked if \"Forward non-listed\" is OFF).",
		    @"ru": @"ВЫКЛ (Точечный): на твик идут только хосты из редактора; список имён «запекается» в профиль при установке, поэтому добавление/удаление имени требует переустановки профиля.\n\nВКЛ (Глобальный): ВЕСЬ DNS идёт через локальный резолвер, поэтому любая правка в редакторе применяется на лету без переустановки; не из списка — форвардятся вверх (или блокируются, если «Форвардить не из списка» ВЫКЛ)."},
		  @"tip_forward": @{
		    @"en": @"ON: names that are not in your list resolve normally (forwarded to public upstreams). This is also the safety fallback — if the tweak resolver is down, DNS keeps working via the system.\n\nOFF: strict allowlist — only listed hosts ever resolve, everything else is blocked (NODATA).",
		    @"ru": @"ВКЛ: имена не из вашего списка резолвятся нормально (форвард на публичные upstream). Это и есть страховка — если резолвер твика недоступен, DNS продолжит работать через систему.\n\nВЫКЛ: строгий allowlist — резолвятся только хосты из списка, всё остальное блокируется (NODATA)."},
		  @"tip_profile": @{
		    @"en": @"Hands you the DNS profile to install (Safari → Allow → Settings ▸ Profile Downloaded ▸ Install). Re-tap after adding/removing a hostname (Scoped mode) to refresh the profile.",
		    @"ru": @"Выдаёт DNS-профиль для установки (Safari → Разрешить → Настройки ▸ Профиль загружен ▸ Установить). Тапните снова после добавления/удаления хоста (Точечный режим), чтобы обновить профиль."},
		  @"tip_profile_use": @{
		    @"en": @"Turn ON only if another DoH/DoT profile is active (e.g. ControlD, NextDNS, AdGuard). It installs a scoped DNS profile so YOUR listed hosts win over it, while that profile keeps serving everything else. Editing an IP is live; adding/removing a hostname needs one more tap on \"Create / update DNS profile\" to refresh it. Leave OFF if you have no other DNS profile — the local resolver alone beats plain Wi-Fi/cellular/Ethernet/VPN DNS. Under a VPN the tweak uses the local resolver automatically.",
		    @"ru": @"Включайте, только если активен другой профиль DoH/DoT (ControlD, NextDNS, AdGuard). Устанавливает точечный DNS-профиль, чтобы ВАШИ хосты были главнее него, а он продолжал обслуживать остальное. Правка IP — на лету; добавление/удаление хоста требует ещё одного тапа по «Создать / обновить DNS-профиль». Оставьте ВЫКЛ, если других DNS-профилей нет — локального резолвера достаточно, он бьёт обычный DNS Wi-Fi/сотовой сети/Ethernet/VPN. Под VPN твик автоматически использует локальный резолвер."},
		  @"install_title": @{@"en": @"Install the DNS profile", @"ru": @"Установить DNS-профиль"},
		  @"install_msg": @{
		    @"en": @"Tap \"Install profile\": Safari opens, tap Allow, then Settings ▸ Profile Downloaded ▸ Install. It activates immediately and updates whenever you re-tap.",
		    @"ru": @"Нажмите «Установить профиль»: откроется Safari, нажмите Разрешить, затем Настройки ▸ Профиль загружен ▸ Установить. Активируется сразу и обновляется при повторном тапе."},
		  @"install_btn": @{@"en": @"Install profile", @"ru": @"Установить профиль"},
		  @"later_btn": @{@"en": @"Later", @"ru": @"Позже"},
		  @"ok_btn": @{@"en": @"OK", @"ru": @"OK"},
		  @"nohosts_title": @{@"en": @"No hosts to override", @"ru": @"Нет хостов для override"},
		  @"nohosts_msg": @{
		    @"en": @"Add at least one entry (for example \"0.0.0.0 ocsp.apple.com\") before creating the DNS profile, then tap Apply.",
		    @"ru": @"Добавьте хотя бы одну запись (например \"0.0.0.0 ocsp.apple.com\") перед созданием профиля, затем нажмите «Применить»."},
		  // --- bottom action cells + footer (Root.plist, built in code) ---
		  @"footer": @{
		    @"en": @"\"Create DNS-profile\" beats encrypted DNS (DoH/DoT) and VPN for the listed hosts — enable it once when prompted. IPv4/IPv6, many hosts per line, # comments.",
		    @"ru": @"«Создать DNS-профиль» побеждает зашифрованный DNS (DoH/DoT) и VPN для перечисленных хостов — включите один раз по запросу. IPv4/IPv6, несколько хостов в строке, # комментарии."},
		  @"footer_builder": @{
		    @"en": @"Fill the fields, then press \"Create & install\". Safari opens the .mobileconfig — install it via Settings \u25b8 General \u25b8 VPN & Device Management \u25b8 DNS.",
		    @"ru": @"Заполните поля и нажмите «Создать и установить». Safari откроет .mobileconfig — установите через Настройки \u25b8 Основные \u25b8 VPN и управление устройством \u25b8 DNS."},
		  @"apply_btn": @{@"en": @"Apply", @"ru": @"Применить"},
		  @"show_merged": @{@"en": @"Show merged hosts", @"ru": @"Показать объединённые hosts"},
		  @"respring_btn": @{@"en": @"Respring", @"ru": @"Респринг"},
		  // --- preset button + menu ---
		  @"preset_prefix": @{@"en": @"PRESET: ", @"ru": @"ПРЕСЕТ: "},
		  @"preset_menu_title": @{@"en": @"Hosts presets", @"ru": @"Пресеты hosts"},
		  @"preset_add": @{@"en": @"Add new preset", @"ru": @"Добавить пресет"},
		  @"preset_rename": @{@"en": @"Rename current preset", @"ru": @"Переименовать пресет"},
		  @"preset_delete": @{@"en": @"Delete current preset", @"ru": @"Удалить пресет"},
		  @"cancel_btn": @{@"en": @"Cancel", @"ru": @"Отмена"},
		  @"save_btn": @{@"en": @"Save", @"ru": @"Сохранить"},
		  @"newpreset_title": @{@"en": @"New preset", @"ru": @"Новый пресет"},
		  @"newpreset_msg": @{
		    @"en": @"The current editor text will be saved into this preset.",
		    @"ru": @"Текущий текст редактора будет сохранён в этот пресет."},
		  @"newpreset_ph": @{@"en": @"Preset name", @"ru": @"Название пресета"},
		  @"rename_title": @{@"en": @"Rename preset", @"ru": @"Переименовать пресет"},
		  @"rename_btn": @{@"en": @"Rename", @"ru": @"Переименовать"},
		  @"cantdelete_title": @{@"en": @"Cannot delete", @"ru": @"Нельзя удалить"},
		  @"cantdelete_msg": @{@"en": @"Keep at least one preset.", @"ru": @"Оставьте хотя бы один пресет."},
		  // --- status line messages ---
		  @"st_persisted": @{@"en": @"> persisted in com.ratush.etchosts17.plist", @"ru": @"> сохранено в com.ratush.etchosts17.plist"},
		  @"st_profile_on": @{@"en": @"> profile mode on — install the DNS profile", @"ru": @"> режим профиля вкл — установите DNS-профиль"},
		  @"st_profile_off": @{@"en": @"> profile mode off — local resolver only", @"ru": @"> режим профиля выкл — только локальный резолвер"},
		  @"st_saved": @{@"en": @"> setting saved and pushed to daemon", @"ru": @"> настройка сохранена и отправлена демону"},
		  @"st_enabled": @{@"en": @"> enabled; resolver override on", @"ru": @"> включено; override резолвера активен"},
		  @"st_disabled": @{@"en": @"> disabled; DNS back to system", @"ru": @"> выключено; DNS вернулся к системному"},
		  @"st_invalid": @{@"en": @"> invalid syntax; not saved", @"ru": @"> неверный синтаксис; не сохранено"},
		  @"st_preset_loaded": @{@"en": @"> preset loaded; tap Apply to activate", @"ru": @"> пресет загружен; нажмите «Применить»"},
		  @"st_preset_saved": @{@"en": @"> preset saved; tap Apply to activate", @"ru": @"> пресет сохранён; нажмите «Применить»"},
		  @"st_apply_failed": @{@"en": @"> apply failed", @"ru": @"> применение не удалось"},
		  @"st_applied": @{@"en": @"> applied; overrides refreshed", @"ru": @"> применено; override обновлены"},
		  @"st_profile_ready": @{@"en": @"> DNS profile ready — install it", @"ru": @"> DNS-профиль готов — установите его"},
		  // --- alerts ---
		  @"invalid_title": @{@"en": @"Invalid hosts syntax", @"ru": @"Неверный синтаксис hosts"},
		  @"invalid_more": @{@"en": @"\n...and %lu more.", @"ru": @"\n...и ещё %lu."},
		  @"invalid_line": @{@"en": @"Line %lu: invalid hostname \"%@\".", @"ru": @"Строка %lu: неверное имя хоста «%@»."},
		  @"invalid_syntax": @{@"en": @"Line %lu: use \"IP hostname [hostname ...]\".", @"ru": @"Строка %lu: формат «IP hostname [hostname ...]»."},
		  @"invalid_ip": @{@"en": @"Line %lu: invalid IP \"%@\".", @"ru": @"Строка %lu: неверный IP «%@»."},
		  @"rename_exists": @{@"en": @"A preset with that name already exists.", @"ru": @"Пресет с таким именем уже существует."},
		  @"must_enable": @{@"en": @"Enable the tweak first to apply changes.", @"ru": @"Сначала включите твик, чтобы применить изменения."},
		  @"applyfailed_title": @{@"en": @"Apply failed", @"ru": @"Применение не удалось"},
		  @"applyfailed_msg": @{@"en": @"Could not write merged hosts.", @"ru": @"Не удалось записать объединённый hosts."},
		  @"removeprofile_title": @{@"en": @"Remove the DNS profile", @"ru": @"Удалить DNS-профиль"},
		  @"removeprofile_msg": @{
		    @"en": @"Overrides are off. To fully remove the scoped DNS profile, open Settings ▸ General ▸ VPN & Device Management ▸ \"/etc/hosts (iOS 17.0)\" and tap Remove Profile.",
		    @"ru": @"Override выключены. Чтобы полностью удалить точечный DNS-профиль, откройте Настройки ▸ Основные ▸ VPN и управление устройством ▸ «/etc/hosts (iOS 17.0)» и нажмите «Удалить профиль»."},
		  @"couldnotopen_title": @{@"en": @"Could not open the profile", @"ru": @"Не удалось открыть профиль"},
		  @"couldnotopen_msg": @{
		    @"en": @"Make sure EtcHosts17 is enabled (the daemon must be running), then try again. You can also open http://127.0.0.1:53580/ in Safari manually.",
		    @"ru": @"Убедитесь, что твик включён (демон должен работать), и повторите. Также можно вручную открыть http://127.0.0.1:53580/ в Safari."},
		  @"merged_title": @{@"en": @"Merged hosts", @"ru": @"Объединённые hosts"},
		  @"merged_empty": @{@"en": @"No merged file yet. Tap Apply first.", @"ru": @"Объединённого файла ещё нет. Сначала нажмите «Применить»."},
		};
	});
	NSDictionary *entry = S[key];
	if (!entry) return key;
	return entry[EH17CurrentLang()] ?: entry[@"en"] ?: key;
}

#pragma mark - CRT scanline overlay

@interface EH17ScanlineView : UIView
@end

@implementation EH17ScanlineView
- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.userInteractionEnabled = NO;
		self.backgroundColor = UIColor.clearColor;
		self.contentMode = UIViewContentModeRedraw;
	}
	return self;
}
- (void)drawRect:(CGRect)rect {
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	// Horizontal scanlines every 3pt.
	CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 0.16);
	for (CGFloat y = 0; y < rect.size.height; y += 3.0) {
		CGContextFillRect(ctx, CGRectMake(0, y, rect.size.width, 1.0));
	}
	// Soft green phosphor bloom at the top edge.
	CGContextSetRGBFillColor(ctx, 0.15, 1.0, 0.4, 0.05);
	CGContextFillRect(ctx, CGRectMake(0, 0, rect.size.width, 2.0));
}
@end

@interface EtcHosts17RootListController : PSListController <UITextViewDelegate, UITextFieldDelegate>
@property (nonatomic, strong) UITextView *hostsTextView;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIView *editorHeaderView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *nanoLabel;
@property (nonatomic, strong) UISwitch *enabledSwitch;
@property (nonatomic, strong) UISwitch *globalModeSwitch;
@property (nonatomic, strong) UISwitch *fallbackSwitch;
@property (nonatomic, strong) UISwitch *useProfileSwitch;
// Profile transport selector (DoT / DoH) and mode selector (Block / Upstream),
// plus the upstream DoT server-name field (visible only in Upstream mode).
@property (nonatomic, strong) UISegmentedControl *transportControl;
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UITextField *upstreamField;
@property (nonatomic, strong) UIButton *createProfileButton;
// Profile Builder section (generic .mobileconfig constructor for any DoT/DoH server)
@property (nonatomic, strong) UISegmentedControl *pbTransportControl;  // DoT/DoH
@property (nonatomic, strong) UITextField *pbServerField;             // ServerName or ServerURL
@property (nonatomic, strong) UITextField *pbAddrsField;              // ServerAddresses (comma-sep, optional)
@property (nonatomic, strong) UITextField *pbPortField;               // custom port (1-65535)
@property (nonatomic, strong) UITextField *pbNameField;               // PayloadDisplayName
@property (nonatomic, strong) UISwitch *pbUseLocalCASwitch;
@property (nonatomic, strong) UIButton *pbCreateButton;
@property (nonatomic, strong) UILabel *vpnInfoLabel;
@property (nonatomic, strong) UILabel *reinstallInfoLabel;
@property (nonatomic, strong) NSMutableArray<UIButton *> *infoButtons;   // one per switch row
@property (nonatomic, strong) NSArray<NSString *> *infoKeys;             // tooltip key per row
@property (nonatomic, strong) UIButton *langButton;
@property (nonatomic, strong) UIView *tooltipBubble;
@property (nonatomic, strong) UIControl *tooltipDismisser;
@property (nonatomic, strong) UIButton *presetButton;
@property (nonatomic, strong) NSMutableArray<UIView *> *separatorLines;
@property (nonatomic, strong) UIView *blockCursor;
@property (nonatomic, strong) EH17ScanlineView *scanlines;
@property (nonatomic, strong) UIView *resizeHandle;
@property (nonatomic, assign) CGFloat editorHeight;      // 0 = auto-fit
@property (nonatomic, assign) CGFloat resizeStartHeight;
@property (nonatomic, assign) BOOL applyingHighlight;
// Tab system: HOSTS page (editor + toggles) vs BUILDER page (profile creator).
// Both live in the same header; only one is visible at a time. This replaces
// the old single-scroll layout that was overloaded with both sections.
@property (nonatomic, strong) UISegmentedControl *pageControl;   // HOSTS | BUILDER
@property (nonatomic, assign) NSInteger activePage;             // 0 = hosts, 1 = builder
@property (nonatomic, strong) UITextView *pbDomainsView;         // large multi-line editor (was pbDomainsField)
@property (nonatomic, strong) EH17ScanlineView *pbDomainsScan;   // scanline overlay for the builder editor
@property (nonatomic, strong) UIView *pbDomainsResizeHandle;     // resize grip (same as hosts editor)
@property (nonatomic, assign) CGFloat pbDomainsHeight;           // 0 = auto-fit
@property (nonatomic, assign) CGFloat pbDomainsResizeStart;
@property (nonatomic, strong) EH17ScanlineView *pageScanlines;   // scanlines over the whole header (glitch/CRT)
@end

@implementation EtcHosts17RootListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		_specifiers = [self buildLocalizedSpecifiers];
	}
	return _specifiers;
}

// Built in code (not from Root.plist) so the bottom footer + button cells follow
// the in-app RU/EN toggle and the active page. The Apply/Show merged/Respring
// buttons are HOSTS-page-only; on the BUILDER page they are hidden (the whole
// point of the builder is a separate self-contained page).
- (NSMutableArray *)buildLocalizedSpecifiers {
	PSSpecifier *group = [PSSpecifier emptyGroupSpecifier];
	[group setProperty:EH17L((self.activePage == 1) ? @"footer_builder" : @"footer") forKey:@"footerText"];

	NSMutableArray *specs = [NSMutableArray arrayWithObject:group];
	if (self.activePage == 1) return specs;   // BUILDER page: no action buttons

	PSSpecifier *apply = [PSSpecifier preferenceSpecifierNamed:EH17L(@"apply_btn")
		target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
	[apply setButtonAction:@selector(applyChanges)];

	PSSpecifier *merged = [PSSpecifier preferenceSpecifierNamed:EH17L(@"show_merged")
		target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
	[merged setButtonAction:@selector(openMergedFile)];

	PSSpecifier *respr = [PSSpecifier preferenceSpecifierNamed:EH17L(@"respring_btn")
		target:self set:NULL get:NULL detail:Nil cell:PSButtonCell edit:Nil];
	[respr setButtonAction:@selector(respring)];

	[specs addObjectsFromArray:@[apply, merged, respr]];
	return specs;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"/etc/hosts (iOS 17.0)";
	self.view.backgroundColor = EH17Background();
	self.view.tintColor = EH17Green();
	self.table.backgroundColor = EH17Background();
	self.table.separatorColor = [EH17Border() colorWithAlphaComponent:0.35];
	self.table.indicatorStyle = UIScrollViewIndicatorStyleWhite;
	self.table.alwaysBounceVertical = NO;
	self.separatorLines = [NSMutableArray array];
	[self ensureStorageDirectory];
	[self loadLanguageFromPrefs];
	[self buildEditorHeader];
	[self loadExtraHostsIntoEditor];
}

- (void)loadLanguageFromPrefs {
	NSString *lang = [[self currentPrefsDictionary] objectForKey:EtcHosts17PrefsLanguageKey];
	if ([lang isEqualToString:@"ru"] || [lang isEqualToString:@"en"]) gEH17Lang = lang;
	else gEH17Lang = nil;   // fall back to device language
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	[self layoutEditorHeader];
}

- (void)viewWillDisappear:(BOOL)animated {
	[super viewWillDisappear:animated];
	[self saveExtraHostsFromEditorShowingError:NO];
}

- (UIFont *)terminalFontOfSize:(CGFloat)size bold:(BOOL)bold {
	// Courier New is the classic CRT-terminal monospaced font. iOS ships it as
	// "CourierNewPS-BoldMT" / "CourierNewPSMT". Fall back to Menlo (same family),
	// then to the system monospaced font.
	NSString *name = bold ? @"CourierNewPS-BoldMT" : @"CourierNewPSMT";
	UIFont *font = [UIFont fontWithName:name size:size];
	if (!font) font = [UIFont fontWithName:(bold ? @"Menlo-Bold" : @"Menlo-Regular") size:size];
	if (!font) font = [UIFont monospacedSystemFontOfSize:size weight:(bold ? UIFontWeightBold : UIFontWeightRegular)];
	return font;
}

// The main editor font: Courier New bold green — the look of a classic
// black/green CRT terminal. Used by BOTH the hosts editor and every builder
// input field so the whole panel reads as one terminal screen.
- (UIFont *)editorFont { return [self terminalFontOfSize:13.5 bold:YES]; }

- (UIView *)makeSeparator {
	UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
	line.backgroundColor = [EH17Border() colorWithAlphaComponent:0.55];
	[self.editorHeaderView addSubview:line];
	[self.separatorLines addObject:line];
	return line;
}

- (void)buildEditorHeader {
	CGFloat width = MAX(self.table.bounds.size.width, 320.0);
	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 560)];
	header.autoresizingMask = UIViewAutoresizingFlexibleWidth;
	header.backgroundColor = EH17Background();
	self.editorHeaderView = header;

	UILabel *title = [[UILabel alloc] init];
	title.font = [self terminalFontOfSize:19 bold:YES];
	title.textColor = EH17Green();
	title.text = @"/etc/hosts (iOS 17.0)";
	title.adjustsFontSizeToFitWidth = YES;
	title.minimumScaleFactor = 0.7;
	self.titleLabel = title;
	[header addSubview:title];

	UILabel *subtitle = [[UILabel alloc] init];
	subtitle.font = [self terminalFontOfSize:10.5 bold:NO];
	subtitle.textColor = EH17DimGreen();
	subtitle.text = EH17L(@"subtitle");
	self.subtitleLabel = subtitle;
	[header addSubview:subtitle];

	// Page tab: HOSTS | BUILDER. Selecting a page hides the other section's
	// elements entirely (.hidden + .frame=CGRectZero), so each page reads as a
	// clean dedicated screen instead of one overloaded scroll.
	self.pageControl = [[UISegmentedControl alloc] initWithItems:@[EH17L(@"tab_hosts"), EH17L(@"tab_builder")]];
	self.pageControl.selectedSegmentIndex = 0;
	self.activePage = 0;
	[self.pageControl addTarget:self action:@selector(pageChanged:) forControlEvents:UIControlEventValueChanged];
	[header addSubview:self.pageControl];

	// Two toggles only. The redirect is inherently global (it points the whole
	// system resolver at the local daemon) and additive (non-listed names are
	// always forwarded), so the old "Global mode" and "Forward non-listed"
	// toggles were redundant/unsafe and were removed.
	self.enabledSwitch = [self addSwitchToHeader:header title:EH17L(@"sw_enable") action:@selector(settingSwitchChanged:)];
	// Optional profile mode: only needed to beat OTHER active DoH/DoT profiles
	// (e.g. ControlD/NextDNS). Users without such profiles can leave it off and
	// rely on the system-resolver redirect alone.
	self.useProfileSwitch = [self addSwitchToHeader:header title:EH17L(@"sw_profile_use") action:@selector(settingSwitchChanged:)];

	// Encrypted transport for the profile (DoT default; DoH if :853 is middleboxed).
	// Switching transport only takes effect after re-installing the profile.
	self.transportControl = [[UISegmentedControl alloc] initWithItems:@[EH17L(@"seg_transport_dot"), EH17L(@"seg_transport_doh")]];
	self.transportControl.selectedSegmentIndex = 0;
	[self.transportControl addTarget:self action:@selector(profileOptionChanged:) forControlEvents:UIControlEventValueChanged];
	[header addSubview:self.transportControl];

	// Profile mode: Block answers from the editor map (0.0.0.0 etc.); Upstream
	// forwards matched hosts to a real DoT server (see upstreamField).
	self.modeControl = [[UISegmentedControl alloc] initWithItems:@[EH17L(@"seg_mode_block"), EH17L(@"seg_mode_upstream")]];
	self.modeControl.selectedSegmentIndex = 0;
	[self.modeControl addTarget:self action:@selector(profileOptionChanged:) forControlEvents:UIControlEventValueChanged];
	[header addSubview:self.modeControl];

	// Upstream DoT server-name field (only meaningful in Upstream mode). Offers a
	// small set of well-known presets via the keyboard's input accessory.
	UILabel *upstreamLabel = [[UILabel alloc] init];
	upstreamLabel.tag = 43005;   // located by tag in layoutEditorHeader
	upstreamLabel.font = [self terminalFontOfSize:10.5 bold:NO];
	upstreamLabel.textColor = EH17DimGreen();
	upstreamLabel.text = EH17L(@"lbl_upstream");
	upstreamLabel.adjustsFontSizeToFitWidth = YES;
	upstreamLabel.minimumScaleFactor = 0.7;
	[header addSubview:upstreamLabel];
	self.upstreamField = [[UITextField alloc] init];
	self.upstreamField.font = [self terminalFontOfSize:13 bold:NO];
	self.upstreamField.textColor = EH17Green();
	self.upstreamField.backgroundColor = EH17ScanlineBG();
	self.upstreamField.layer.cornerRadius = 6;
	self.upstreamField.layer.borderWidth = 1.0;
	self.upstreamField.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.6].CGColor;
	self.upstreamField.keyboardAppearance = UIKeyboardAppearanceDark;
	self.upstreamField.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.upstreamField.autocorrectionType = UITextAutocorrectionTypeNo;
	self.upstreamField.smartDashesType = UITextSmartDashesTypeNo;
	self.upstreamField.smartQuotesType = UITextSmartQuotesTypeNo;
	self.upstreamField.returnKeyType = UIReturnKeyDone;
	self.upstreamField.delegate = self;
	self.upstreamField.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 8, 1)];
	self.upstreamField.leftViewMode = UITextFieldViewModeAlways;
	[header addSubview:self.upstreamField];

	// One tappable "i" per switch/segment row: short tap = sticky tooltip,
	// long-press = show while held. Order MUST match infoKeys below.
	// Index 4 = builder hint (shown next to the page tab, not a switch row).
	self.infoKeys = @[@"tip_enable", @"tip_profile_use", @"tip_transport", @"tip_mode", @"pb_hint"];
	self.infoButtons = [NSMutableArray array];
	for (NSUInteger i = 0; i < self.infoKeys.count; i++) {
		[self.infoButtons addObject:[self makeInfoButtonIndex:i inHeader:header]];
	}

	// Profile creation is a secondary action now (the primary override is the
	// system-resolver redirect), so it is a button, not a toggle. Short tap
	// creates/installs the .mobileconfig; long-press shows its tooltip.
	self.createProfileButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.createProfileButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
	self.createProfileButton.backgroundColor = EH17Panel();
	self.createProfileButton.layer.cornerRadius = 7;
	self.createProfileButton.layer.borderWidth = 1.0;
	self.createProfileButton.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.7].CGColor;
	self.createProfileButton.titleLabel.font = [self terminalFontOfSize:13 bold:YES];
	self.createProfileButton.titleLabel.adjustsFontSizeToFitWidth = YES;
	self.createProfileButton.titleLabel.minimumScaleFactor = 0.7;
	[self.createProfileButton setTitleColor:EH17Green() forState:UIControlStateNormal];
	[self.createProfileButton addTarget:self action:@selector(createProfileTapped) forControlEvents:UIControlEventTouchUpInside];
	UILongPressGestureRecognizer *plp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(createProfileLongPress:)];
	plp.minimumPressDuration = 0.25;
	[self.createProfileButton addGestureRecognizer:plp];
	[header addSubview:self.createProfileButton];

	// --- Profile Builder (BUILDER page) ---
	// No collapse toggle anymore: the pageControl tab above switches the whole
	// section in/out. Every builder element is a direct child of header, placed
	// at absolute (margin, y). When the HOSTS page is active, all of these are
	// hidden via .hidden=YES + .frame=CGRectZero (same mechanism as upstreamField).

	// Hint caption (dim "// ..." style, same font as upstream label/nano prompt).
	UILabel *pbHintLabel = [[UILabel alloc] init];
	pbHintLabel.tag = 43009;
	pbHintLabel.font = [self terminalFontOfSize:10 bold:NO];
	pbHintLabel.textColor = EH17CommentGreen();
	pbHintLabel.text = EH17L(@"pb_hint");
	pbHintLabel.numberOfLines = 0;
	pbHintLabel.hidden = YES;
	[header addSubview:pbHintLabel];

	self.pbTransportControl = [[UISegmentedControl alloc] initWithItems:@[EH17L(@"seg_transport_dot"), EH17L(@"seg_transport_doh")]];
	self.pbTransportControl.selectedSegmentIndex = 0;
	[self.pbTransportControl addTarget:self action:@selector(pbFieldChanged:) forControlEvents:UIControlEventValueChanged];
	self.pbTransportControl.hidden = YES;
	[header addSubview:self.pbTransportControl];

	// Each field is preceded by a small dim caption (same pattern as the
	// upstream row: label tag 43005 + upstreamField) so the builder reads like
	// the rest of the terminal panel.
	UILabel *pbServerCaption = [[UILabel alloc] init];
	pbServerCaption.tag = 43011;
	pbServerCaption.font = [self terminalFontOfSize:10 bold:NO];
	pbServerCaption.textColor = EH17CommentGreen();
	pbServerCaption.text = EH17L(@"pb_server_dot");
	pbServerCaption.adjustsFontSizeToFitWidth = YES;
	pbServerCaption.minimumScaleFactor = 0.7;
	pbServerCaption.hidden = YES;
	[header addSubview:pbServerCaption];
	self.pbServerField = [self makePBFieldPlaceholder:EH17L(@"pb_server_dot")];
	self.pbServerField.hidden = YES;
	[header addSubview:self.pbServerField];

	UILabel *pbAddrsCaption = [[UILabel alloc] init];
	pbAddrsCaption.tag = 43012;
	pbAddrsCaption.font = [self terminalFontOfSize:10 bold:NO];
	pbAddrsCaption.textColor = EH17CommentGreen();
	pbAddrsCaption.text = EH17L(@"pb_addrs");
	pbAddrsCaption.adjustsFontSizeToFitWidth = YES;
	pbAddrsCaption.minimumScaleFactor = 0.7;
	pbAddrsCaption.hidden = YES;
	[header addSubview:pbAddrsCaption];
	self.pbAddrsField = [self makePBFieldPlaceholder:EH17L(@"pb_addrs")];
	self.pbAddrsField.hidden = YES;
	[header addSubview:self.pbAddrsField];

	// Custom port field (1-65535). Lets the user override the protocol default
	// (DoT=853, DoH=443) for non-standard DoT/DoH servers.
	UILabel *pbPortCaption = [[UILabel alloc] init];
	pbPortCaption.tag = 43015;
	pbPortCaption.font = [self terminalFontOfSize:10 bold:NO];
	pbPortCaption.textColor = EH17CommentGreen();
	pbPortCaption.text = EH17L(@"pb_port");
	pbPortCaption.adjustsFontSizeToFitWidth = YES;
	pbPortCaption.minimumScaleFactor = 0.7;
	pbPortCaption.hidden = YES;
	[header addSubview:pbPortCaption];
	self.pbPortField = [self makePBFieldPlaceholder:EH17L(@"pb_port")];
	self.pbPortField.hidden = YES;
	self.pbPortField.keyboardType = UIKeyboardTypeNumberPad;
	[header addSubview:self.pbPortField];

	UILabel *pbDomainsCaption = [[UILabel alloc] init];
	pbDomainsCaption.tag = 43013;
	pbDomainsCaption.font = [self terminalFontOfSize:10 bold:NO];
	pbDomainsCaption.textColor = EH17CommentGreen();
	pbDomainsCaption.text = EH17L(@"pb_domains");
	pbDomainsCaption.adjustsFontSizeToFitWidth = YES;
	pbDomainsCaption.minimumScaleFactor = 0.7;
	pbDomainsCaption.hidden = YES;
	[header addSubview:pbDomainsCaption];
	// Domains is a multi-line editor (one domain per line), styled identically
	// to the /etc/hosts editor: CRT-green monospaced text, scanline overlay, and
	// a draggable resize grip. Same look & feel, not a narrow one-line field.
	self.pbDomainsView = [[UITextView alloc] initWithFrame:CGRectZero];
	self.pbDomainsView.font = [self editorFont];
	self.pbDomainsView.textColor = EH17Green();
	self.pbDomainsView.tintColor = [EH17DimGreen() colorWithAlphaComponent:0.35];
	self.pbDomainsView.layer.cornerRadius = 8;
	self.pbDomainsView.clipsToBounds = YES;
	self.pbDomainsView.layer.borderWidth = 1.0;
	self.pbDomainsView.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.8].CGColor;
	self.pbDomainsView.backgroundColor = EH17FieldBG();
	self.pbDomainsView.textContainerInset = UIEdgeInsetsMake(10, 9, 10, 9);
	self.pbDomainsView.textContainer.lineFragmentPadding = 0;
	self.pbDomainsView.alwaysBounceVertical = YES;
	self.pbDomainsView.showsVerticalScrollIndicator = YES;
	self.pbDomainsView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
	self.pbDomainsView.keyboardAppearance = UIKeyboardAppearanceDark;
	self.pbDomainsView.autocorrectionType = UITextAutocorrectionTypeNo;
	self.pbDomainsView.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.pbDomainsView.smartDashesType = UITextSmartDashesTypeNo;
	self.pbDomainsView.smartQuotesType = UITextSmartQuotesTypeNo;
	self.pbDomainsView.delegate = self;
	self.pbDomainsView.hidden = YES;
	[header addSubview:self.pbDomainsView];
	// Scanline overlay over the domains editor (CRT effect, does not scroll).
	self.pbDomainsScan = [[EH17ScanlineView alloc] initWithFrame:CGRectZero];
	self.pbDomainsScan.hidden = YES;
	[header addSubview:self.pbDomainsScan];
	// Draggable resize grip on the domains editor's bottom border.
	self.pbDomainsResizeHandle = [[UIView alloc] initWithFrame:CGRectZero];
	self.pbDomainsResizeHandle.backgroundColor = UIColor.clearColor;
	self.pbDomainsResizeHandle.hidden = YES;
	UIView *dGrip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 34, 4)];
	dGrip.tag = 7789;
	dGrip.backgroundColor = [EH17Green() colorWithAlphaComponent:0.8];
	dGrip.layer.cornerRadius = 2;
	[self.pbDomainsResizeHandle addSubview:dGrip];
	UIPanGestureRecognizer *dPan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePBDomainsResizePan:)];
	[self.pbDomainsResizeHandle addGestureRecognizer:dPan];
	[header addSubview:self.pbDomainsResizeHandle];

	UILabel *pbNameCaption = [[UILabel alloc] init];
	pbNameCaption.tag = 43014;
	pbNameCaption.font = [self terminalFontOfSize:10 bold:NO];
	pbNameCaption.textColor = EH17CommentGreen();
	pbNameCaption.text = EH17L(@"pb_name");
	pbNameCaption.adjustsFontSizeToFitWidth = YES;
	pbNameCaption.minimumScaleFactor = 0.7;
	pbNameCaption.hidden = YES;
	[header addSubview:pbNameCaption];
	self.pbNameField = [self makePBFieldPlaceholder:EH17L(@"pb_name")];
	self.pbNameField.hidden = YES;
	[header addSubview:self.pbNameField];

	// CA switch row: label left, switch right — same layout as enabledSwitch.
	UILabel *pbCaLabel = [[UILabel alloc] init];
	pbCaLabel.tag = 43010;
	pbCaLabel.font = [self terminalFontOfSize:11 bold:NO];
	pbCaLabel.textColor = EH17DimGreen();
	pbCaLabel.text = EH17L(@"pb_use_local_ca");
	pbCaLabel.adjustsFontSizeToFitWidth = YES;
	pbCaLabel.minimumScaleFactor = 0.7;
	pbCaLabel.hidden = YES;
	[header addSubview:pbCaLabel];
	self.pbUseLocalCASwitch = [[UISwitch alloc] init];
	self.pbUseLocalCASwitch.onTintColor = EH17MidGreen();
	self.pbUseLocalCASwitch.transform = CGAffineTransformMakeScale(0.82, 0.82);
	[self.pbUseLocalCASwitch addTarget:self action:@selector(pbFieldChanged:) forControlEvents:UIControlEventValueChanged];
	self.pbUseLocalCASwitch.hidden = YES;
	[header addSubview:self.pbUseLocalCASwitch];

	// Create button — same style as createProfileButton (full-width panel button).
	self.pbCreateButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.pbCreateButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentCenter;
	self.pbCreateButton.backgroundColor = EH17Panel();
	self.pbCreateButton.layer.cornerRadius = 7;
	self.pbCreateButton.layer.borderWidth = 1.0;
	self.pbCreateButton.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.7].CGColor;
	self.pbCreateButton.titleLabel.font = [self terminalFontOfSize:13 bold:YES];
	self.pbCreateButton.titleLabel.adjustsFontSizeToFitWidth = YES;
	self.pbCreateButton.titleLabel.minimumScaleFactor = 0.7;
	[self.pbCreateButton setTitleColor:EH17Green() forState:UIControlStateNormal];
	[self.pbCreateButton addTarget:self action:@selector(pbCreateTapped) forControlEvents:UIControlEventTouchUpInside];
	self.pbCreateButton.hidden = YES;
	[header addSubview:self.pbCreateButton];

	// Language toggle EN/RU (top-right of the header).
	self.langButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.langButton.titleLabel.font = [self terminalFontOfSize:12 bold:YES];
	[self.langButton setTitleColor:EH17Green() forState:UIControlStateNormal];
	self.langButton.layer.borderWidth = 1.0;
	self.langButton.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.7].CGColor;
	self.langButton.layer.cornerRadius = 5;
	[self.langButton addTarget:self action:@selector(toggleLanguage) forControlEvents:UIControlEventTouchUpInside];
	[header addSubview:self.langButton];

	// The always-visible "// ..." hint lines were removed to declutter the panel;
	// the same information now lives only behind the "i" tooltips.
	self.presetButton = [UIButton buttonWithType:UIButtonTypeSystem];
	self.presetButton.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeading;
	self.presetButton.backgroundColor = EH17Panel();
	self.presetButton.layer.cornerRadius = 7;
	self.presetButton.layer.borderWidth = 1.0;
	self.presetButton.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.7].CGColor;
	self.presetButton.clipsToBounds = YES;
	[self.presetButton addTarget:self action:@selector(showPresetMenu) forControlEvents:UIControlEventTouchUpInside];
	[header addSubview:self.presetButton];

	UILabel *nano = [[UILabel alloc] init];
	nano.font = [self terminalFontOfSize:11 bold:NO];
	nano.textColor = EH17DimGreen();
	nano.text = EH17L(@"nano");
	self.nanoLabel = nano;
	[header addSubview:nano];

	self.hostsTextView = [[UITextView alloc] initWithFrame:CGRectZero];
	self.hostsTextView.font = [self editorFont];
	self.hostsTextView.textColor = EH17Green();
	// Dim green tintColor so selection handles/loupe are visible but subtle.
	self.hostsTextView.tintColor = [EH17DimGreen() colorWithAlphaComponent:0.35];
	self.hostsTextView.layer.cornerRadius = 8;
	self.hostsTextView.clipsToBounds = YES;
	self.hostsTextView.layer.borderWidth = 1.0;
	self.hostsTextView.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.8].CGColor;
	self.hostsTextView.backgroundColor = [UIColor colorWithRed:0.004 green:0.020 blue:0.010 alpha:1.0];
	self.hostsTextView.textContainerInset = UIEdgeInsetsMake(10, 9, 10, 9);
	self.hostsTextView.textContainer.lineFragmentPadding = 0;
	self.hostsTextView.alwaysBounceHorizontal = NO;
	self.hostsTextView.showsHorizontalScrollIndicator = NO;
	self.hostsTextView.indicatorStyle = UIScrollViewIndicatorStyleWhite;
	self.hostsTextView.keyboardAppearance = UIKeyboardAppearanceDark;
	self.hostsTextView.autocorrectionType = UITextAutocorrectionTypeNo;
	self.hostsTextView.autocapitalizationType = UITextAutocapitalizationTypeNone;
	self.hostsTextView.smartDashesType = UITextSmartDashesTypeNo;
	self.hostsTextView.smartQuotesType = UITextSmartQuotesTypeNo;
	self.hostsTextView.delegate = self;
	[header addSubview:self.hostsTextView];

	// Block cursor lives inside the text view so it scrolls with content.
	self.blockCursor = [[UIView alloc] initWithFrame:CGRectZero];
	self.blockCursor.backgroundColor = [EH17Green() colorWithAlphaComponent:0.65];
	self.blockCursor.userInteractionEnabled = NO;
	self.blockCursor.hidden = YES;
	[self.hostsTextView addSubview:self.blockCursor];

	// Scanline overlay sits above the editor frame (screen effect, does not scroll).
	self.scanlines = [[EH17ScanlineView alloc] initWithFrame:CGRectZero];
	[header addSubview:self.scanlines];

	// Draggable resize grip on the editor's bottom border.
	self.resizeHandle = [[UIView alloc] initWithFrame:CGRectZero];
	self.resizeHandle.backgroundColor = UIColor.clearColor;
	UIView *grip = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 34, 4)];
	grip.tag = 7788;
	grip.backgroundColor = [EH17Green() colorWithAlphaComponent:0.8];
	grip.layer.cornerRadius = 2;
	[self.resizeHandle addSubview:grip];
	UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleResizePan:)];
	[self.resizeHandle addGestureRecognizer:pan];
	[header addSubview:self.resizeHandle];

	self.statusLabel = [[UILabel alloc] init];
	self.statusLabel.font = [self terminalFontOfSize:10.5 bold:NO];
	self.statusLabel.textColor = EH17DimGreen();
	self.statusLabel.numberOfLines = 2;
	self.statusLabel.text = EH17L(@"st_persisted");
	[header addSubview:self.statusLabel];

	for (int i = 0; i < 5; i++) [self makeSeparator];

	// Editor heights: load from prefs (persisted across respring/reinstall),
	// falling back to tuned defaults that fit all elements on-screen without
	// scrolling on iPhone 14 Pro Max.
	NSNumber *savedHeight = [[self mutablePrefs] objectForKey:@"EditorHeight"];
	if ([savedHeight isKindOfClass:NSNumber.class] && savedHeight.doubleValue >= 100.0) {
		self.editorHeight = savedHeight.doubleValue;
	} else {
		self.editorHeight = 236.0;   // tuned default: all HOSTS-page elements visible
	}
	NSNumber *savedDomainsH = [[self mutablePrefs] objectForKey:@"PBDomainsHeight"];
	if ([savedDomainsH isKindOfClass:NSNumber.class] && savedDomainsH.doubleValue >= 60.0) {
		self.pbDomainsHeight = savedDomainsH.doubleValue;
	} else {
		self.pbDomainsHeight = 240.0;   // tuned default: all BUILDER-page elements visible
	}

	self.table.tableHeaderView = header;
	[self loadSettingsIntoControls];
	[self layoutEditorHeader];
	[self startCursorBlink];
}

- (UISwitch *)addSwitchToHeader:(UIView *)header title:(NSString *)title action:(SEL)action {
	UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
	// Fixed deterministic tags: 43001 = first switch label, 43002 = second.
	// Builder captions use 43005+, so this range never collides.
	static NSUInteger switchLabelCounter = 0;
	label.tag = 43001 + switchLabelCounter++;
	label.text = title;
	label.font = [self terminalFontOfSize:12.5 bold:NO];
	label.textColor = EH17MidGreen();
	label.adjustsFontSizeToFitWidth = YES;
	label.minimumScaleFactor = 0.65;
	[header addSubview:label];
	UISwitch *control = [[UISwitch alloc] initWithFrame:CGRectZero];
	control.onTintColor = EH17MidGreen();
	control.thumbTintColor = [UIColor colorWithWhite:0.92 alpha:1.0];
	control.backgroundColor = EH17Panel();
	control.layer.cornerRadius = 16;
	control.clipsToBounds = YES;
	control.transform = CGAffineTransformMakeScale(0.82, 0.82);
	[control addTarget:self action:action forControlEvents:UIControlEventValueChanged];
	[header addSubview:control];
	return control;
}

#pragma mark - Profile Builder

// Factory for the Profile Builder text fields. Uses the SAME font, text colour,
// background, corner radius and border as the /etc/hosts editor so every input
// on every page looks identical. Placeholder text is dim-green (matching the
// terminal CRT theme) with the same editorFont so it reads like the hosts editor.
- (UITextField *)makePBFieldPlaceholder:(NSString *)placeholder {
	UITextField *field = [[UITextField alloc] init];
	field.font = [self editorFont];
	field.textColor = EH17Green();
	field.backgroundColor = EH17ScanlineBG();
	field.layer.cornerRadius = 8;
	field.layer.borderWidth = 1.0;
	field.layer.borderColor = [EH17Border() colorWithAlphaComponent:0.8].CGColor;
	field.keyboardAppearance = UIKeyboardAppearanceDark;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.smartDashesType = UITextSmartDashesTypeNo;
	field.smartQuotesType = UITextSmartQuotesTypeNo;
	field.returnKeyType = UIReturnKeyDone;
	field.delegate = self;
	field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 9, 1)];
	field.leftViewMode = UITextFieldViewModeAlways;
	[self setPBFieldPlaceholder:field text:placeholder];
	return field;
}

// Update the coloured placeholder on an existing PB field (called on every
// layout pass + language switch so the placeholder text stays in sync). The
// placeholder uses the same editorFont + a dim-green CRT colour so it looks
// exactly like the /etc/hosts editor's hint text.
- (void)setPBFieldPlaceholder:(UITextField *)field text:(NSString *)text {
	NSMutableAttributedString *ph = [[NSMutableAttributedString alloc] initWithString:text];
	// Dim green with slight transparency for a "placeholder" feel, but still
	// clearly in-theme (not the system grey).
	[ph addAttribute:NSForegroundColorAttributeName value:[EH17DimGreen() colorWithAlphaComponent:0.85] range:NSMakeRange(0, text.length)];
	[ph addAttribute:NSFontAttributeName value:[self editorFont] range:NSMakeRange(0, text.length)];
	field.attributedPlaceholder = ph;
}

// Switch between the HOSTS page and the BUILDER page. layoutEditorHeader hides
// the inactive page's elements via .hidden + .frame=CGRectZero, so each page is
// a clean dedicated screen.
- (void)pageChanged:(UISegmentedControl *)sender {
	self.activePage = sender.selectedSegmentIndex;
	// Resign any active keyboard so the editor doesn't float over the new page.
	[self.view endEditing:YES];
	// Rebuild the bottom table cells: HOSTS page has Apply/Show merged/Respring,
	// BUILDER page has none.
	_specifiers = [self buildLocalizedSpecifiers];
	[self reloadSpecifiers];
	[self layoutEditorHeader];
}

// Any change in the builder fields. Persist to prefs so the config survives
// respring; the transport segment also swaps the server field placeholder.
- (void)pbFieldChanged:(UIControl *)sender {
	[self pbSaveToPrefs];
	[self layoutEditorHeader];
}

- (void)pbSaveToPrefs {
	NSMutableDictionary *prefs = [self mutablePrefs];
	[prefs setObject:(self.pbTransportControl.selectedSegmentIndex == 1 ? @"HTTPS" : @"TLS") forKey:EtcHosts17PrefsPBTransportKey];
	[prefs setObject:(self.pbServerField.text ?: @"") forKey:EtcHosts17PrefsPBServerKey];
	[prefs setObject:(self.pbAddrsField.text ?: @"") forKey:EtcHosts17PrefsPBAddrsKey];
	// Port: clamp 1-65535, 0/blank = use protocol default.
	NSString *portRaw = [self.pbPortField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	NSInteger portVal = portRaw.integerValue;
	if (portVal < 1 || portVal > 65535) portVal = 0;
	[prefs setObject:@(portVal) forKey:EtcHosts17PrefsPBPortKey];
	// Domains are stored as the raw multi-line editor text (one per line) so the
	// big editor round-trips verbatim. pbCreateTapped flattens to comma-sep.
	[prefs setObject:(self.pbDomainsView.text ?: @"") forKey:EtcHosts17PrefsPBDomainsKey];
	[prefs setObject:(self.pbNameField.text ?: @"") forKey:EtcHosts17PrefsPBNameKey];
	[prefs setObject:@(self.pbUseLocalCASwitch.on) forKey:EtcHosts17PrefsPBUseLocalCAKey];
	[self writePrefs:prefs];
}

- (void)pbLoadFromPrefs {
	NSDictionary *prefs = [self mutablePrefs];
	NSString *transport = prefs[EtcHosts17PrefsPBTransportKey];
	self.pbTransportControl.selectedSegmentIndex = [transport isEqualToString:@"HTTPS"] ? 1 : 0;
	self.pbServerField.text = prefs[EtcHosts17PrefsPBServerKey] ?: @"";
	self.pbAddrsField.text = prefs[EtcHosts17PrefsPBAddrsKey] ?: @"";
	NSInteger portVal = [prefs[EtcHosts17PrefsPBPortKey] integerValue];
	self.pbPortField.text = (portVal > 0 && portVal <= 65535) ? [NSString stringWithFormat:@"%ld", (long)portVal] : @"";
	// Backwards-compat: old prefs stored comma-sep; split into lines for the editor.
	NSString *domains = prefs[EtcHosts17PrefsPBDomainsKey] ?: @"";
	if ([domains rangeOfString:@","].length && ![domains containsString:@"\n"]) {
		NSArray *parts = [domains componentsSeparatedByString:@","];
		NSMutableArray *cleaned = [NSMutableArray array];
		for (NSString *p in parts) {
			NSString *t = [p stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
			if (t.length) [cleaned addObject:t];
		}
		domains = [cleaned componentsJoinedByString:@"\n"];
	}
	self.pbDomainsView.text = domains;
	self.pbNameField.text = prefs[EtcHosts17PrefsPBNameKey] ?: @"";
	self.pbUseLocalCASwitch.on = [prefs[EtcHosts17PrefsPBUseLocalCAKey] boolValue];
}

// Build the query-param URL and hand it to Safari. The daemon's /build.mobileconfig
// endpoint assembles the .mobileconfig from these params.
- (void)pbCreateTapped {
	[self.view endEditing:YES];
	[self pbSaveToPrefs];
	BOOL isDoh = self.pbTransportControl.selectedSegmentIndex == 1;
	NSString *server = [self.pbServerField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (!server.length) {
		self.statusLabel.text = EH17L(@"pb_invalid");
		return;
	}
	// Deterministic deterministic UUIDs in the daemon need stable param order,
	// and query values must be URL-encoded (domains/URL contain special chars).
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	[parts addObject:[NSString stringWithFormat:@"proto=%@", isDoh ? @"HTTPS" : @"TLS"]];
	NSString *serverKey = isDoh ? @"url" : @"server";
	[parts addObject:[NSString stringWithFormat:@"%@=%@", serverKey, [self urlEncode:server]]];
	NSString *addrs = [self.pbAddrsField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (addrs.length) [parts addObject:[NSString stringWithFormat:@"addrs=%@", [self urlEncode:addrs]]];
	// Custom port (1-65535). Omitted = the daemon uses the protocol default.
	NSString *portRaw = [self.pbPortField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSInteger portVal = portRaw.integerValue;
	if (portVal >= 1 && portVal <= 65535) [parts addObject:[NSString stringWithFormat:@"port=%ld", (long)portVal]];
	// Flatten the multi-line domains editor to comma-sep for the query param.
	NSString *rawDomains = self.pbDomainsView.text ?: @"";
	NSMutableArray *domainParts = [NSMutableArray array];
	for (NSString *line in [rawDomains componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@"\n\r,"]]) {
		NSString *t = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (t.length) [domainParts addObject:t];
	}
	NSString *domains = [domainParts componentsJoinedByString:@","];
	if (domains.length) [parts addObject:[NSString stringWithFormat:@"domains=%@", [self urlEncode:domains]]];
	NSString *name = [self.pbNameField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	if (name.length) [parts addObject:[NSString stringWithFormat:@"name=%@", [self urlEncode:name]]];
	if (self.pbUseLocalCASwitch.on) [parts addObject:@"ca=local"];
	// cache-buster so Safari does not serve a stale .mobileconfig
	[parts addObject:[NSString stringWithFormat:@"v=%ld", (long)[[NSDate date] timeIntervalSince1970]]];
	NSString *query = [parts componentsJoinedByString:@"&"];
	NSString *urlString = [NSString stringWithFormat:@"http://127.0.0.1:%d/build.mobileconfig?%@", 53580, query];
	NSURL *url = [NSURL URLWithString:urlString];
	self.statusLabel.text = EH17L(@"pb_created");
	__weak typeof(self) weakSelf = self;
	[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
		if (!success) {
			dispatch_async(dispatch_get_main_queue(), ^{
				__strong typeof(weakSelf) strongSelf = weakSelf;
				[strongSelf showAlertWithTitle:EH17L(@"couldnotopen_title") message:EH17L(@"couldnotopen_msg")];
			});
		}
	}];
}

- (NSString *)urlEncode:(NSString *)value {
	// Encode everything except unreserved (A-Za-z0-9-._~) so commas/slashes in
	// URLs and domain lists survive the trip to the daemon intact.
	NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
	return [value stringByAddingPercentEncodingWithAllowedCharacters:allowed] ?: value;
}

#pragma mark - Info tooltips (short tap = sticky, long-press = hold)

- (UIButton *)makeInfoButtonIndex:(NSUInteger)index inHeader:(UIView *)header {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	b.tag = 47000 + (NSInteger)index;
	UIImage *img = [UIImage systemImageNamed:@"info.circle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightRegular]];
	[b setImage:img forState:UIControlStateNormal];
	b.tintColor = EH17MidGreen();
	[b addTarget:self action:@selector(infoButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(infoButtonLongPress:)];
	lp.minimumPressDuration = 0.25;
	[b addGestureRecognizer:lp];
	[header addSubview:b];
	return b;
}

- (void)infoButtonTapped:(UIButton *)sender {
	NSUInteger idx = (NSUInteger)(sender.tag - 47000);
	if (idx >= self.infoKeys.count) return;
	[self showTooltip:EH17L(self.infoKeys[idx]) fromView:sender sticky:YES];
}

- (void)infoButtonLongPress:(UILongPressGestureRecognizer *)gr {
	NSUInteger idx = (NSUInteger)(gr.view.tag - 47000);
	if (idx >= self.infoKeys.count) return;
	if (gr.state == UIGestureRecognizerStateBegan) {
		[self showTooltip:EH17L(self.infoKeys[idx]) fromView:gr.view sticky:NO];
	} else if (gr.state == UIGestureRecognizerStateEnded ||
			   gr.state == UIGestureRecognizerStateCancelled ||
			   gr.state == UIGestureRecognizerStateFailed) {
		[self hideTooltip];
	}
}

- (void)showTooltip:(NSString *)text fromView:(UIView *)anchor sticky:(BOOL)sticky {
	[self hideTooltip];
	UIView *host = self.navigationController.view ?: self.view;
	CGFloat maxW = MIN(host.bounds.size.width - 32.0, 330.0);
	UILabel *lbl = [[UILabel alloc] init];
	lbl.numberOfLines = 0;
	lbl.font = [self terminalFontOfSize:12 bold:NO];
	lbl.textColor = EH17Green();
	lbl.text = text;
	CGSize sz = [lbl sizeThatFits:CGSizeMake(maxW - 20.0, CGFLOAT_MAX)];
	CGFloat w = sz.width + 20.0, h = sz.height + 16.0;

	UIView *bubble = [[UIView alloc] init];
	bubble.backgroundColor = [UIColor colorWithRed:0.02 green:0.08 blue:0.04 alpha:0.98];
	bubble.layer.borderColor = EH17Green().CGColor;
	bubble.layer.borderWidth = 1.0;
	bubble.layer.cornerRadius = 8.0;
	bubble.userInteractionEnabled = NO;

	CGRect a = [anchor convertRect:anchor.bounds toView:host];
	CGFloat x = a.origin.x + a.size.width / 2.0 - w / 2.0;
	if (x < 12.0) x = 12.0;
	if (x + w > host.bounds.size.width - 12.0) x = host.bounds.size.width - 12.0 - w;
	CGFloat y = a.origin.y + a.size.height + 6.0;
	if (y + h > host.bounds.size.height - 12.0) y = a.origin.y - h - 6.0;
	bubble.frame = CGRectMake(x, y, w, h);
	lbl.frame = CGRectMake(10.0, 8.0, w - 20.0, h - 16.0);
	[bubble addSubview:lbl];

	if (sticky) {
		UIControl *dismiss = [[UIControl alloc] initWithFrame:host.bounds];
		dismiss.backgroundColor = UIColor.clearColor;
		[dismiss addTarget:self action:@selector(hideTooltip) forControlEvents:UIControlEventTouchUpInside];
		[host addSubview:dismiss];
		self.tooltipDismisser = dismiss;
	}
	[host addSubview:bubble];
	self.tooltipBubble = bubble;
}

- (void)hideTooltip {
	[self.tooltipBubble removeFromSuperview];
	self.tooltipBubble = nil;
	[self.tooltipDismisser removeFromSuperview];
	self.tooltipDismisser = nil;
}

- (void)toggleLanguage {
	gEH17Lang = [EH17CurrentLang() isEqualToString:@"ru"] ? @"en" : @"ru";
	NSMutableDictionary *prefs = [self mutablePrefs];
	[prefs setObject:gEH17Lang forKey:EtcHosts17PrefsLanguageKey];
	[self writePrefs:prefs];
	[self hideTooltip];
	[self relocalizeUI];
}

- (void)relocalizeUI {
	self.subtitleLabel.text = EH17L(self.activePage == 0 ? @"subtitle" : @"subtitle_builder");
	self.nanoLabel.text = EH17L(@"nano");
	[self updatePresetButtonTitle];
	// Rebuild the localized bottom cells/footer and reload the table sections.
	_specifiers = [self buildLocalizedSpecifiers];
	[self reloadSpecifiers];
	[self layoutEditorHeader];
}

- (void)layoutEditorHeader {
	if (!self.editorHeaderView) return;
	CGFloat width = self.table.bounds.size.width;
	if (width <= 0) width = self.view.bounds.size.width;
	CGFloat margin = 18.0;
	CGFloat contentWidth = MAX(width - (margin * 2.0), 240.0);
	BOOL hostsPage = (self.activePage == 0);

	// Apply the green CRT theme + localized titles to ALL segmented controls on
	// every layout pass (iOS can reset segment appearance after re-adding to the
	// view hierarchy, and language switches must refresh the segment titles).
	EH17ThemeSegment(self.pageControl, @[EH17L(@"tab_hosts"), EH17L(@"tab_builder")]);
	EH17ThemeSegment(self.transportControl, @[EH17L(@"seg_transport_dot"), EH17L(@"seg_transport_doh")]);
	EH17ThemeSegment(self.modeControl, @[EH17L(@"seg_mode_block"), EH17L(@"seg_mode_upstream")]);
	EH17ThemeSegment(self.pbTransportControl, @[EH17L(@"seg_transport_dot"), EH17L(@"seg_transport_doh")]);

	CGFloat y = 10.0;
	self.titleLabel.frame = CGRectMake(margin, y, contentWidth - 52, 24);
	[self.langButton setTitle:[NSString stringWithFormat:@" %@ ", [EH17CurrentLang() isEqualToString:@"ru"] ? @"RU" : @"EN"] forState:UIControlStateNormal];
	self.langButton.frame = CGRectMake(margin + contentWidth - 46, y + 1, 46, 22);
	y += 26;
	self.subtitleLabel.frame = CGRectMake(margin, y, contentWidth, 15); y += 20;

	// Reset ALL separators to zero first. Each page uses a different number of
	// separators; without this reset, separators left over from the OTHER page
	// stayed at their old Y and appeared as ghost lines across the screen.
	for (UIView *line in self.separatorLines) { line.frame = CGRectZero; }

	NSUInteger sep = 0;
	((UIView *)self.separatorLines[sep++]).frame = CGRectMake(0, y, width, 1.0); y += 8;

	// --- Page tab (HOSTS | BUILDER) + (i) hint button on BUILDER page ---
	self.pageControl.selectedSegmentIndex = self.activePage;
	// Reserve room for an (i) button on the right of the tab (BUILDER page only).
	CGFloat tabInfoW = hostsPage ? 0.0 : 28.0;
	CGFloat tabInfoGap = hostsPage ? 0.0 : 6.0;
	self.pageControl.frame = CGRectMake(margin, y, contentWidth - tabInfoW - tabInfoGap, 30);
	UIButton *builderInfoBtn = self.infoButtons.count > 4 ? self.infoButtons[4] : nil;
	if (builderInfoBtn) {
		if (hostsPage) {
			builderInfoBtn.hidden = YES; builderInfoBtn.frame = CGRectZero;
		} else {
			builderInfoBtn.hidden = NO;
			builderInfoBtn.frame = CGRectMake(margin + contentWidth - tabInfoW, y + 1, tabInfoW, 28);
		}
	}
	y += 34;
	((UIView *)self.separatorLines[sep++]).frame = CGRectMake(0, y, width, 1.0); y += 8;

	if (hostsPage) {
		y = [self layoutHostsPageAtY:y margin:margin contentWidth:contentWidth width:width sep:&sep];
	} else {
		y = [self layoutBuilderPageAtY:y margin:margin contentWidth:contentWidth width:width sep:&sep];
	}

	CGRect f = self.editorHeaderView.frame;
	f.size.width = width;
	f.size.height = y;
	self.editorHeaderView.frame = f;
	self.table.tableHeaderView = self.editorHeaderView;
	if (hostsPage) [self updateBlockCursor];
}

// HOSTS page: enable toggle, profile toggle, transport/mode segments, upstream
// field, create-profile button, preset button, nano prompt, hosts editor with
// scanlines + resize grip, status line.
- (CGFloat)layoutHostsPageAtY:(CGFloat)y margin:(CGFloat)margin contentWidth:(CGFloat)contentWidth width:(CGFloat)width sep:(NSUInteger *)sep {
	// Un-hide everything the BUILDER page hid (switches, labels, info buttons,
	// segments, preset button, nano prompt, editor). Builder elements are hidden
	// separately via hideAllBuilderElements below.
	for (UIView *sub in self.editorHeaderView.subviews) {
		if ([sub isKindOfClass:UILabel.class] && sub.tag >= 43001 && sub.tag < 43001 + 1000) sub.hidden = NO;
	}
	for (UISwitch *sw in @[self.enabledSwitch, self.useProfileSwitch]) sw.hidden = NO;
	for (UIButton *info in self.infoButtons) info.hidden = NO;
	self.transportControl.hidden = NO;
	self.modeControl.hidden = NO;
	self.presetButton.hidden = NO;
	self.nanoLabel.hidden = NO;
	// Hide all BUILDER-page elements (they belong to the other page).
	[self hideAllBuilderElements];

	NSArray<UISwitch *> *switches = @[self.enabledSwitch, self.useProfileSwitch];
	NSArray<NSString *> *titles = @[EH17L(@"sw_enable"), EH17L(@"sw_profile_use")];
	NSUInteger labelIndex = 0;
	CGFloat rowH = 30.0;
	for (UIView *subview in self.editorHeaderView.subviews) {
		if ([subview isKindOfClass:UILabel.class] && subview.tag >= 43001 && subview.tag < 43001 + 1000) {
			if (labelIndex < switches.count) {
				UILabel *label = (UILabel *)subview;
				label.text = titles[labelIndex];
				UISwitch *sw = switches[labelIndex];
				CGFloat rowMid = y + rowH / 2.0;
				sw.bounds = CGRectMake(0, 0, 51.0, 31.0);
				CGFloat visualW = 51.0 * 0.82;
				CGFloat swLeft = margin + contentWidth - visualW;
				sw.center = CGPointMake(swLeft + visualW / 2.0, rowMid + 1.5);
				UIButton *info = labelIndex < self.infoButtons.count ? self.infoButtons[labelIndex] : nil;
				info.frame = CGRectMake(swLeft - 28, rowMid - 12.0, 24, 24);
				label.frame = CGRectMake(margin, rowMid - rowH / 2.0, swLeft - 28 - margin - 4, rowH);
				y += rowH;
				labelIndex++;
			}
		}
	}

	BOOL profileOn = self.useProfileSwitch.on;
	CGFloat segRowH = 30.0;
	{
		CGFloat infoW = 24.0, infoGap = 6.0;
		CGFloat segWidth = contentWidth - infoW - infoGap;
		self.transportControl.frame = CGRectMake(margin, y, segWidth, segRowH);
		UIButton *infoT = self.infoButtons.count > 2 ? self.infoButtons[2] : nil;
		infoT.frame = CGRectMake(margin + segWidth + infoGap, y + 3, infoW, infoW);
		y += segRowH + 4;
		self.modeControl.frame = CGRectMake(margin, y, segWidth, segRowH);
		UIButton *infoM = self.infoButtons.count > 3 ? self.infoButtons[3] : nil;
		infoM.frame = CGRectMake(margin + segWidth + infoGap, y + 3, infoW, infoW);
		y += segRowH + 4;
	}
	BOOL upstreamVisible = profileOn && self.modeControl.selectedSegmentIndex == 1;
	UILabel *upstreamLabel = (UILabel *)[self.editorHeaderView viewWithTag:43005];
	if (upstreamVisible) {
		upstreamLabel.hidden = NO;
		upstreamLabel.frame = CGRectMake(margin, y, contentWidth, 14); y += 16;
		self.upstreamField.hidden = NO;
		self.upstreamField.frame = CGRectMake(margin, y, contentWidth, 30); y += 34;
	} else {
		upstreamLabel.hidden = YES;
		upstreamLabel.frame = CGRectZero;
		self.upstreamField.hidden = YES;
		self.upstreamField.frame = CGRectZero;
	}

	y += 4;
	[self.createProfileButton setTitle:EH17L(@"sw_profile") forState:UIControlStateNormal];
	self.createProfileButton.hidden = !self.useProfileSwitch.on;
	if (self.useProfileSwitch.on) {
		self.createProfileButton.frame = CGRectMake(margin, y, contentWidth, 30); y += 36;
	} else {
		self.createProfileButton.frame = CGRectZero;
	}
	((UIView *)self.separatorLines[(*sep)++]).frame = CGRectMake(0, y + 1, width, 1.0); y += 8;

	self.presetButton.frame = CGRectMake(margin, y, contentWidth, 30); y += 36;
	((UIView *)self.separatorLines[(*sep)++]).frame = CGRectMake(0, y - 3, width, 1.0);
	self.nanoLabel.frame = CGRectMake(margin, y, contentWidth, 14); y += 18;

	CGFloat editorMargin = 10.0;
	CGFloat editorWidth = MAX(width - editorMargin * 2.0, 240.0);
	CGFloat editorTop = y;
	CGFloat belowEditor = 6.0 + 1.0 + 5.0 + 26.0;
	CGFloat available = self.table.bounds.size.height;
	if (available <= 0) available = self.view.bounds.size.height;
	CGFloat reserve = 3.0 * 40.0 + 150.0;
	CGFloat autoH = available - reserve - editorTop - belowEditor;
	if (autoH < 130.0) autoH = 130.0;
	CGFloat editorH = self.editorHeight > 0 ? self.editorHeight : autoH;
	CGFloat maxH = available - reserve - editorTop - belowEditor + 40.0;
	if (editorH > maxH && maxH > 130.0) editorH = maxH;
	if (editorH < 100.0) editorH = 100.0;

	self.hostsTextView.hidden = NO;
	self.hostsTextView.frame = CGRectMake(editorMargin, y, editorWidth, editorH);
	self.scanlines.hidden = NO;
	self.scanlines.frame = self.hostsTextView.frame;
	self.resizeHandle.hidden = NO;
	self.resizeHandle.frame = CGRectMake(editorMargin, y + editorH - 11, editorWidth, 22);
	UIView *grip = [self.resizeHandle viewWithTag:7788];
	grip.frame = CGRectMake((editorWidth - 34) / 2.0, 9, 34, 4);
	y += editorH + 6;

	((UIView *)self.separatorLines[(*sep)++]).frame = CGRectMake(0, y, width, 1.0); y += 5;
	self.statusLabel.frame = CGRectMake(margin, y, contentWidth, 26); y += 28;
	return y;
}

// BUILDER page: hint, transport segment, server/addrs/name single-line fields,
// a large multi-line domains editor (scanlines + resize grip, just like the
// hosts editor), CA switch, create button, status line.
- (CGFloat)layoutBuilderPageAtY:(CGFloat)y margin:(CGFloat)margin contentWidth:(CGFloat)contentWidth width:(CGFloat)width sep:(NSUInteger *)sep {
	CGFloat pbFieldH = 28.0, pbCapH = 13.0, pbGap = 3.0;
	UILabel *pbHint = (UILabel *)[self.editorHeaderView viewWithTag:43009];
	UILabel *pbServerCap = (UILabel *)[self.editorHeaderView viewWithTag:43011];
	UILabel *pbAddrsCap = (UILabel *)[self.editorHeaderView viewWithTag:43012];
	UILabel *pbDomainsCap = (UILabel *)[self.editorHeaderView viewWithTag:43013];
	UILabel *pbNameCap = (UILabel *)[self.editorHeaderView viewWithTag:43014];
	UILabel *pbPortCap = (UILabel *)[self.editorHeaderView viewWithTag:43015];
	UILabel *pbCaLabel = (UILabel *)[self.editorHeaderView viewWithTag:43010];
	// The single-line fields have no caption above them anymore (the placeholder
	// is enough). Hide the unused caption labels so they don't leak from a
	// previous layout. pbDomainsCap and pbCaLabel ARE used below.
	pbServerCap.hidden = YES; pbServerCap.frame = CGRectZero;
	pbAddrsCap.hidden = YES; pbAddrsCap.frame = CGRectZero;
	pbPortCap.hidden = YES; pbPortCap.frame = CGRectZero;
	pbNameCap.hidden = YES; pbNameCap.frame = CGRectZero;

	// Hide all HOSTS-page-only elements (so they don't show through). Every one
	// is BOTH hidden AND zeroed — scanlines especially MUST be hidden (not just
	// zeroed) because it overrides drawRect: and would keep painting ghost lines.
	self.hostsTextView.hidden = YES; self.hostsTextView.frame = CGRectZero;
	self.scanlines.hidden = YES; self.scanlines.frame = CGRectZero;
	self.resizeHandle.hidden = YES; self.resizeHandle.frame = CGRectZero;
	self.presetButton.hidden = YES; self.presetButton.frame = CGRectZero;
	self.nanoLabel.hidden = YES; self.nanoLabel.frame = CGRectZero;
	self.upstreamField.hidden = YES; self.upstreamField.frame = CGRectZero;
	UILabel *upstreamLabel = (UILabel *)[self.editorHeaderView viewWithTag:43005];
	upstreamLabel.hidden = YES; upstreamLabel.frame = CGRectZero;
	self.createProfileButton.hidden = YES; self.createProfileButton.frame = CGRectZero;
	// Hide switch labels + switches + info buttons (they are HOSTS-page toggles).
	for (UIView *sub in self.editorHeaderView.subviews) {
		if ([sub isKindOfClass:UILabel.class] && sub.tag >= 43001 && sub.tag < 43001 + 1000) {
			sub.hidden = YES; sub.frame = CGRectZero;
		}
	}
	for (UISwitch *sw in @[self.enabledSwitch, self.useProfileSwitch]) { sw.hidden = YES; }
	for (UIButton *info in self.infoButtons) { info.hidden = YES; info.frame = CGRectZero; }
	self.transportControl.hidden = YES; self.transportControl.frame = CGRectZero;
	self.modeControl.hidden = YES; self.modeControl.frame = CGRectZero;

	// Hint text is now behind the (i) button next to the page tab (infoButtons[4]).
	// Hide the persistent hint label so it no longer takes screen space.
	pbHint.hidden = YES; pbHint.frame = CGRectZero;

	// Transport segment.
	BOOL isDoh = self.pbTransportControl.selectedSegmentIndex == 1;
	self.pbTransportControl.hidden = NO;
	self.pbTransportControl.frame = CGRectMake(margin, y, contentWidth, 30); y += 30 + 8;

	// --- Fields with NO caption labels above them. The placeholder text inside
	// each field already describes what to enter, so a separate caption above
	// was redundant. Only the Domains editor keeps a caption because UITextView
	// has no built-in placeholder. ---

	// Server field.
	NSString *serverCap = EH17L(isDoh ? @"pb_server_doh" : @"pb_server_dot");
	[self setPBFieldPlaceholder:self.pbServerField text:serverCap];
	self.pbServerField.hidden = NO;
	self.pbServerField.frame = CGRectMake(margin, y, contentWidth, pbFieldH); y += pbFieldH + 6;

	// Addrs field.
	NSString *addrsCap = EH17L(@"pb_addrs");
	[self setPBFieldPlaceholder:self.pbAddrsField text:addrsCap];
	self.pbAddrsField.hidden = NO;
	self.pbAddrsField.frame = CGRectMake(margin, y, contentWidth, pbFieldH); y += pbFieldH + 6;

	// Port field.
	NSString *portCap = EH17L(@"pb_port");
	[self setPBFieldPlaceholder:self.pbPortField text:portCap];
	self.pbPortField.hidden = NO;
	self.pbPortField.frame = CGRectMake(margin, y, contentWidth, pbFieldH); y += pbFieldH + 8;

	// Domains caption + LARGE multi-line editor (scanlines + resize grip).
	// UITextView has no placeholder, so this one field keeps its caption.
	NSString *domainsCap = EH17L(@"pb_domains");
	pbDomainsCap.hidden = NO; pbDomainsCap.text = domainsCap;
	pbDomainsCap.frame = CGRectMake(margin, y, contentWidth, pbCapH); y += pbCapH + pbGap;
	CGFloat editorMargin = 10.0;
	CGFloat editorWidth = MAX(width - editorMargin * 2.0, 240.0);
	CGFloat editorTop = y;
	CGFloat belowEditor = 6.0 + pbFieldH + 8.0 + pbFieldH + 8.0 + 34.0 + 26.0; // gap + name + CA + create + status
	CGFloat available = self.table.bounds.size.height;
	if (available <= 0) available = self.view.bounds.size.height;
	CGFloat reserve = 150.0;
	CGFloat autoH = available - reserve - editorTop - belowEditor;
	if (autoH < 100.0) autoH = 100.0;
	CGFloat domH = self.pbDomainsHeight > 0 ? self.pbDomainsHeight : autoH;
	CGFloat maxH = available - reserve - editorTop - belowEditor + 40.0;
	if (domH > maxH && maxH > 100.0) domH = maxH;
	if (domH < 60.0) domH = 60.0;
	self.pbDomainsView.hidden = NO;
	self.pbDomainsView.frame = CGRectMake(editorMargin, y, editorWidth, domH);
	self.pbDomainsScan.hidden = NO;
	self.pbDomainsScan.frame = self.pbDomainsView.frame;
	self.pbDomainsResizeHandle.hidden = NO;
	self.pbDomainsResizeHandle.frame = CGRectMake(editorMargin, y + domH - 11, editorWidth, 22);
	UIView *dGrip = [self.pbDomainsResizeHandle viewWithTag:7789];
	dGrip.frame = CGRectMake((editorWidth - 34) / 2.0, 9, 34, 4);
	y += domH + 8;

	// Name field (no caption).
	NSString *nameCap = EH17L(@"pb_name");
	[self setPBFieldPlaceholder:self.pbNameField text:nameCap];
	self.pbNameField.hidden = NO;
	self.pbNameField.frame = CGRectMake(margin, y, contentWidth, pbFieldH); y += pbFieldH + 8;

	// CA switch row (label needed — it's a toggle, not a text field).
	pbCaLabel.hidden = NO; pbCaLabel.text = EH17L(@"pb_use_local_ca");
	self.pbUseLocalCASwitch.bounds = CGRectMake(0, 0, 51.0, 31.0);
	CGFloat swW = 51.0 * 0.82;
	CGFloat swLeft = margin + contentWidth - swW;
	self.pbUseLocalCASwitch.hidden = NO;
	self.pbUseLocalCASwitch.center = CGPointMake(swLeft + swW / 2.0, y + pbFieldH / 2.0 + 1.5);
	pbCaLabel.frame = CGRectMake(margin, y, swLeft - margin - 6, pbFieldH);
	y += pbFieldH + 8;

	// Create button.
	[self.pbCreateButton setTitle:EH17L(@"pb_create") forState:UIControlStateNormal];
	self.pbCreateButton.hidden = NO;
	self.pbCreateButton.frame = CGRectMake(margin, y, contentWidth, 30); y += 34;

	((UIView *)self.separatorLines[(*sep)++]).frame = CGRectMake(0, y, width, 1.0); y += 5;
	self.statusLabel.frame = CGRectMake(margin, y, contentWidth, 26); y += 28;
	return y;
}

// Hide every BUILDER-page element (used when switching to the HOSTS page so
// nothing from the builder bleeds through).
- (void)hideAllBuilderElements {
	UILabel *pbHint = (UILabel *)[self.editorHeaderView viewWithTag:43009];
	UILabel *pbServerCap = (UILabel *)[self.editorHeaderView viewWithTag:43011];
	UILabel *pbAddrsCap = (UILabel *)[self.editorHeaderView viewWithTag:43012];
	UILabel *pbPortCap = (UILabel *)[self.editorHeaderView viewWithTag:43015];
	UILabel *pbDomainsCap = (UILabel *)[self.editorHeaderView viewWithTag:43013];
	UILabel *pbNameCap = (UILabel *)[self.editorHeaderView viewWithTag:43014];
	UILabel *pbCaLabel = (UILabel *)[self.editorHeaderView viewWithTag:43010];
	NSArray *pbHidden = @[pbHint, self.pbTransportControl, pbServerCap, self.pbServerField,
						  pbAddrsCap, self.pbAddrsField, pbPortCap, self.pbPortField,
						  pbDomainsCap, self.pbDomainsView,
						  self.pbDomainsScan, self.pbDomainsResizeHandle,
						  pbNameCap, self.pbNameField, pbCaLabel, self.pbUseLocalCASwitch,
						  self.pbCreateButton];
	for (UIView *v in pbHidden) { v.hidden = YES; v.frame = CGRectZero; }
}

#pragma mark - Block cursor

- (void)startCursorBlink {
	CAKeyframeAnimation *blink = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
	blink.values = @[@1.0, @1.0, @0.0, @0.0];
	blink.keyTimes = @[@0.0, @0.5, @0.5, @1.0];
	blink.duration = 1.06;
	blink.repeatCount = HUGE_VALF;
	blink.calculationMode = kCAAnimationDiscrete;
	[self.blockCursor.layer addAnimation:blink forKey:@"blink"];
}

- (void)updateBlockCursor {
	UITextView *tv = self.hostsTextView;
	if (!tv.isFirstResponder || !tv.selectedTextRange || !tv.selectedTextRange.empty) {
		self.blockCursor.hidden = YES;
		return;
	}
	self.blockCursor.hidden = NO;
	CGRect caret = [tv caretRectForPosition:tv.selectedTextRange.start];
	CGFloat charW = [@"M" sizeWithAttributes:@{NSFontAttributeName: [self editorFont]}].width;
	if (charW < 4) charW = 8;
	self.blockCursor.frame = CGRectMake(caret.origin.x, caret.origin.y, charW, caret.size.height);
}

- (void)handleResizePan:(UIPanGestureRecognizer *)pan {
	CGFloat ty = [pan translationInView:self.editorHeaderView].y;
	if (pan.state == UIGestureRecognizerStateBegan) {
		self.resizeStartHeight = self.hostsTextView.frame.size.height;
	}
	CGFloat h = self.resizeStartHeight + ty;
	CGFloat available = self.table.bounds.size.height;
	if (available <= 0) available = self.view.bounds.size.height;
	if (h < 100.0) h = 100.0;
	if (h > available - 200.0) h = available - 200.0;
	self.editorHeight = h;
	[self layoutEditorHeader];
	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		NSMutableDictionary *prefs = [self mutablePrefs];
		[prefs setObject:@(self.editorHeight) forKey:@"EditorHeight"];
		[self writePrefs:prefs];
	}
}

// Resize grip for the builder's domains editor — mirrors handleResizePan so both
// editors behave identically.
- (void)handlePBDomainsResizePan:(UIPanGestureRecognizer *)pan {
	CGFloat ty = [pan translationInView:self.editorHeaderView].y;
	if (pan.state == UIGestureRecognizerStateBegan) {
		self.pbDomainsResizeStart = self.pbDomainsView.frame.size.height;
	}
	CGFloat h = self.pbDomainsResizeStart + ty;
	CGFloat available = self.table.bounds.size.height;
	if (available <= 0) available = self.view.bounds.size.height;
	if (h < 60.0) h = 60.0;
	if (h > available - 200.0) h = available - 200.0;
	self.pbDomainsHeight = h;
	[self layoutEditorHeader];
	if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
		NSMutableDictionary *prefs = [self mutablePrefs];
		[prefs setObject:@(self.pbDomainsHeight) forKey:@"PBDomainsHeight"];
		[self writePrefs:prefs];
	}
}

- (void)textViewDidChangeSelection:(UITextView *)textView { if (textView == self.hostsTextView) [self updateBlockCursor]; }
- (void)textViewDidBeginEditing:(UITextView *)textView { if (textView == self.hostsTextView) [self updateBlockCursor]; }
- (void)textViewDidEndEditing:(UITextView *)textView {
	if (textView == self.hostsTextView) {
		self.blockCursor.hidden = YES;
		// Persist edits on keyboard dismiss so they survive a crash or kill.
		[self saveExtraHostsFromEditorShowingError:NO];
		return;
	}
	// pbDomainsView: persist on end-edit so the config survives respring.
	if (textView == self.pbDomainsView) [self pbSaveToPrefs];
}
- (void)scrollViewDidScroll:(UIScrollView *)scrollView { if (scrollView == self.hostsTextView) [self updateBlockCursor]; }

#pragma mark - Upstream field

// Done on the upstream field: commit + resign. Keeps the keyboard from trapping
// the user after they edit the DoT upstream server name.
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
	[textField resignFirstResponder];
	return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField {
	if (textField == self.upstreamField) {
		NSString *value = [textField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!value.length) value = @"dns.google";
		textField.text = value;
		[self saveSettingsFromControls];
		[self sendApplyCommandToDaemon];
		return;
	}
	// Profile Builder fields: persist on end-edit so the config survives respring.
	// (pbDomainsView is a UITextView, handled in textViewDidEndEditing below.)
	if (textField == self.pbServerField || textField == self.pbAddrsField ||
		textField == self.pbPortField || textField == self.pbNameField) {
		[self pbSaveToPrefs];
	}
}

#pragma mark - Cell theming

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
	return 40.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
	return section == 0 ? 6.0 : UITableViewAutomaticDimension;   // trim the gap under the editor header
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
	if ([PSListController instancesRespondToSelector:@selector(tableView:willDisplayCell:forRowAtIndexPath:)]) {
		[super tableView:tableView willDisplayCell:cell forRowAtIndexPath:indexPath];
	}
	cell.backgroundColor = EH17Panel();
	cell.textLabel.font = [self terminalFontOfSize:15 bold:YES];
	cell.textLabel.textColor = EH17Green();
	UIView *selection = [[UIView alloc] initWithFrame:cell.bounds];
	selection.backgroundColor = [EH17Border() colorWithAlphaComponent:0.25];
	cell.selectedBackgroundView = selection;
}

- (void)tableView:(UITableView *)tableView willDisplayFooterView:(UIView *)view forSection:(NSInteger)section {
	if ([PSListController instancesRespondToSelector:@selector(tableView:willDisplayFooterView:forSection:)]) {
		[super tableView:tableView willDisplayFooterView:view forSection:section];
	}
	if ([view isKindOfClass:UITableViewHeaderFooterView.class]) {
		UITableViewHeaderFooterView *footer = (UITableViewHeaderFooterView *)view;
		footer.textLabel.font = [self terminalFontOfSize:10.5 bold:NO];
		footer.textLabel.textColor = EH17DimGreen();
	}
}

#pragma mark - Storage

- (void)ensureStorageDirectory {
	NSFileManager *fm = NSFileManager.defaultManager;
	if (![fm fileExistsAtPath:EtcHosts17Directory]) {
		[fm createDirectoryAtPath:EtcHosts17Directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions: @0755} error:nil];
	}
}

- (NSString *)defaultHostsText {
	return @"# EtcHosts17 supplemental entries\n127.0.0.1 localhost\n# Examples:\n# 0.0.0.0 example.com other.example.com\n# ::1 ipv6.example.com\n";
}

- (void)loadExtraHostsIntoEditor {
	NSDictionary *prefs = [self currentPrefsDictionary];
	NSString *text = [prefs objectForKey:EtcHosts17PrefsHostsKey];
	if (!text.length) {
		text = [NSString stringWithContentsOfFile:EtcHosts17ExtraPath encoding:NSUTF8StringEncoding error:nil];
	}
	if (!text.length) {
		text = [self defaultHostsText];
	}
	self.hostsTextView.text = text;
	[self updatePresetButtonTitle];
	[self applySyntaxHighlightingPreservingSelection:NO];
}

- (NSMutableDictionary *)mutablePrefs {
	NSMutableDictionary *prefs = [[self currentPrefsDictionary] mutableCopy];
	if (!prefs) prefs = [NSMutableDictionary dictionary];
	if (![prefs objectForKey:EtcHosts17PrefsEnabledKey]) [prefs setObject:@YES forKey:EtcHosts17PrefsEnabledKey];
	if (![prefs objectForKey:EtcHosts17PrefsGlobalModeKey]) [prefs setObject:@NO forKey:EtcHosts17PrefsGlobalModeKey];
	if (![prefs objectForKey:EtcHosts17PrefsFallbackKey]) [prefs setObject:@YES forKey:EtcHosts17PrefsFallbackKey];
	if (![prefs objectForKey:EtcHosts17PrefsCreateProfileKey]) [prefs setObject:@NO forKey:EtcHosts17PrefsCreateProfileKey];
	if (![prefs objectForKey:EtcHosts17PrefsUseProfileKey]) [prefs setObject:@NO forKey:EtcHosts17PrefsUseProfileKey];
	if (![prefs objectForKey:EtcHosts17PrefsProfileTransportKey]) [prefs setObject:@"tls" forKey:EtcHosts17PrefsProfileTransportKey];
	if (![prefs objectForKey:EtcHosts17PrefsProfileModeKey]) [prefs setObject:@"block" forKey:EtcHosts17PrefsProfileModeKey];
	if (![prefs objectForKey:EtcHosts17PrefsProfileUpstreamKey]) [prefs setObject:@"dns.google" forKey:EtcHosts17PrefsProfileUpstreamKey];
	if (![prefs objectForKey:EtcHosts17PrefsSelectedPresetKey]) [prefs setObject:@"Default" forKey:EtcHosts17PrefsSelectedPresetKey];
	NSDictionary *presets = [prefs objectForKey:EtcHosts17PrefsPresetsKey];
	if (![presets isKindOfClass:NSDictionary.class]) {
		NSString *text = [prefs objectForKey:EtcHosts17PrefsHostsKey] ?: [self defaultHostsText];
		[prefs setObject:@{@"Default": text} forKey:EtcHosts17PrefsPresetsKey];
	}
	return prefs;
}


- (NSDictionary *)currentPrefsDictionary {
	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:EtcHosts17PrefsPath];
	return [prefs isKindOfClass:NSDictionary.class] ? prefs : nil;
}

- (void)writePrefs:(NSDictionary *)prefs {
	[prefs writeToFile:EtcHosts17PrefsPath atomically:YES];
	chmod(EtcHosts17PrefsPath.fileSystemRepresentation, 0644);
}

- (BOOL)boolPref:(NSString *)key fromPrefs:(NSDictionary *)prefs defaultValue:(BOOL)value {
	id object = [prefs objectForKey:key];
	return [object respondsToSelector:@selector(boolValue)] ? [object boolValue] : value;
}

- (void)loadSettingsIntoControls {
	NSDictionary *prefs = [self mutablePrefs];
	self.enabledSwitch.on = [self boolPref:EtcHosts17PrefsEnabledKey fromPrefs:prefs defaultValue:YES];
	self.useProfileSwitch.on = [self boolPref:EtcHosts17PrefsUseProfileKey fromPrefs:prefs defaultValue:NO];
	NSString *transport = prefs[EtcHosts17PrefsProfileTransportKey];
	self.transportControl.selectedSegmentIndex = [transport isEqualToString:@"https"] ? 1 : 0;
	NSString *mode = prefs[EtcHosts17PrefsProfileModeKey];
	self.modeControl.selectedSegmentIndex = [mode isEqualToString:@"upstream"] ? 1 : 0;
	NSString *upstream = prefs[EtcHosts17PrefsProfileUpstreamKey];
	self.upstreamField.text = upstream.length ? upstream : @"dns.google";
	[self updateDependentControlAppearance];
	[self updatePresetButtonTitle];
	[self pbLoadFromPrefs];
}

- (void)updateDependentControlAppearance {
	BOOL profileOn = self.enabledSwitch.on && self.useProfileSwitch.on;
	CGFloat switchAlpha = self.enabledSwitch.on ? 1.0 : 0.4;
	CGFloat profileAlpha = profileOn ? 1.0 : 0.4;
	self.useProfileSwitch.alpha = switchAlpha;
	self.transportControl.alpha = profileAlpha;
	self.transportControl.userInteractionEnabled = profileOn;
	self.modeControl.alpha = profileAlpha;
	self.modeControl.userInteractionEnabled = profileOn;
	self.upstreamField.alpha = (profileOn && self.modeControl.selectedSegmentIndex == 1) ? 1.0 : 0.4;
	self.upstreamField.userInteractionEnabled = (profileOn && self.modeControl.selectedSegmentIndex == 1);
	// The install button only matters when profile mode is on.
	self.createProfileButton.alpha = profileOn ? 1.0 : 0.4;
	self.createProfileButton.userInteractionEnabled = profileOn;
}

- (void)saveSettingsFromControls {
	NSMutableDictionary *prefs = [self mutablePrefs];
	[prefs setObject:@(self.enabledSwitch.on) forKey:EtcHosts17PrefsEnabledKey];
	[prefs setObject:@(self.useProfileSwitch.on) forKey:EtcHosts17PrefsUseProfileKey];
	[prefs setObject:(self.transportControl.selectedSegmentIndex == 1 ? @"https" : @"tls")
			  forKey:EtcHosts17PrefsProfileTransportKey];
	[prefs setObject:(self.modeControl.selectedSegmentIndex == 1 ? @"upstream" : @"block")
			  forKey:EtcHosts17PrefsProfileModeKey];
	NSString *upstream = [self.upstreamField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	[prefs setObject:(upstream.length ? upstream : @"dns.google") forKey:EtcHosts17PrefsProfileUpstreamKey];
	// Global mode and strict-allowlist were removed: the redirect is always
	// global + additive. Pin the daemon to the safe values so an old plist can
	// never re-enable them.
	[prefs setObject:@NO forKey:EtcHosts17PrefsGlobalModeKey];
	[prefs setObject:@YES forKey:EtcHosts17PrefsFallbackKey];
	[self writePrefs:prefs];
}

// Any change to the transport / mode / upstream segment or field. These shape the
// generated .mobileconfig and how matched hosts are answered; switching transport
// or the host set requires a profile re-install (the install sheet is offered).
- (void)profileOptionChanged:(UIControl *)sender {
	[self saveSettingsFromControls];
	[self updateDependentControlAppearance];
	[self layoutEditorHeader];
	[self sendApplyCommandToDaemon];
	if (sender == self.transportControl || sender == self.modeControl) {
		self.statusLabel.text = EH17L(@"st_profile_ready");
	}
}

- (void)settingSwitchChanged:(UISwitch *)sender {
	[self saveSettingsFromControls];
	[self updateDependentControlAppearance];
	// Re-lay out so the install button shows/hides with profile mode.
	[self layoutEditorHeader];
	[self sendApplyCommandToDaemon];
	if (sender == self.enabledSwitch) {
		self.statusLabel.text = sender.on ? EH17L(@"st_enabled") : EH17L(@"st_disabled");
	} else if (sender == self.useProfileSwitch) {
		if (sender.on) {
			self.statusLabel.text = EH17L(@"st_profile_on");
			// Turning profile mode on only helps once the scoped profile is
			// installed, so hand the user straight into the install flow.
			[self createProfileTapped];
		} else {
			self.statusLabel.text = EH17L(@"st_profile_off");
		}
	} else {
		self.statusLabel.text = EH17L(@"st_saved");
	}
}

// Secondary action: build + install the scoped .mobileconfig on demand.
- (void)createProfileTapped {
	[self saveExtraHostsFromEditorShowingError:NO];
	[self sendHostsTextToDaemon:[self normalizedHostsText:self.hostsTextView.text]];
	[self sendApplyCommandToDaemon];
	[self buildAndInstallProfilePrompting:YES];
}

- (void)createProfileLongPress:(UILongPressGestureRecognizer *)gr {
	if (gr.state == UIGestureRecognizerStateBegan) {
		[self showTooltip:EH17L(@"tip_profile") fromView:self.createProfileButton sticky:NO];
	} else if (gr.state == UIGestureRecognizerStateEnded ||
			   gr.state == UIGestureRecognizerStateCancelled ||
			   gr.state == UIGestureRecognizerStateFailed) {
		[self hideTooltip];
	}
}

- (BOOL)saveExtraHostsFromEditorShowingError:(BOOL)showError {
	[self ensureStorageDirectory];
	NSString *text = [self normalizedHostsText:self.hostsTextView.text ?: @""];
	NSArray<NSString *> *errors = [self validationErrorsForHostsText:text];
	if (errors.count) {
		self.statusLabel.text = EH17L(@"st_invalid");
		if (showError) [self showValidationErrors:errors];
		return NO;
	}
	NSMutableDictionary *prefs = [[self currentPrefsDictionary] mutableCopy];
	if (!prefs) prefs = [NSMutableDictionary dictionary];
	[prefs setObject:@(self.enabledSwitch.on) forKey:EtcHosts17PrefsEnabledKey];
	[prefs setObject:@(self.useProfileSwitch.on) forKey:EtcHosts17PrefsUseProfileKey];
	[prefs setObject:(self.transportControl.selectedSegmentIndex == 1 ? @"https" : @"tls")
			  forKey:EtcHosts17PrefsProfileTransportKey];
	[prefs setObject:(self.modeControl.selectedSegmentIndex == 1 ? @"upstream" : @"block")
			  forKey:EtcHosts17PrefsProfileModeKey];
	NSString *upstream = [self.upstreamField.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	[prefs setObject:(upstream.length ? upstream : @"dns.google") forKey:EtcHosts17PrefsProfileUpstreamKey];
	[prefs setObject:@NO forKey:EtcHosts17PrefsGlobalModeKey];
	[prefs setObject:@YES forKey:EtcHosts17PrefsFallbackKey];
	[prefs setObject:text forKey:EtcHosts17PrefsHostsKey];
	NSString *selected = [prefs objectForKey:EtcHosts17PrefsSelectedPresetKey] ?: @"Default";
	NSMutableDictionary *presets = [[prefs objectForKey:EtcHosts17PrefsPresetsKey] mutableCopy];
	if (!presets) presets = [NSMutableDictionary dictionary];
	[presets setObject:text forKey:selected];
	[prefs setObject:presets forKey:EtcHosts17PrefsPresetsKey];
	[prefs setObject:[NSDate date] forKey:@"LastSaved"];
	[self writePrefs:prefs];
	[text writeToFile:EtcHosts17ExtraPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
	chmod(EtcHosts17ExtraPath.fileSystemRepresentation, 0644);
	self.statusLabel.text = EH17L(@"st_persisted");
	return YES;
}

- (void)updatePresetButtonTitle {
	NSDictionary *prefs = [self mutablePrefs];
	NSString *selected = [prefs objectForKey:EtcHosts17PrefsSelectedPresetKey] ?: @"Default";
	NSString *titleText = [EH17L(@"preset_prefix") stringByAppendingString:selected];
	UIImage *chevron = [UIImage systemImageNamed:@"chevron.down" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:10 weight:UIImageSymbolWeightBold]];
	// NSProcessInfo instead of @available: the linux toolchain's linker has no
	// ___isOSVersionAtLeast, so @available fails to link here.
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
	if ([NSProcessInfo.processInfo isOperatingSystemAtLeastVersion:(NSOperatingSystemVersion){15, 0, 0}]) {
		UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
		NSAttributedString *t = [[NSAttributedString alloc] initWithString:titleText attributes:@{
			NSFontAttributeName: [self terminalFontOfSize:13 bold:YES],
			NSForegroundColorAttributeName: EH17Green()
		}];
		config.attributedTitle = t;
		config.image = chevron;
		config.imagePlacement = NSDirectionalRectEdgeTrailing;
		config.imagePadding = 8.0;
		config.baseForegroundColor = EH17Green();
		config.contentInsets = NSDirectionalEdgeInsetsMake(6, 11, 6, 11);
		self.presetButton.configuration = config;
	} else {
		self.presetButton.titleLabel.font = [self terminalFontOfSize:13 bold:YES];
		[self.presetButton setTitleColor:EH17Green() forState:UIControlStateNormal];
		self.presetButton.tintColor = EH17Green();
		[self.presetButton setTitle:[titleText stringByAppendingString:@"  "] forState:UIControlStateNormal];
		[self.presetButton setImage:chevron forState:UIControlStateNormal];
		self.presetButton.semanticContentAttribute = UISemanticContentAttributeForceRightToLeft;
		self.presetButton.contentEdgeInsets = UIEdgeInsetsMake(6, 11, 6, 11);
	}
#pragma clang diagnostic pop
}

- (void)showPresetMenu {
	[self saveExtraHostsFromEditorShowingError:NO];
	NSMutableDictionary *prefs = [self mutablePrefs];
	NSDictionary *presets = [prefs objectForKey:EtcHosts17PrefsPresetsKey];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:EH17L(@"preset_menu_title") message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	for (NSString *name in [[presets allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]) {
		[sheet addAction:[UIAlertAction actionWithTitle:name style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
			[weakSelf loadPresetNamed:name];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:EH17L(@"preset_add") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf promptAddPreset]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:EH17L(@"preset_rename") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) { [weakSelf promptRenamePreset]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:EH17L(@"preset_delete") style:UIAlertActionStyleDestructive handler:^(__unused UIAlertAction *action) { [weakSelf deleteCurrentPreset]; }]];
	[sheet addAction:[UIAlertAction actionWithTitle:EH17L(@"cancel_btn") style:UIAlertActionStyleCancel handler:nil]];
	sheet.popoverPresentationController.sourceView = self.presetButton;
	sheet.popoverPresentationController.sourceRect = self.presetButton.bounds;
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)loadPresetNamed:(NSString *)name {
	NSMutableDictionary *prefs = [self mutablePrefs];
	NSDictionary *presets = [prefs objectForKey:EtcHosts17PrefsPresetsKey];
	NSString *text = [presets objectForKey:name];
	if (![text isKindOfClass:NSString.class]) return;
	self.hostsTextView.text = text;
	[prefs setObject:name forKey:EtcHosts17PrefsSelectedPresetKey];
	[prefs setObject:text forKey:EtcHosts17PrefsHostsKey];
	[self writePrefs:prefs];
	[self updatePresetButtonTitle];
	[self applySyntaxHighlightingPreservingSelection:NO];
	self.statusLabel.text = EH17L(@"st_preset_loaded");
}

- (void)promptAddPreset {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:EH17L(@"newpreset_title") message:EH17L(@"newpreset_msg") preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.placeholder = EH17L(@"newpreset_ph"); }];
	[alert addAction:[UIAlertAction actionWithTitle:EH17L(@"cancel_btn") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:EH17L(@"save_btn") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		NSString *name = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!name.length) return;
		[weakSelf saveCurrentTextAsPreset:name];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)saveCurrentTextAsPreset:(NSString *)name {
	if (![self saveExtraHostsFromEditorShowingError:YES]) return;
	NSMutableDictionary *prefs = [self mutablePrefs];
	NSMutableDictionary *presets = [[prefs objectForKey:EtcHosts17PrefsPresetsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
	NSString *text = [self normalizedHostsText:self.hostsTextView.text ?: @""];
	[presets setObject:text forKey:name];
	[prefs setObject:presets forKey:EtcHosts17PrefsPresetsKey];
	[prefs setObject:name forKey:EtcHosts17PrefsSelectedPresetKey];
	[prefs setObject:text forKey:EtcHosts17PrefsHostsKey];
	[self writePrefs:prefs];
	[self updatePresetButtonTitle];
	self.statusLabel.text = EH17L(@"st_preset_saved");
}

- (void)promptRenamePreset {
	NSMutableDictionary *prefs = [self mutablePrefs];
	NSString *current = [prefs objectForKey:EtcHosts17PrefsSelectedPresetKey] ?: @"Default";
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:EH17L(@"rename_title") message:current preferredStyle:UIAlertControllerStyleAlert];
	[alert addTextFieldWithConfigurationHandler:^(UITextField *field) { field.text = current; }];
	[alert addAction:[UIAlertAction actionWithTitle:EH17L(@"cancel_btn") style:UIAlertActionStyleCancel handler:nil]];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:EH17L(@"rename_btn") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
		NSString *newName = [alert.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!newName.length) return;
		__strong typeof(weakSelf) strongSelf = weakSelf;
		NSMutableDictionary *mutablePrefs = [strongSelf mutablePrefs];
		NSMutableDictionary *presets = [[mutablePrefs objectForKey:EtcHosts17PrefsPresetsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
		// F18: prevent silent overwrite of a DIFFERENT existing preset.
		if (![newName isEqualToString:current] && [presets objectForKey:newName]) {
			[strongSelf showAlertWithTitle:EH17L(@"rename_title") message:EH17L(@"rename_exists")];
			return;
		}
		NSString *text = [presets objectForKey:current] ?: [strongSelf normalizedHostsText:strongSelf.hostsTextView.text ?: @""];
		[presets removeObjectForKey:current];
		[presets setObject:text forKey:newName];
		[mutablePrefs setObject:presets forKey:EtcHosts17PrefsPresetsKey];
		[mutablePrefs setObject:newName forKey:EtcHosts17PrefsSelectedPresetKey];
		[strongSelf writePrefs:mutablePrefs];
		[strongSelf updatePresetButtonTitle];
	}]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)deleteCurrentPreset {
	NSMutableDictionary *prefs = [self mutablePrefs];
	NSString *current = [prefs objectForKey:EtcHosts17PrefsSelectedPresetKey] ?: @"Default";
	NSMutableDictionary *presets = [[prefs objectForKey:EtcHosts17PrefsPresetsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
	if (presets.count <= 1) {
		[self showAlertWithTitle:EH17L(@"cantdelete_title") message:EH17L(@"cantdelete_msg")];
		return;
	}
	[presets removeObjectForKey:current];
	NSString *next = [[[presets allKeys] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)] firstObject] ?: @"Default";
	[prefs setObject:presets forKey:EtcHosts17PrefsPresetsKey];
	[prefs setObject:next forKey:EtcHosts17PrefsSelectedPresetKey];
	[self writePrefs:prefs];
	[self loadPresetNamed:next];
}

#pragma mark - Editor highlighting / validation

- (void)textViewDidChange:(UITextView *)textView {
	[self applySyntaxHighlightingPreservingSelection:YES];
	[self updateBlockCursor];
}

- (void)applySyntaxHighlightingPreservingSelection:(BOOL)preserveSelection {
	if (self.applyingHighlight) return;
	self.applyingHighlight = YES;
	NSRange selectedRange = self.hostsTextView.selectedRange;
	NSString *text = self.hostsTextView.text ?: @"";
	NSMutableAttributedString *value = [[NSMutableAttributedString alloc] initWithString:text attributes:@{
		NSFontAttributeName: [self editorFont],
		NSForegroundColorAttributeName: EH17MidGreen()
	}];
	UIColor *commentColor = EH17CommentGreen();
	UIColor *ipColor = EH17Green();
	UIColor *hostColor = EH17MidGreen();
	[text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByLines | NSStringEnumerationSubstringNotRequired usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
		NSString *line = [text substringWithRange:substringRange];
		NSUInteger commentOffset = [line rangeOfString:@"#"].location;
		NSUInteger parseLength = line.length;
		if (commentOffset != NSNotFound) {
			NSRange commentRange = NSMakeRange(substringRange.location + commentOffset, line.length - commentOffset);
			[value addAttribute:NSForegroundColorAttributeName value:commentColor range:commentRange];
			parseLength = commentOffset;
		}
		NSString *prefix = [[line substringToIndex:parseLength] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
		if (!prefix.length) return;
		NSRegularExpression *tokenRegex = [NSRegularExpression regularExpressionWithPattern:@"\\S+" options:0 error:nil];
		NSArray<NSTextCheckingResult *> *matches = [tokenRegex matchesInString:line options:0 range:NSMakeRange(0, parseLength)];
		for (NSUInteger i = 0; i < matches.count; i++) {
			NSRange localRange = matches[i].range;
			NSRange absoluteRange = NSMakeRange(substringRange.location + localRange.location, localRange.length);
			if (i == 0) {
				[value addAttribute:NSForegroundColorAttributeName value:ipColor range:absoluteRange];
				[value addAttribute:NSFontAttributeName value:[self terminalFontOfSize:13.5 bold:YES] range:absoluteRange];
			} else {
				[value addAttribute:NSForegroundColorAttributeName value:hostColor range:absoluteRange];
			}
		}
	}];
	self.hostsTextView.attributedText = value;
	if (preserveSelection && selectedRange.location <= value.length) {
		self.hostsTextView.selectedRange = selectedRange;
	}
	self.applyingHighlight = NO;
}

- (NSString *)normalizedHostsText:(NSString *)text {
	NSString *value = text ?: @"";
	value = [value stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
	value = [value stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
	if (value.length && ![value hasSuffix:@"\n"]) value = [value stringByAppendingString:@"\n"];
	return value;
}

- (BOOL)isValidIPLiteral:(NSString *)token {
	const char *raw = token.UTF8String;
	if (!raw || !raw[0]) return NO;
	if ([token containsString:@":"]) {
		struct in6_addr addr6;
		return inet_pton(AF_INET6, raw, &addr6) == 1;
	}
	struct in_addr addr4;
	return inet_pton(AF_INET, raw, &addr4) == 1;
}

- (NSArray<NSString *> *)hostnamesFromText:(NSString *)text {
	NSMutableArray<NSString *> *names = [NSMutableArray array];
	NSMutableSet<NSString *> *seen = [NSMutableSet set];
	NSCharacterSet *ws = NSCharacterSet.whitespaceAndNewlineCharacterSet;
	for (NSString *rawLine in [[self normalizedHostsText:text] componentsSeparatedByString:@"\n"]) {
		NSUInteger c = [rawLine rangeOfString:@"#"].location;
		NSString *code = c == NSNotFound ? rawLine : [rawLine substringToIndex:c];
		NSArray<NSString *> *parts = [code componentsSeparatedByCharactersInSet:ws];
		NSMutableArray<NSString *> *tokens = [NSMutableArray array];
		for (NSString *p in parts) if (p.length) [tokens addObject:p];
		if (tokens.count < 2) continue;
		for (NSUInteger i = 1; i < tokens.count; i++) {
			NSString *host = [tokens[i] lowercaseString];
			if (![seen containsObject:host]) { [seen addObject:host]; [names addObject:host]; }
		}
	}
	return names;
}

- (NSArray<NSString *> *)validationErrorsForHostsText:(NSString *)text {
	NSMutableArray<NSString *> *errors = [NSMutableArray array];
	NSString *value = [self normalizedHostsText:text ?: @""];
	NSCharacterSet *whitespace = NSCharacterSet.whitespaceAndNewlineCharacterSet;
	// RFC 1123: hostnames allow letters, digits, and hyphens (no underscores).
	NSRegularExpression *domainShape = [NSRegularExpression regularExpressionWithPattern:@"^[A-Za-z0-9]([A-Za-z0-9\\-]{0,61}[A-Za-z0-9])?(\\.[A-Za-z0-9]([A-Za-z0-9\\-]{0,61}[A-Za-z0-9])?)*\\.?$" options:0 error:nil];
	NSRegularExpression *tokenRegex = [NSRegularExpression regularExpressionWithPattern:@"\\S+" options:0 error:nil];
	NSArray<NSString *> *lines = [value componentsSeparatedByString:@"\n"];
	for (NSUInteger index = 0; index < lines.count; index++) {
		NSString *rawLine = lines[index];
		NSUInteger commentOffset = [rawLine rangeOfString:@"#"].location;
		NSString *codePart = commentOffset == NSNotFound ? rawLine : [rawLine substringToIndex:commentOffset];
		NSString *line = [codePart stringByTrimmingCharactersInSet:whitespace];
		if (!line.length) continue;
		NSArray<NSTextCheckingResult *> *tokens = [tokenRegex matchesInString:line options:0 range:NSMakeRange(0, line.length)];
		NSUInteger lineNumber = index + 1;
		if (tokens.count < 2) {
			[errors addObject:[NSString stringWithFormat:EH17L(@"invalid_syntax"), (unsigned long)lineNumber]];
			continue;
		}
		NSString *ip = [line substringWithRange:tokens[0].range];
		if (![self isValidIPLiteral:ip]) {
			[errors addObject:[NSString stringWithFormat:EH17L(@"invalid_ip"), (unsigned long)lineNumber, ip]];
			continue;
		}
		for (NSUInteger tokenIndex = 1; tokenIndex < tokens.count; tokenIndex++) {
			NSString *domain = [line substringWithRange:tokens[tokenIndex].range];
			if ([domainShape numberOfMatchesInString:domain options:0 range:NSMakeRange(0, domain.length)] != 1) {
				[errors addObject:[NSString stringWithFormat:EH17L(@"invalid_line"), (unsigned long)lineNumber, domain]];
			}
		}
	}
	return errors;
}

- (void)showValidationErrors:(NSArray<NSString *> *)errors {
	NSUInteger limit = MIN(errors.count, 8);
	NSArray<NSString *> *visible = [errors subarrayWithRange:NSMakeRange(0, limit)];
	NSString *message = [visible componentsJoinedByString:@"\n"];
	if (errors.count > limit) {
		message = [message stringByAppendingFormat:EH17L(@"invalid_more"), (unsigned long)(errors.count - limit)];
	}
	[self showAlertWithTitle:EH17L(@"invalid_title") message:message];
}

#pragma mark - Apply / DNS profile

- (void)applyChanges {
	[self.view endEditing:YES];
	if (![self saveExtraHostsFromEditorShowingError:YES]) return;

	NSError *error = nil;
	NSString *base = [NSString stringWithContentsOfFile:EtcHosts17BasePath encoding:NSUTF8StringEncoding error:nil];
	if (!base.length) base = @"127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n";
	NSString *extra = [self normalizedHostsText:self.hostsTextView.text];
	NSString *merged = self.enabledSwitch.on
		? [NSString stringWithFormat:@"%@\n# EtcHosts17 supplemental entries begin\n%@# EtcHosts17 supplemental entries end\n", [self normalizedHostsText:base], extra]
		: [self normalizedHostsText:base];
	BOOL ok = [merged writeToFile:EtcHosts17MergedPath atomically:YES encoding:NSUTF8StringEncoding error:&error];
	chmod(EtcHosts17MergedPath.fileSystemRepresentation, 0644);

	if (!ok) {
		self.statusLabel.text = EH17L(@"st_apply_failed");
		[self showAlertWithTitle:EH17L(@"applyfailed_title") message:error.localizedDescription ?: EH17L(@"applyfailed_msg")];
		return;
	}
	notify_post(EtcHosts17ApplyNotification);
	[self sendHostsTextToDaemon:extra];
	[self sendApplyCommandToDaemon];
	[self runApplyTool];
	// The system-resolver redirect picks up host edits live via the daemon; the
	// optional .mobileconfig is a separate explicit action (Create DNS-profile).
	self.statusLabel.text = EH17L(@"st_applied");
}

// Create/update the scoped DoT profile. On this device the only DNS override
// that is visible and enforceable in Settings is an installed configuration
// profile (com.apple.dnsSettings.managed), exactly like the NextDNS/AdGuard
// encrypted-DNS profiles. The daemon serves a freshly-generated .mobileconfig
// (bundling the per-device CA + a scoped DoT payload) over localhost HTTP;
// opening it in Safari drops the user straight into the install sheet.
- (void)buildAndInstallProfilePrompting:(BOOL)prompt {
	if (!self.enabledSwitch.on) {
		if (prompt) [self showAlertWithTitle:EH17L(@"nohosts_title") message:EH17L(@"must_enable")];
		return;
	}
	NSArray<NSString *> *names = [self hostnamesFromText:self.hostsTextView.text];
	// localhost never needs a scoped override.
	NSMutableArray<NSString *> *match = [NSMutableArray array];
	for (NSString *n in names) if (![n isEqualToString:@"localhost"]) [match addObject:n];
	if (!match.count) {
		if (prompt) {
			[self showAlertWithTitle:EH17L(@"nohosts_title") message:EH17L(@"nohosts_msg")];
		}
		return;
	}
	// Push the current hosts to the daemon so the served profile matches the
	// editor, then hand the user into the install sheet.
	[self sendHostsTextToDaemon:[self normalizedHostsText:self.hostsTextView.text]];
	[self sendApplyCommandToDaemon];
	self.statusLabel.text = EH17L(@"st_profile_ready");
	if (prompt) {
		[self promptInstallDNSProfile];
	}
}

- (void)promptInstallDNSProfile {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:EH17L(@"install_title")
		message:EH17L(@"install_msg")
		preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[alert addAction:[UIAlertAction actionWithTitle:EH17L(@"install_btn") style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *a) {
		__strong typeof(weakSelf) strongSelf = weakSelf;
		[strongSelf openProfileInstaller];
	}]];
	[alert addAction:[UIAlertAction actionWithTitle:EH17L(@"later_btn") style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

- (void)promptRemoveDNSProfile {
	[self showAlertWithTitle:EH17L(@"removeprofile_title") message:EH17L(@"removeprofile_msg")];
}

- (void)openProfileInstaller {
	// Safari is a separate app, so this is a normal cross-app open (not the
	// self-open no-op that App-Prefs: hits from inside Settings). Safari fetches
	// the profile from the daemon and iOS presents the install flow.
	NSURL *url = [NSURL URLWithString:EtcHosts17ProfileURL];
	if (!url) return;
	__weak typeof(self) weakSelf = self;
	[[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
		if (!success) {
			dispatch_async(dispatch_get_main_queue(), ^{
				__strong typeof(weakSelf) strongSelf = weakSelf;
				[strongSelf showAlertWithTitle:EH17L(@"couldnotopen_title") message:EH17L(@"couldnotopen_msg")];
			});
		}
	}];
}

- (NSString *)resolveToolPath:(NSString *)literal {
	NSString *resolved = [@"/var/jb" stringByAppendingString:literal];
	return [NSFileManager.defaultManager isExecutableFileAtPath:resolved] ? resolved : literal;
}

- (int)spawnTool:(NSString *)literalPath args:(NSArray<NSString *> *)args {
	NSString *toolPath = [self resolveToolPath:literalPath];
	NSMutableArray<NSString *> *argv = [NSMutableArray arrayWithObject:toolPath];
	[argv addObjectsFromArray:args];
	const char **cargv = malloc(sizeof(char *) * (argv.count + 1));
	for (NSUInteger i = 0; i < argv.count; i++) cargv[i] = argv[i].fileSystemRepresentation;
	cargv[argv.count] = NULL;
	pid_t pid = 0;
	int spawnStatus = posix_spawn(&pid, toolPath.fileSystemRepresentation, NULL, NULL, (char *const *)cargv, environ);
	free(cargv);
	if (spawnStatus != 0) return -spawnStatus;
	int waitStatus = 0;
	if (waitpid(pid, &waitStatus, 0) < 0) return -1;
	return WIFEXITED(waitStatus) ? WEXITSTATUS(waitStatus) : -1;
}

- (int)runDNSTool:(NSArray<NSString *> *)args {
	return [self spawnTool:EtcHosts17DNSToolPath args:args];
}

- (void)sendControlPayload:(NSData *)payload {
	int sock = socket(AF_INET, SOCK_DGRAM, 0);
	if (sock < 0) return;
	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(EtcHosts17ControlPort);
	inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
	sendto(sock, payload.bytes, payload.length, 0, (struct sockaddr *)&addr, sizeof(addr));
	close(sock);
}

- (void)sendHostsTextToDaemon:(NSString *)text {
	NSData *body = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
	NSMutableData *payload = [NSMutableData dataWithBytes:"ETCHOSTS17\n" length:11];
	[payload appendData:body];
	[self sendControlPayload:payload];
}

- (void)sendApplyCommandToDaemon {
	[self sendControlPayload:[NSData dataWithBytes:"ETCHOSTS17APPLY\n" length:16]];
}

- (int)runApplyTool {
	return [self spawnTool:EtcHosts17ApplyToolPath args:@[@"apply"]];
}

- (void)respring {
	NSURL *url = [NSURL URLWithString:@"prefs:root=EtcHosts17"];
	id action = [NSClassFromString(@"SBSRelaunchAction") actionWithReason:@"RestartRenderServer" options:SBSRelaunchActionOptionsFadeToBlackTransition targetURL:url];
	[[NSClassFromString(@"FBSSystemService") sharedService] sendActions:[NSSet setWithObject:action] withResult:nil];
}

- (void)openMergedFile {
	NSString *merged = [NSString stringWithContentsOfFile:EtcHosts17MergedPath encoding:NSUTF8StringEncoding error:nil];
	if (!merged.length) merged = EH17L(@"merged_empty");
	[self showAlertWithTitle:EH17L(@"merged_title") message:merged];
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
	[alert addAction:[UIAlertAction actionWithTitle:EH17L(@"ok_btn") style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:alert animated:YES completion:nil];
}

@end
