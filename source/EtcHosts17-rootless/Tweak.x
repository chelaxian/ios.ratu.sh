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
//              mDNSMacOSXUpdateEtcHosts() is called once, for the initial
//              load of the file.
//   disabled / missing - nothing is hooked and the engine is never started:
//              mDNSResponder runs exactly as stock with this dylib dormant.
// Any change while the engine runs (new entries or disabling) makes
// mDNSResponder exit normally (SIGTERM, its own clean shutdown). launchd
// starts it again on the next DNS request and the new instance does a fresh
// initial load (or stays dormant). The engine's incremental reload is not
// relied upon: on iOS 17 it can drop a re-added entry (A -> B -> A loses A once
// the name was cached from unicast DNS), and it cannot unregister itself.
// The restart also flushes the DNS cache, like re-reading hosts on a PC.
//
// Scoped questions: when a NECP policy (per-app VPN, App Split VPN, MDM)
// scopes an app's DNS to one interface, mDNSPlatformGetDNSRoutePolicy() stores
// that interface in q->InterfaceID and LocalOnlyRecordAnswersQuestion() then
// rejects every /etc/hosts record (they are registered on LocalOnly). While the
// engine runs, that function is wrapped: a record owned by the hosts engine
// (RecordCallback == FreeEtcHosts) that was rejected for a scoped question is
// re-checked as if the question were unscoped. Field offsets are read from the
// instructions of this very build; on any mismatch the wrapper is not installed.
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
#include <time.h>
#include <unistd.h>
#include <notify.h>
#include <os/log.h>
#include <dispatch/dispatch.h>
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/nlist.h>
#include <substrate.h>
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
//   bit 6  hosts entries also answer interface-scoped (per-app policy) questions
//   bits 8-15 errno of the last failed compiled open
//   bits 16-47 mDNSResponder pid
//   bits 48-63 16-bit FNV-1a fold of the compiled file the engine loaded
enum { EHLoaded = 1, EHEngineOn = 2, EHNoFile = 4, EHNoSymbol = 8, EHDisabled = 16, EHRestarting = 32, EHScoped = 64 };
enum { EHFileMissing = 0, EHFileDisabled = 1, EHFileEnabled = 2 };
#define EH_MAX_FILE (4u << 20)
#define EH_MIN_UPTIME_NS (11ull * NSEC_PER_SEC)   // launchd throttles respawn of jobs that ran <10 s

static os_log_t gLog;
static int gStateToken = -1;
static uint64_t gFlags = 0;
static int gLastErr = 0;
static int gHooksInstalled = 0;         // main queue only
static int gEngineStarted = 0;          // main queue only
static int gRestartQueued = 0;          // main queue only
static uint16_t gLoadedHash = 0;
static uint32_t gLoadedFull = 0;
static size_t gLoadedLen = 0;
static uint64_t gStartNs = 0;
typedef void (*EHUpdateFn)(void);
static EHUpdateFn gUpdateEtcHosts = NULL;

static void EHPublish(void) {
	if (gStateToken < 0) return;
	uint64_t v = gFlags | ((uint64_t)(gLastErr & 0xff) << 8) | ((uint64_t)(uint32_t)getpid() << 16) | ((uint64_t)gLoadedHash << 48);
	notify_set_state(gStateToken, v);
	notify_post(EH_STATE);
}

static int EHIsHostsPath(const char *path) {
	return path && (strcmp(path, "/etc/hosts") == 0 || strcmp(path, "/private/etc/hosts") == 0);
}

static uint32_t EHHash32(const char *p, size_t n) {
	uint32_t h = 2166136261u;
	for (size_t i = 0; i < n; i++) { h ^= (uint8_t)p[i]; h *= 16777619u; }
	return h;
}

