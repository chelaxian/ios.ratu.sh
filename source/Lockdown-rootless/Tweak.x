// Dopamine rootless port of roothide/lockdown eab851c7ac6b295cd418882f3270c1fde4f8cc6e.
// GPL-3.0; original author: roothide. Port: chelaxian, 2026-10-19.
/*
 * lockdown — JSC Security Hardening Tweak for WebContent Process
 *
 * Hardens JavaScriptCore against exploit primitives (addrof/fakeobj,
 * JIT type confusion, GC UAF) by enforcing security-relevant JSC
 * Options and runtime state before the first VM is created.
 *
 * Three enforcement layers:
 *   1. Environment variables (JSC_*) — set before JSC reads them
 *   2. Hook Options::initialize() — programmatic setOption() after init
 *   3. Hook JSGlobalObject::init() — force haveABadTime() at runtime
 *
 * Security levels (compile-time; no preference UI in upstream):
 *   0 — Disabled
 *   1 — Balanced: GC hardened, DoubleShape eliminated
 *   2 — Strict:   + DFG disabled, FTL disabled, generational GC disabled
 *   3 — Maximum:  + all JIT disabled, IC disabled
 */

#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <libgen.h>
#include <sys/time.h>
#include <mach-o/dyld.h>
#include <substrate.h>
#include <ptrauth.h>
#include <limits.h>
#include <time.h>
#include <os/log.h>

// ============================================================
// Configuration
// ============================================================

static int g_WebContent_level = 1;

// ============================================================
// Logging (unified log; no sandbox file access required)
// ============================================================

// Unified logging works without writing into a sandboxed filesystem.
#define LOG(fmt, ...) os_log_with_type(OS_LOG_DEFAULT, OS_LOG_TYPE_DEFAULT, "[lockdown-rootless] " fmt, ##__VA_ARGS__)

// ============================================================
// Unified options table (single source of truth)
// ============================================================
// Each entry is {name, value, min_level}.
// Phase 1 sets env var  "JSC_<name>" = "<value>"
// Phase 2 calls setOption("<name>=<value>")
//
// NOTE: some options (alwaysHaveABadTime, ...) doesn't
// exist on old JSC — they are NOT in this table. DoubleShape elimination
// is achieved via direct haveABadTime() hook in Phase 3.

typedef struct { const char *name; const char *value; int min_level; } opt_entry;

static const opt_entry kOptions[] = {
    // Level 1: core hardening
	// { "alwaysHaveABadTime", "true",  1 },  // eliminate DoubleShape → no addrof/fakeobj
    { "forceGCSlowPaths",  "true",  1 },   // GC slow path → more safety checks
    { "useConcurrentGC",   "false", 1 },   // no GC races (CVE-2025-43529)
    // useAccessInlining = false
    // usePolymorphicAccessInlining = false
    // forcePolyProto = true
    // useArrayAllocationProfiling = false
    // Level 2: disable JIT speculation
    { "useDFGJIT",         "false", 2 },   // no speculative opt (CVE-2025-31277)
    { "useFTLJIT",         "false", 2 },   // disable most aggressive JIT tier
    { "useGenerationalGC", "false", 2 },   // simplify GC
    // Level 3: full JIT lockdown
    { "useLLInt",          "true",  3 },
    { "useLLIntICs",       "false", 3 },    // no interpreter inline caches
    { "useBaselineJIT",    "false", 3 },
    { "useBBQJIT",         "false", 3 },
    { "useOMGJIT",         "false", 3 },
    { "useDOMJIT",         "false", 3 },
    { "useRegExpJIT",      "false", 3 },
    { "useJITCage",        "false", 3 },
    { "useConcurrentJIT",  "false", 3 },
    { NULL, NULL, 0 }
};

// ============================================================
// Phase 1: Set JSC_* environment variables
// ============================================================

static void setJSCEnvVars(void) {
    char envname[64];
    for (const opt_entry *o = kOptions; o->name; o++) {
        if (o->min_level > g_WebContent_level) continue;
        snprintf(envname, sizeof(envname), "JSC_%s", o->name);
        setenv(envname, o->value, 1);
    }
	LOG("JSC_* env vars set");
}

// ============================================================
// Phase 2: Hook Options::initialize()
// ============================================================

static bool (*JSC_Options_setOption1)(const char *) = NULL;
static bool (*JSC_Options_setOption2)(const char *, bool) = NULL;
static void (*JSC_Options_notifyOptionsChanged)(void) = NULL;

static bool JSC_Options_setOption(const char *arg) {
	if (JSC_Options_setOption2)
		return JSC_Options_setOption2(arg, false);
	else if (JSC_Options_setOption1)
		return JSC_Options_setOption1(arg);
	else
		return false;
}

static void applyOptions(const char *tag) {
    char buf[128];
    for (const opt_entry *o = kOptions; o->name; o++) {
        if (o->min_level > g_WebContent_level) continue;
        snprintf(buf, sizeof(buf), "%s=%s", o->name, o->value);
        bool ok = JSC_Options_setOption(buf);
        LOG("  %{public}s setOption(\"%{public}s\") -> %{public}s", tag, buf, ok ? "OK" : "FAIL");
    }
}

