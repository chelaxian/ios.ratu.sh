// EtcHosts17 core: switch on mDNSResponder's own /etc/hosts engine.
//
// iOS 17 mDNSResponder contains the full macOS /etc/hosts implementation
// (mDNSMacOSXUpdateEtcHosts*, EtcHostsAddNewEntries, a vnode watch on the
// file). main() only runs it when is_apple_internal_build() is true; retail
// builds register a hardcoded localhost/broadcasthost instead. Entries loaded
// by that engine become local-only auth records, which mDNSResponder answers
// before the unicast resolver, encrypted DNS (DoH/DoT) and VPN DNS.
//
// Behaviour by compiled-file state (written by the Settings pane):
//   enabled  - read-only open()/fopen() of /etc/hosts are redirected to the
//              compiled file and mDNSResponder's own locked entry point
//              mDNSMacOSXUpdateEtcHosts() is called once. From then on the
//              daemon watches the file and reloads it on every atomic replace.
//   disabled / missing - nothing is hooked and the engine is never started:
//              mDNSResponder runs exactly as stock with this dylib dormant.
// Switching from enabled to disabled while the engine runs makes
// mDNSResponder exit normally (SIGTERM, its own clean shutdown); launchd starts
// it again at once and the new instance stays dormant. The engine cannot be
// unregistered any other way.
//
// The internal-build flag is not touched. Nothing is written to system
// configuration. Without this dylib mDNSResponder behaves exactly as stock.

#include <dlfcn.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
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
#define EH_DISABLED_MARK "# EtcHosts17 is disabled."
#define EH_RELOAD   "com.ratush.etchosts17.reload"
#define EH_STATE    "com.ratush.etchosts17.state"

// Published state (notify_get_state on EH_STATE), readable from any process:
//   bit 0  hook loaded in mDNSResponder
//   bit 1  hosts engine running on the compiled file
//   bit 2  compiled file missing/unreadable (dormant, stock)
//   bit 3  engine entry point not found on this build (stock)
//   bit 4  disabled in Settings (dormant, stock)
//   bit 5  restarting mDNSResponder to return to stock
//   bits 8-15 errno of the last failed compiled open
//   bits 16-47 mDNSResponder pid
enum { EHLoaded = 1, EHEngineOn = 2, EHNoFile = 4, EHNoSymbol = 8, EHDisabled = 16, EHRestarting = 32 };
enum { EHFileMissing = 0, EHFileDisabled = 1, EHFileEnabled = 2 };

static os_log_t gLog;
static int gStateToken = -1;
static uint64_t gFlags = 0;
static int gLastErr = 0;
static int gHooksInstalled = 0;         // main queue only
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

// Reads the head of the compiled file directly (not through /etc/hosts, so the
// hooks are irrelevant here).
static int EHCompiledFileState(void) {
	int fd = open(EH_COMPILED, O_RDONLY | O_CLOEXEC);
	if (fd < 0) { gLastErr = errno; return EHFileMissing; }
	char buf[4096];
	ssize_t n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n < 0) { gLastErr = errno; return EHFileMissing; }
	buf[n] = 0;
	return strstr(buf, EH_DISABLED_MARK) ? EHFileDisabled : EHFileEnabled;
}

// Look up a (possibly local) symbol in the main executable's LC_SYMTAB. The
// executable is located by MH_EXECUTE because jailbreak-inserted libraries can
// precede it in dyld's image list.
static void *EHFindLocalSymbol(const char *wanted) {
	const struct mach_header_64 *mh = NULL;
	intptr_t slide = 0;
	for (uint32_t i = 0; i < _dyld_image_count(); i++) {
		const struct mach_header_64 *h = (const struct mach_header_64 *)_dyld_get_image_header(i);
		if (h && h->magic == MH_MAGIC_64 && h->filetype == MH_EXECUTE) { mh = h; slide = _dyld_get_image_vmaddr_slide(i); break; }
	}
	if (!mh) return NULL;
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

// Main queue only. Brings mDNSResponder to the state the compiled file asks for.
static void EHSync(void) {
	if (!gUpdateEtcHosts) return;
	int st = EHCompiledFileState();
	gFlags &= ~(uint64_t)(EHNoFile | EHDisabled);

	if (st == EHFileEnabled) {
		if (!gHooksInstalled) {
			gHooksInstalled = 1;
			%init;
		}
		if (!gEngineStarted) {
			gEngineStarted = 1;
			os_log(gLog, "starting mDNSResponder /etc/hosts engine on compiled file");
			gUpdateEtcHosts();
		}
		gFlags |= EHEngineOn;
		EHPublish();
		return;
	}

	gFlags |= (st == EHFileMissing) ? EHNoFile : EHDisabled;
	if (gEngineStarted) {
		// The engine holds its records until the process ends. Exit cleanly;
		// launchd restarts mDNSResponder and the new instance stays dormant.
		gFlags = (gFlags & ~(uint64_t)EHEngineOn) | EHRestarting;
		EHPublish();
		os_log(gLog, "hosts disabled; restarting mDNSResponder to return to stock");
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(300 * NSEC_PER_MSEC)), dispatch_get_main_queue(), ^{
			kill(getpid(), SIGTERM);
		});
		return;
	}
	EHPublish();
}

%ctor {
	gLog = os_log_create("com.ratush.etchosts17", "mdns");
	notify_register_check(EH_STATE, &gStateToken);
	const char *exe = getprogname();
	if (!exe || strcmp(exe, "mDNSResponder") != 0) return;
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
	EHPublish();

	// main() runs CFRunLoopRun() on the main thread after mDNS_Init, so this
	// block executes once the daemon is fully initialised.
	dispatch_async(dispatch_get_main_queue(), ^{ EHSync(); });

	// Posted by the Settings pane after every write of the compiled file.
	int token = 0;
	notify_register_dispatch(EH_RELOAD, &token, dispatch_get_main_queue(), ^(int t) {
		(void)t;
		EHSync();
	});
}

