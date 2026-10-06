// EtcHosts17 v1 core: switch on mDNSResponder's own /etc/hosts engine.
//
// iOS 17 mDNSResponder contains the full macOS /etc/hosts implementation
// (mDNSMacOSXUpdateEtcHosts*, EtcHostsAddNewEntries, a vnode watch on the
// file). main() only runs it when is_apple_internal_build() is true; retail
// builds register a hardcoded localhost/broadcasthost instead. Entries loaded
// by that engine become local-only auth records, which mDNSResponder answers
// before the unicast resolver, encrypted DNS (DoH/DoT) and VPN DNS.
//
// This tweak:
//   1. redirects the read-only open()/fopen() of /etc/hosts to the compiled
//      file written by the Settings pane (sealed system volume stays untouched);
//   2. once the daemon's run loop is up, calls mDNSResponder's own locked entry
//      point mDNSMacOSXUpdateEtcHosts() a single time -- the same call its
//      /etc/hosts change handler makes. From then on mDNSResponder watches the
//      compiled file itself and reloads it on every atomic replace.
// The internal-build flag is not touched, so no other internal behaviour
// (sensitive logging, test trust anchors) is enabled.
//
// Nothing is written to system configuration. Without this dylib (tweak
// removed, jailbreak not active) mDNSResponder behaves exactly as stock.

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <notify.h>
#include <os/log.h>
#include <dispatch/dispatch.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#if __has_feature(ptrauth_calls)
#include <ptrauth.h>
#endif

#define EH_COMPILED "/var/jb/var/mobile/Library/EtcHosts17/hosts"
#define EH_RELOAD   "com.ratush.etchosts17.reload"
#define EH_STATE    "com.ratush.etchosts17.state"

// Published state (notify_get_state on EH_STATE), readable from any process:
//   bit 0  hook loaded in mDNSResponder
//   bit 1  hosts engine started on the compiled file
//   bit 2  compiled file missing/unreadable (engine left off = stock)
//   bit 3  engine entry point not found on this build (stock)
//   bits 8-15 errno of the last failed compiled open
//   bits 16-47 mDNSResponder pid
enum { EHLoaded = 1, EHEngineOn = 2, EHNoFile = 4, EHNoSymbol = 8 };

static os_log_t gLog;
static int gStateToken = -1;
static uint64_t gFlags = 0;
static int gLastErr = 0;
static int gEngineStarted = 0;          // main queue only
typedef void (*EHUpdateFn)(void);
static EHUpdateFn gUpdateEtcHosts = NULL;

static void EHPublish(void) {
	if (gStateToken < 0) return;
	uint64_t v = gFlags | ((uint64_t)(gLastErr & 0xff) << 8) | ((uint64_t)(uint32_t)getpid() << 16);
	notify_set_state(gStateToken, v);
	notify_post(EH_STATE);
}

static int EHIsHostsPath(const char *path) {
	return path && (strcmp(path, "/etc/hosts") == 0 || strcmp(path, "/private/etc/hosts") == 0);
}

// Look up a (possibly local) symbol in the main executable's LC_SYMTAB.
static void *EHFindLocalSymbol(const char *wanted) {
	const struct mach_header_64 *mh = (const struct mach_header_64 *)_dyld_get_image_header(0);
	intptr_t slide = _dyld_get_image_vmaddr_slide(0);
	if (!mh || mh->magic != MH_MAGIC_64) return NULL;
	const struct load_command *lc = (const struct load_command *)(mh + 1);
	const struct symtab_command *symtab = NULL;
	const struct segment_command_64 *linkedit = NULL;
	for (uint32_t i = 0; i < mh->ncmds; i++) {
		if (lc->cmd == LC_SYMTAB) symtab = (const struct symtab_command *)lc;
		else if (lc->cmd == LC_SEGMENT_64 && strcmp(((const struct segment_command_64 *)lc)->segname, SEG_LINKEDIT) == 0)
			linkedit = (const struct segment_command_64 *)lc;
		lc = (const struct load_command *)((const char *)lc + lc->cmdsize);
	}
	if (!symtab || !linkedit) return NULL;
	uintptr_t base = (uintptr_t)slide + linkedit->vmaddr - linkedit->fileoff;
	const struct nlist_64 *syms = (const struct nlist_64 *)(base + symtab->symoff);
	const char *strs = (const char *)(base + symtab->stroff);
	for (uint32_t i = 0; i < symtab->nsyms; i++) {
		const struct nlist_64 *s = &syms[i];
		if ((s->n_type & N_STAB) || (s->n_type & N_TYPE) != N_SECT || s->n_un.n_strx == 0) continue;
		if (strcmp(strs + s->n_un.n_strx, wanted) == 0) return (void *)(s->n_value + (uintptr_t)slide);
	}
	return NULL;
}

// Main queue only. Starts mDNSResponder's hosts engine once, if the compiled
// file is readable. Uses the daemon's own locked entry point.
static void EHStartEngineIfReady(void) {
	if (gEngineStarted || !gUpdateEtcHosts) return;
	if (access(EH_COMPILED, R_OK) != 0) {
		gLastErr = errno;
		gFlags |= EHNoFile;
		EHPublish();
		return;
	}
	gEngineStarted = 1;
	gFlags = (gFlags & ~(uint64_t)EHNoFile) | EHEngineOn;
	os_log(gLog, "starting mDNSResponder /etc/hosts engine on compiled file");
	gUpdateEtcHosts();
	EHPublish();
}

%hookf(int, open, const char *path, int flags, ...) {
	mode_t mode = 0;
	if (flags & O_CREAT) {
		va_list ap; va_start(ap, flags); mode = (mode_t)va_arg(ap, int); va_end(ap);
	}
	if (EHIsHostsPath(path) && (flags & O_ACCMODE) == O_RDONLY && !(flags & O_CREAT)) {
		int fd = %orig(EH_COMPILED, flags, 0);
		if (fd >= 0) return fd;
		gLastErr = errno;
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
	const char *exe = _dyld_get_image_name(0);
	if (!exe || strcmp(exe, "/usr/sbin/mDNSResponder") != 0) return;
	gLog = os_log_create("com.ratush.etchosts17", "mdns");
	notify_register_check(EH_STATE, &gStateToken);
	gFlags = EHLoaded;

	void *fn = EHFindLocalSymbol("_mDNSMacOSXUpdateEtcHosts");
	if (!fn) {
		gFlags |= EHNoSymbol;
		os_log(gLog, "mDNSMacOSXUpdateEtcHosts not found; staying stock");
		EHPublish();
		return;   // no hooks installed at all
	}
#if __has_feature(ptrauth_calls)
	fn = ptrauth_sign_unauthenticated(ptrauth_strip(fn, ptrauth_key_asia), ptrauth_key_function_pointer, 0);
#endif
	gUpdateEtcHosts = (EHUpdateFn)fn;
	%init;
	EHPublish();

	// main() runs CFRunLoopRun() on the main thread after mDNS_Init, so this
	// block executes once the daemon is fully initialised.
	dispatch_async(dispatch_get_main_queue(), ^{ EHStartEngineIfReady(); });

	// Edits replace the compiled file atomically and mDNSResponder's own vnode
	// watch reloads it. The notification only matters when the file appeared
	// after start-up (engine not yet running).
	int token = 0;
	notify_register_dispatch(EH_RELOAD, &token, dispatch_get_main_queue(), ^(int t) {
		(void)t;
		EHStartEngineIfReady();
	});
}