// Reads the compiled file directly (not through /etc/hosts, so the hooks are
// irrelevant here) and reports its state plus a content hash.
static int EHCompiledFileState(uint32_t *outHash, size_t *outLen) {
	int fd = open(EH_COMPILED, O_RDONLY | O_CLOEXEC);
	if (fd < 0) { gLastErr = errno; return EHFileMissing; }
	size_t cap = 64 * 1024, len = 0;
	char *buf = malloc(cap + 1);
	if (!buf) { close(fd); gLastErr = ENOMEM; return EHFileMissing; }
	for (;;) {
		if (len == cap) {
			if (cap >= EH_MAX_FILE) break;
			char *nb = realloc(buf, cap * 2 + 1);
			if (!nb) break;
			buf = nb; cap *= 2;
		}
		ssize_t n = read(fd, buf + len, cap - len);
		if (n < 0) { if (errno == EINTR) continue; gLastErr = errno; close(fd); free(buf); return EHFileMissing; }
		if (n == 0) break;
		len += (size_t)n;
	}
	close(fd);
	buf[len] = 0;
	if (outHash) *outHash = EHHash32(buf, len);
	if (outLen) *outLen = len;
	size_t head = len < 4096 ? len : 4096;
	char saved = buf[head]; buf[head] = 0;
	int st = strstr(buf, EH_DISABLED_MARK) ? EHFileDisabled : EHFileEnabled;
	buf[head] = saved;
	free(buf);
	return st;
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

#pragma mark Scoped questions

static uintptr_t EHStrip(const void *p) {
#if __has_feature(ptrauth_calls)
	return (uintptr_t)ptrauth_strip(p, ptrauth_key_asia);
#else
	return (uintptr_t)p;
#endif
}

static size_t gQIfOff = 0, gRRIfOff = 0, gCbOff = 0;
static uintptr_t gFreeEtcHosts = 0;
typedef unsigned char (*EHLORAQFn)(void *ar, void *q);
static EHLORAQFn gOrigLORAQ = NULL;
static void *gLORAQ = NULL;

static unsigned char EHLocalOnlyRecordAnswersQuestion(void *ar, void *q) {
	unsigned char r = gOrigLORAQ(ar, q);
	if (r || !ar || !q) return r;
	intptr_t *qif = (intptr_t *)((char *)q + gQIfOff);
	intptr_t saved = *qif;
	// Only real interface scopes (positive index). Any (0), LocalOnly, P2P,
	// BLE and the internal marks are negative or zero and stay untouched.
	if (saved <= 0) return r;
	if (EHStrip(*(void **)((char *)ar + gCbOff)) != gFreeEtcHosts) return r;
	*qif = 0;
	r = gOrigLORAQ(ar, q);
	*qif = saved;
	return r;
}

// Reads the q->InterfaceID / rr->InterfaceID offsets from the function's own
// RRAny/interface check and RecordCallback from EtcHostsDeleteOldEntries'
// "rr->RecordCallback == FreeEtcHosts" comparison. All must match.
static int EHPrepareScoped(void) {
	void *lor = EHFindLocalSymbol("_LocalOnlyRecordAnswersQuestion");
	void *freeEH = EHFindLocalSymbol("_FreeEtcHosts");
	void *del = EHFindLocalSymbol("_EtcHostsDeleteOldEntries");
	if (!lor || !freeEH || !del) return 0;
	const uint32_t *ins = (const uint32_t *)EHStrip(lor);
	long rrIf = -1, qIf = -1;
	unsigned arReg = 99, qReg = 99;
	// prologue: mov x19, x0 ... mov x20, x1 (registers vary; find the moves)
	for (int i = 0; i < 24; i++) {
		uint32_t w = ins[i];
		if ((w & 0xFFE0FFE0u) == 0xAA0003E0u) {          // mov xd, xm
			unsigned rm = (w >> 16) & 31, rd = w & 31;
			if (rm == 0 && arReg == 99) arReg = rd;
			if (rm == 1 && qReg == 99) qReg = rd;
		}
	}
	if (arReg == 99 || qReg == 99) return 0;
	// "if (rr->InterfaceID && q->InterfaceID != mDNSInterface_LocalOnly ...":
	//   ldr xA, [ar, #rrIf] ; cbz xA      and   ldr xB, [q, #qIf] ; cmn xB, #2
	for (int i = 0; i < 40 && (rrIf < 0 || qIf < 0); i++) {
		uint32_t w = ins[i], nx = ins[i + 1];
		if ((w & 0xFFC00000u) != 0xF9400000u) continue;
		unsigned rn = (w >> 5) & 31, rt = w & 31;
		long off = (long)(((w >> 10) & 0xFFF) * 8);
		if (rn == arReg && rrIf < 0 && (nx & 0xFF00001Fu) == (0xB4000000u | rt)) rrIf = off;
		else if (rn == qReg && qIf < 0 && (nx & 0xFFFFFFFFu) == (0xB100081Fu | (rt << 5))) qIf = off;
	}
	if (rrIf < 0 || qIf < 0) return 0;
	uintptr_t freeAddr = EHStrip(freeEH);
	const uint32_t *d = (const uint32_t *)EHStrip(del);
	long cb = -1;
	for (int i = 2; i < 512 && cb < 0; i++) {
		uint32_t w = d[i];
		if ((w & 0x9F000000u) != 0x10000000u) continue;  // ADR
		int64_t imm = ((int64_t)((w >> 5) & 0x7FFFF) << 2) | ((w >> 29) & 3);
		if (imm & (1 << 20)) imm -= (1 << 21);
		if ((uintptr_t)((intptr_t)&d[i] + imm) != freeAddr) continue;
		for (int k = 1; k <= 3 && cb < 0; k++) {
			uint32_t p = d[i - k];
			if ((p & 0xFFC00000u) == 0xF9400000u) {
				long off = (long)(((p >> 10) & 0xFFF) * 8);
				if (off >= 0x40 && off <= 0x100) cb = off;
			}
		}
	}
	if (cb < 0) return 0;
	gRRIfOff = (size_t)rrIf; gQIfOff = (size_t)qIf; gCbOff = (size_t)cb; gFreeEtcHosts = freeAddr;
	gLORAQ = lor;
	os_log(gLog, "scoped hosts answers: rr.if=+0x%zx q.if=+0x%zx cb=+0x%zx", gRRIfOff, gQIfOff, gCbOff);
	return 1;
}

// Main queue only. Exits cleanly so launchd starts a fresh instance. Waits
// until the process is old enough for launchd to respawn it without throttling.
static void EHRestart(const char *why) {
	gFlags |= EHRestarting;
	EHPublish();
	if (gRestartQueued) return;
	gRestartQueued = 1;
	uint64_t up = clock_gettime_nsec_np(CLOCK_MONOTONIC) - gStartNs;
	uint64_t delay = 300 * NSEC_PER_MSEC;
	if (up + delay < EH_MIN_UPTIME_NS) delay = EH_MIN_UPTIME_NS - up;
	os_log(gLog, "%{public}s; restarting mDNSResponder in %llu ms", why, (unsigned long long)(delay / NSEC_PER_MSEC));
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay), dispatch_get_main_queue(), ^{
		kill(getpid(), SIGTERM);
	});
}

