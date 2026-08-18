#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>

// EtcHosts17 DNS-profile helper (entitlement: com.apple.developer.networking.networkextension = dns-settings).
//
// Usage:
//   etchosts17dns install <server> [matchdomain1,matchdomain2,...]      (DoT, default)
//   etchosts17dns install-doh <serverURL> <serverIP> [matchdomains]     (DoH)
//   etchosts17dns remove
//   etchosts17dns status
//
// A scoped resolver (matchDomains set) only handles the given names, so those
// exact hosts resolve through the local daemon and win over encrypted DNS
// profiles (ControlD DoH/DoT) and VPN DNS -- the /etc/hosts parity we want.
// With no matchdomains it becomes the primary resolver for everything.
//
// iOS requires the user to enable a DNS-settings configuration once in
// Settings > General > VPN & Device Management > DNS. saveToPreferences cannot
// enable it silently; once enabled, later updates preserve the enabled state.
//
// NOTE (iOS 17.0 verified): a managed DoH resolver (ControlD) that is selected
// as primary makes iOS IGNORE all DoT profiles entirely (0 packets ever reach
// :853, even a global DoT profile with public IPs). So when a DoH profile is
// the active primary, our scoped resolver must ALSO be DoH to participate in
// routing. Use install-doh when ControlD/NextDNS/AdGuard (DoH) is the primary.

static int gExit = 2;
static void finish(int code) { gExit = code; CFRunLoopStop(CFRunLoopGetCurrent()); }

static void ehlog(NSString *fmt, ...) {
	va_list ap; va_start(ap, fmt);
	NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
	va_end(ap);
	NSString *stamp = [NSString stringWithFormat:@"%@ [uid=%d] %@\n", [NSDate date], (int)getuid(), line];
	const char *paths[] = {
		"/var/mobile/Library/EtcHosts17/dns.log",
		"/rootfs/private/var/mobile/Library/EtcHosts17/dns.log",
		"/var/tmp/etchosts17.dns.log",
		"/tmp/etchosts17.dns.log",
		NULL
	};
	for (int i = 0; paths[i]; i++) {
		int fd = open(paths[i], O_WRONLY | O_CREAT | O_APPEND, 0644);
		if (fd >= 0) { write(fd, stamp.UTF8String, strlen(stamp.UTF8String)); close(fd); break; }
	}
	fputs(stamp.UTF8String, stderr);
}

