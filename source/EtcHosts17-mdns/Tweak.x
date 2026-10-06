// EtcHosts17 v1 core: feed mDNSResponder's own /etc/hosts engine.
//
// mDNSResponder (iOS 17) watches /etc/hosts with open(O_RDONLY|O_EVTONLY) +
// a vnode dispatch source and parses it with fopen("/etc/hosts", "r"). Entries
// become local-only auth records that are answered before the unicast resolver,
// encrypted DNS (DoH/DoT) and VPN DNS are consulted.
//
// This hook redirects ONLY those two read-only opens of /etc/hosts to the
// compiled file. Nothing else in the process changes and no system setting is
// written. If the compiled file is missing or unreadable the original
// /etc/hosts is used, so a broken install degrades to stock behaviour.

#include <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <notify.h>
#include <os/log.h>
#include <dispatch/dispatch.h>

#define EH_COMPILED "/var/jb/var/mobile/Library/EtcHosts17/hosts"
#define EH_RELOAD   "com.ratush.etchosts17.reload"
#define EH_STATE    "com.ratush.etchosts17.state"

static os_log_t gLog;
static volatile int gServedCompiled = -1;   // -1 unknown, 0 stock file, 1 compiled
static int gStateToken = -1;

// Published state (notify_get_state on EH_STATE), readable from any process:
//   bit 0      hook loaded in mDNSResponder
//   bit 1      compiled hosts served on the last open of /etc/hosts
//   bit 2      stock /etc/hosts served (compiled file missing/unreadable)
//   bits 8-15  errno of the failed compiled open
//   bits 16-47 pid of mDNSResponder
static void EHPublish(uint64_t flags, int err) {
	if (gStateToken < 0) return;
	uint64_t v = flags | ((uint64_t)(err & 0xff) << 8) | ((uint64_t)(uint32_t)getpid() << 16);
	notify_set_state(gStateToken, v);
	notify_post(EH_STATE);
}

static int EHIsHostsPath(const char *path) {
	return path && (strcmp(path, "/etc/hosts") == 0 || strcmp(path, "/private/etc/hosts") == 0);
}

%hookf(int, open, const char *path, int flags, ...) {
	mode_t mode = 0;
	if (flags & O_CREAT) {
		va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap);
	}
	if (EHIsHostsPath(path) && (flags & O_ACCMODE) == O_RDONLY && !(flags & O_CREAT)) {
		int fd = %orig(EH_COMPILED, flags, 0);
		if (fd >= 0) {
			gServedCompiled = 1;
			EHPublish(1 | 2, 0);
			os_log(gLog, "open(/etc/hosts) -> compiled fd=%d", fd);
			return fd;
		}
		int err = errno;
		gServedCompiled = 0;
		EHPublish(1 | 4, err);
		os_log(gLog, "compiled hosts unavailable (errno %d), using stock /etc/hosts", err);
	}
	return %orig(path, flags, mode);
}

%hookf(FILE *, fopen, const char *path, const char *fmode) {
	if (EHIsHostsPath(path) && fmode && fmode[0] == 'r' && !strchr(fmode, '+')) {
		FILE *fp = %orig(EH_COMPILED, fmode);
		if (fp) return fp;
	}
	return %orig(path, fmode);
}

%ctor {
	gLog = os_log_create("com.ratush.etchosts17", "mdns");
	os_log(gLog, "EtcHosts17 loaded into mDNSResponder pid=%d", getpid());
	notify_register_check(EH_STATE, &gStateToken);
	EHPublish(1, 0);
	%init;
	// Normal edits replace the compiled file atomically; mDNSResponder's own
	// vnode watch on the open fd sees that and re-reads it. Only when it is
	// watching the stock file (compiled file was absent at start) can it not
	// notice the new file -- then a clean exit lets launchd restart it.
	int token = 0;
	notify_register_dispatch(EH_RELOAD, &token, dispatch_get_main_queue(), ^(int t) {
		(void)t;
		if (gServedCompiled != 1 && access(EH_COMPILED, R_OK) == 0) {
			os_log(gLog, "reload: switching from stock to compiled hosts");
			exit(0);
		}
	});
}