static void (*orig_JSC_Options_initialize)(void) = NULL;
static void hookd_JSC_Options_initialize(void) {

    orig_JSC_Options_initialize();
    LOG("Options::initialize() returned (level %d)", g_WebContent_level);

	if (g_WebContent_level <= 0) return;

    // Post-init: reinforce via setOption (env vars already applied by init)
    applyOptions("post-init");
	
    if (JSC_Options_notifyOptionsChanged) 
		JSC_Options_notifyOptionsChanged();
}

// ============================================================
// Phase 3: Hook JSGlobalObject::init() → haveABadTime()
// ============================================================
// alwaysHaveABadTime doesn't exist in old JSC. We call
// haveABadTime(VM&) directly after each JSGlobalObject::init()
// to eliminate DoubleShape → blocks addrof/fakeobj primitives.
// C++ ABI (ARM64): this=x0, vm=x1

static void (*orig_JSC_JSGlobalObject_init)(void *this, void *vm) = NULL;
static void (*JSC_JSGlobalObject_haveABadTime)(void *this, void *vm) = NULL;

static void hooked_JSC_JSGlobalObject_init(void *this, void *vm) {
    orig_JSC_JSGlobalObject_init(this, vm);
    if (JSC_JSGlobalObject_haveABadTime && g_WebContent_level >= 1) {
        JSC_JSGlobalObject_haveABadTime(this, vm);
		static unsigned int g_haveBadTime_count = 0;
        unsigned int count = __atomic_add_fetch(&g_haveBadTime_count, 1, __ATOMIC_RELAXED);
        if (count <= 5)
            LOG("haveABadTime() on globalObj=%p (#%u)", this, count);
    }
}

// ============================================================
// Constructor
// ============================================================

/*
libhooker's MSFindSymbol doesn't sign function pointers at all, 
while rootless/ellekit's MSFindSymbol signs only all exported symbols(even data pointers). 
the new roothide/ellekit implements signing only all code pointers (whether exported or private).
this helper function is compatible with all of these.
*/
static void* FindAndSignFunction(MSImageRef image, const char *symbol) {
	void *sym = MSFindSymbol(image, symbol);
	if (!sym) {
		LOG("Symbol not found: %{public}s", symbol);
		return NULL;
	}
	return ptrauth_sign_unauthenticated(ptrauth_strip(sym, ptrauth_key_function_pointer), ptrauth_key_function_pointer, 0);
}

%ctor {

    char executablePath[PATH_MAX]={0};
    uint32_t size = sizeof(executablePath);
    if (_NSGetExecutablePath(executablePath, &size) != 0) return;
    
    if(strcmp(basename(executablePath), "xpcproxy") == 0)
    {
        return;
    }

    if(strcmp(basename(executablePath), "com.apple.WebKit.WebContent") != 0)
    {
        return;
    }

    if (g_WebContent_level <= 0) { LOG("Disabled (level 0)"); return; }
    LOG("Starting — level %d", g_WebContent_level);

    MSImageRef JavaScriptCore = MSGetImageByName("/System/Library/Frameworks/JavaScriptCore.framework/JavaScriptCore");
    if(!JavaScriptCore) {
        LOG("JavaScriptCore framework not found");
        LOG("Unsupported JavaScriptCore; hooks disabled");
        return;
    }

    // Phase 2: hook Options::initialize()
    JSC_Options_setOption1 = FindAndSignFunction(JavaScriptCore, "__ZN3JSC7Options9setOptionEPKc"); // ios15.1
    JSC_Options_setOption2 = FindAndSignFunction(JavaScriptCore, "__ZN3JSC7Options9setOptionEPKcb"); // ios16.4
    JSC_Options_notifyOptionsChanged = FindAndSignFunction(JavaScriptCore, "__ZN3JSC7Options20notifyOptionsChangedEv"); // ios16.4
    if(!JSC_Options_setOption1 && !JSC_Options_setOption2) {
        LOG("Unsupported JavaScriptCore; hooks disabled");
        return;
    }
    void* JSC_Options_initialize = FindAndSignFunction(JavaScriptCore, "__ZN3JSC7Options10initializeEv");
    void* JSC_JSGlobalObject_init = FindAndSignFunction(JavaScriptCore, "__ZN3JSC14JSGlobalObject4initERNS_2VME");
    JSC_JSGlobalObject_haveABadTime = FindAndSignFunction(JavaScriptCore, "__ZN3JSC14JSGlobalObject12haveABadTimeERNS_2VME");
    // Resolve the entire capability set before changing environment or code.
    if (!JSC_Options_initialize || !JSC_JSGlobalObject_init || !JSC_JSGlobalObject_haveABadTime) {
        LOG("Required JSC symbols missing; protection inactive in this process");
        return;
    }
    setJSCEnvVars();
    MSHookFunction(JSC_Options_initialize, (void *)hookd_JSC_Options_initialize, (void **)&orig_JSC_Options_initialize);
    MSHookFunction(JSC_JSGlobalObject_init, (void *)hooked_JSC_JSGlobalObject_init, (void **)&orig_JSC_JSGlobalObject_init);
    LOG("Hooks installed (level %d); runtime enforcement awaits JSC initialization", g_WebContent_level);
}