int main(int argc, char **argv) {
	@autoreleasepool {
		NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"status";
		ehlog(@"invoked mode=%@ arg2=%s arg3=%s", mode,
			argc > 2 ? argv[2] : "(none)", argc > 3 ? argv[3] : "(none)");
		NEDNSSettingsManager *mgr = [NEDNSSettingsManager sharedManager];
		[mgr loadFromPreferencesWithCompletionHandler:^(NSError *loadErr) {
			if (loadErr) ehlog(@"load error: %@", loadErr.localizedDescription);

			if ([mode isEqualToString:@"status"]) {
				fprintf(stdout, "enabled=%d hasSettings=%d desc=%s\n",
					(int)mgr.isEnabled, (int)(mgr.dnsSettings != nil),
					mgr.localizedDescription.UTF8String ?: "(nil)");
				finish(mgr.isEnabled ? 0 : 3);
				return;
			}
			if ([mode isEqualToString:@"remove"]) {
				if (!mgr.dnsSettings) { fprintf(stdout, "no profile\n"); finish(0); return; }
				[mgr removeFromPreferencesWithCompletionHandler:^(NSError *e) {
					if (e) { fprintf(stderr, "remove: %s\n", e.localizedDescription.UTF8String); finish(1); }
					else { fprintf(stdout, "removed\n"); finish(0); }
				}];
				return;
			}

			// install-doh <serverURL> <serverIP> [matchdomains]
			if ([mode isEqualToString:@"install-doh"]) {
				NSString *urlStr = argc > 2 && argv[2][0] ? [NSString stringWithUTF8String:argv[2]] : @"https://127.0.0.1:8443/dns-query";
				NSString *ip = argc > 3 && argv[3][0] ? [NSString stringWithUTF8String:argv[3]] : @"127.0.0.1";
				Class dohClass = NSClassFromString(@"NEDNSOverHTTPSSettings");
				NEDNSSettings *settings;
				if (dohClass) {
					NEDNSOverHTTPSSettings *doh = [[dohClass alloc] initWithServers:@[ip]];
					doh.serverURL = [NSURL URLWithString:urlStr];
					settings = doh;
					ehlog(@"install-doh url=%@ ip=%@", urlStr, ip);
				} else {
					ehlog(@"NEDNSOverHTTPSSettings unavailable, falling back to TLS");
					settings = [[NEDNSSettings alloc] initWithServers:@[ip]];
				}
				if (argc > 4 && argv[4][0]) {
					NSArray *md = [[NSString stringWithUTF8String:argv[4]] componentsSeparatedByString:@","];
					NSMutableArray *clean = [NSMutableArray array];
					for (NSString *d in md) {
						NSString *t = [d stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
						if (t.length) [clean addObject:t.lowercaseString];
					}
					if (clean.count) { settings.matchDomains = clean; settings.matchDomainsNoSearch = YES; }
				}
				mgr.dnsSettings = settings;
				mgr.localizedDescription = @"EtcHosts17 (/etc/hosts DoH override)";
				[mgr saveToPreferencesWithCompletionHandler:^(NSError *e) {
					BOOL unchanged = e && [e.localizedDescription.lowercaseString containsString:@"unchanged"];
					if (e && !unchanged) { ehlog(@"save error: %@", e.localizedDescription); finish(1); return; }
					[mgr loadFromPreferencesWithCompletionHandler:^(NSError *e2) {
						ehlog(@"saved%@ ok, enabled=%d matchCount=%lu", unchanged ? @"(unchanged)" : @"",
							(int)mgr.isEnabled, (unsigned long)mgr.dnsSettings.matchDomains.count);
						finish(mgr.isEnabled ? 0 : 3);
					}];
				}];
				return;
			}

			// install (DoT) / update
			NSString *server = argc > 2 && argv[2][0] ? [NSString stringWithUTF8String:argv[2]] : @"127.0.0.1";
			NEDNSSettings *settings = [[NEDNSSettings alloc] initWithServers:@[server]];
			if (argc > 3 && argv[3][0]) {
				NSArray *md = [[NSString stringWithUTF8String:argv[3]] componentsSeparatedByString:@","];
				NSMutableArray *clean = [NSMutableArray array];
				for (NSString *d in md) {
					NSString *t = [d stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
					if (t.length) [clean addObject:t.lowercaseString];
				}
				if (clean.count) { settings.matchDomains = clean; settings.matchDomainsNoSearch = YES; }
			}
			mgr.dnsSettings = settings;
			mgr.localizedDescription = @"EtcHosts17 (/etc/hosts override)";
			[mgr saveToPreferencesWithCompletionHandler:^(NSError *e) {
				// "configuration is unchanged" means an identical profile already
				// exists -> treat as success, not failure.
				BOOL unchanged = e && [e.localizedDescription.lowercaseString containsString:@"unchanged"];
				if (e && !unchanged) { ehlog(@"save error: %@", e.localizedDescription); finish(1); return; }
				[mgr loadFromPreferencesWithCompletionHandler:^(NSError *e2) {
					ehlog(@"saved%@ ok, enabled=%d matchCount=%lu", unchanged ? @"(unchanged)" : @"",
						(int)mgr.isEnabled, (unsigned long)mgr.dnsSettings.matchDomains.count);
					finish(mgr.isEnabled ? 0 : 3);  // 3 = saved but needs one-time enable
				}];
			}];
		}];
		CFRunLoopRunInMode(kCFRunLoopDefaultMode, 15.0, false);
		return gExit;
	}
}