// Main queue only. Brings mDNSResponder to the state the compiled file asks for.
static void EHSync(void) {
	if (!gUpdateEtcHosts || gRestartQueued) return;
	uint32_t hash = 0;
	size_t len = 0;
	int st = EHCompiledFileState(&hash, &len);

	if (st == EHFileEnabled) {
		if (!gEngineStarted) {
			if (!gHooksInstalled) {
				gHooksInstalled = 1;
				%init;
				if (gLORAQ) {
					MSHookFunction(gLORAQ, (void *)EHLocalOnlyRecordAnswersQuestion, (void **)&gOrigLORAQ);
					if (gOrigLORAQ) gFlags |= EHScoped;
				}
			}
			gEngineStarted = 1;
			gLoadedFull = hash;
			gLoadedLen = len;
			gLoadedHash = (uint16_t)((hash >> 16) ^ hash);
			os_log(gLog, "starting mDNSResponder /etc/hosts engine on compiled file");
			gUpdateEtcHosts();
			gFlags = (gFlags & ~(uint64_t)(EHNoFile | EHDisabled)) | EHEngineOn;
			EHPublish();
			return;
		}
		if (hash == gLoadedFull && len == gLoadedLen) { EHPublish(); return; }
		EHRestart("hosts entries changed");
		return;
	}

	if (gEngineStarted) {
		// The engine holds its records until the process ends.
		EHRestart("hosts disabled");
		return;
	}
	gFlags = (gFlags & ~(uint64_t)(EHNoFile | EHDisabled | EHEngineOn)) | ((st == EHFileMissing) ? EHNoFile : EHDisabled);
	EHPublish();
}

%ctor {
	gLog = os_log_create("com.ratush.etchosts17", "mdns");
	notify_register_check(EH_STATE, &gStateToken);
	const char *exe = getprogname();
	if (!exe || strcmp(exe, "mDNSResponder") != 0) return;
	gStartNs = clock_gettime_nsec_np(CLOCK_MONOTONIC);
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
	if (EHPrepareScoped()) {
#if __has_feature(ptrauth_calls)
		gLORAQ = ptrauth_sign_unauthenticated(ptrauth_strip(gLORAQ, ptrauth_key_asia), ptrauth_key_function_pointer, 0);
#endif
	} else {
		gLORAQ = NULL;
		os_log(gLog, "scoped hosts answers unavailable on this build; unscoped questions only");
	}
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
