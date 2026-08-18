/*
 * jetsamfix shared core: process lookup by name, config plist parsing,
 * and the memorystatus apply primitives shared by the daemon and the CLI.
 */
#include "jf_core.h"
#include "memorystatus.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/sysctl.h>
#include <sys/types.h>

#include <CoreFoundation/CoreFoundation.h>

/* ---- process lookup -------------------------------------------------- */

pid_t jf_find_pid(const char *name) {
    if (!name || !*name) return 0;
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) == -1) return 0;
    if (size == 0) return 0;
    struct kinfo_proc *procs = (struct kinfo_proc *)malloc(size);
    if (!procs) return 0;
    if (sysctl(mib, 4, procs, &size, NULL, 0) == -1) { free(procs); return 0; }
    pid_t found = 0;
    size_t count = size / sizeof(struct kinfo_proc);
    for (size_t i = 0; i < count; i++) {
        if (strcmp(procs[i].kp_proc.p_comm, name) == 0) {
            found = procs[i].kp_proc.p_pid;
            break;
        }
    }
    free(procs);
    return found;
}

/* ---- memorystatus primitives ----------------------------------------- */

int jf_set_task_limit(pid_t pid, int mb) {
    /* 0 => remove the per-process fatal cap (no limit). */
    return memorystatus_control(MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT,
                                pid, (uint32_t)mb, NULL, 0);
}

int jf_set_priority(pid_t pid, int priority) {
    memorystatus_properties_entry_v1_t props;
    memset(&props, 0, sizeof(props));
    props.version = MEMORYSTATUS_MPE_VERSION_1;
    props.pid = pid;
    props.priority = priority;
    return memorystatus_control(MEMORYSTATUS_CMD_GRP_SET_PROPERTIES, 0,
                                MEMORYSTATUS_FLAGS_GRP_SET_PRIORITY,
                                &props, sizeof(props));
}

int jf_set_priority_and_limit(pid_t pid, int priority, int mb) {
    memorystatus_properties_entry_v1_t props;
    memset(&props, 0, sizeof(props));
    props.version = MEMORYSTATUS_MPE_VERSION_1;
    props.pid = pid;
    props.priority = priority;
    props.limit = mb;
    return memorystatus_control(MEMORYSTATUS_CMD_GRP_SET_PROPERTIES, 0,
                                MEMORYSTATUS_FLAGS_GRP_SET_PRIORITY,
                                &props, sizeof(props));
}

int jf_lenient_enable(int on) {
    uint32_t cmd = on ? MEMORYSTATUS_CMD_AGGRESSIVE_JETSAM_LENIENT_MODE_ENABLE
                      : MEMORYSTATUS_CMD_AGGRESSIVE_JETSAM_LENIENT_MODE_DISABLE;
    return memorystatus_control(cmd, 0, 0, NULL, 0);
}

int jf_lenient_get(void) {
    /* returns 1/0, or -1 on error */
    return memorystatus_control(MEMORYSTATUS_CMD_GET_AGGRESSIVE_JETSAM_LENIENT_MODE,
                                0, 0, NULL, 0);
}

/* ---- config parsing -------------------------------------------------- */

static int cf_bool(CFDictionaryRef d, const char *key, int def) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = CFDictionaryGetValue(d, k);
    int out = def;
    if (v) {
        if (CFGetTypeID(v) == CFBooleanGetTypeID())
            out = CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
        else if (CFGetTypeID(v) == CFNumberGetTypeID()) {
            int n = 0;
            CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n);
            out = n ? 1 : 0;
        }
    }
    if (k) CFRelease(k);
    return out;
}

static int cf_int(CFDictionaryRef d, const char *key, int def) {
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = CFDictionaryGetValue(d, k);
    int out = def;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID())
        CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &out);
    if (k) CFRelease(k);
    return out;
}

int jf_load_config(const char *path, jf_config_t *cfg) {
    memset(cfg, 0, sizeof(*cfg));
    cfg->lenient = 1;
    cfg->interval = 30;
    cfg->count = 0;

    /* Read the file with plain POSIX I/O (avoids CFReadStream quirks on
     * iOS where the stream path can fail under AMFI/sandbox contexts). */
    int fd = open(path, O_RDONLY);
    if (fd < 0) {
        fprintf(stderr, "jf_load_config: open(%s) failed: %s\n", path, strerror(errno));
        return -1;
    }
    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size <= 0) {
        fprintf(stderr, "jf_load_config: fstat failed (size=%lld): %s\n",
                (long long)st.st_size, strerror(errno));
        close(fd);
        return -1;
    }
    size_t fsize = (size_t)st.st_size;
    uint8_t *fbuf = (uint8_t *)malloc(fsize);
    if (!fbuf) { close(fd); return -1; }
    ssize_t n = read(fd, fbuf, fsize);
    close(fd);
    if (n <= 0) {
        fprintf(stderr, "jf_load_config: read failed: %s\n", strerror(errno));
        free(fbuf);
        return -1;
    }

    CFDataRef data = CFDataCreateWithBytesNoCopy(NULL, fbuf, (CFIndex)n, kCFAllocatorMalloc);
    if (!data) { free(fbuf); return -1; }
    CFPropertyListRef pl = CFPropertyListCreateWithData(
        NULL, data, kCFPropertyListImmutable, NULL, NULL);
    CFRelease(data); /* owns fbuf */
    if (!pl) {
        fprintf(stderr, "jf_load_config: CFPropertyListCreateWithData returned NULL\n");
        return -1;
    }
    if (CFGetTypeID(pl) != CFDictionaryGetTypeID()) {
        fprintf(stderr, "jf_load_config: root is not a dict\n");
        CFRelease(pl);
        return -1;
    }

    CFDictionaryRef d = (CFDictionaryRef)pl;
    cfg->lenient = cf_bool(d, "LenientMode", 1);
    cfg->interval = cf_int(d, "Interval", 30);
    if (cfg->interval < 5) cfg->interval = 5;

    CFStringRef tk = CFStringCreateWithCString(NULL, "Targets", kCFStringEncodingUTF8);
    CFTypeRef tv = CFDictionaryGetValue(d, tk);
    if (tk) CFRelease(tk);
    if (tv && CFGetTypeID(tv) == CFArrayGetTypeID()) {
        CFArrayRef arr = (CFArrayRef)tv;
        CFIndex n = CFArrayGetCount(arr);
        if (n > JF_MAX_TARGETS) n = JF_MAX_TARGETS;
        for (CFIndex i = 0; i < n; i++) {
            CFTypeRef e = CFArrayGetValueAtIndex(arr, i);
            if (!e || CFGetTypeID(e) != CFDictionaryGetTypeID()) continue;
            CFDictionaryRef ed = (CFDictionaryRef)e;
            jf_target_t *t = &cfg->targets[cfg->count];
            t->name[0] = '\0';
            t->limit_mb = 0;
            t->priority = -1;
            t->raise_limit = 0;
            t->raise_priority = 0;
            t->pid = 0;

            CFStringRef nk = CFStringCreateWithCString(NULL, "Name", kCFStringEncodingUTF8);
            CFTypeRef nv = CFDictionaryGetValue(ed, nk);
            if (nk) CFRelease(nk);
            if (nv && CFGetTypeID(nv) == CFStringGetTypeID())
                CFStringGetCString((CFStringRef)nv, t->name, sizeof(t->name), kCFStringEncodingUTF8);

            int lim = cf_int(ed, "LimitMB", -1);
            if (lim >= 0) { t->limit_mb = lim; t->raise_limit = 1; }

            int pri = cf_int(ed, "Priority", -1);
            if (pri >= 0) { t->priority = pri; t->raise_priority = 1; }

            if (t->name[0]) cfg->count++;
        }
    }
    CFRelease(pl);
    return 0;
}

/* Populate a sensible hardcoded policy used when no config file is available
 * (e.g. inside the iOS data-container where the prefs path is unreachable).
 * This keeps the daemon self-sufficient even without a readable config. */
void jf_builtin_config(jf_config_t *cfg) {
    memset(cfg, 0, sizeof(*cfg));
    cfg->lenient = 1;
    cfg->interval = 30;
    int i = 0;
    /* SpringBoard: remove the fatal per-process cap, keep Home band (160). */
    snprintf(cfg->targets[i].name, sizeof(cfg->targets[i].name), "SpringBoard");
    cfg->targets[i].priority = 160;
    cfg->targets[i].raise_priority = 1;
    cfg->targets[i].limit_mb = 0;   /* 0 = no per-process fatal cap */
    cfg->targets[i].raise_limit = 1;
    i++;
    /* VPN packet tunnels: raise the ~15MB default hard cap to 256MB. */
    snprintf(cfg->targets[i].name, sizeof(cfg->targets[i].name), "NEPacketTunnelProvider");
    cfg->targets[i].limit_mb = 256;
    cfg->targets[i].raise_limit = 1;
    i++;
    /* backboardd: boost just below SpringBoard's Home band. */
    snprintf(cfg->targets[i].name, sizeof(cfg->targets[i].name), "backboardd");
    cfg->targets[i].priority = 150;
    cfg->targets[i].raise_priority = 1;
    i++;
    cfg->count = i;
}
int jf_apply(const jf_config_t *cfg, FILE *log) {
    int hit = 0;

    if (cfg->lenient) {
        if (jf_lenient_enable(1) == 0) {
            if (log) fprintf(log, "lenient mode: ENABLED\n");
        } else if (log) {
            fprintf(log, "lenient mode: FAILED (%s)\n", strerror(errno));
        }
    }

    for (int i = 0; i < cfg->count; i++) {
        const jf_target_t *t = &cfg->targets[i];
        pid_t pid = jf_find_pid(t->name);
        if (pid <= 0) {
            if (log) fprintf(log, "[%s] not running\n", t->name);
            continue;
        }
        int ok = 1;
        if (t->raise_priority && t->raise_limit) {
            if (jf_set_priority_and_limit(pid, t->priority, t->limit_mb) != 0) ok = 0;
        } else if (t->raise_priority) {
            if (jf_set_priority(pid, t->priority) != 0) ok = 0;
        } else if (t->raise_limit) {
            if (jf_set_task_limit(pid, t->limit_mb) != 0) ok = 0;
        }
        if (ok) {
            hit++;
            if (log) fprintf(log, "[%s] pid=%d priority=%d limit=%dMB -> OK\n",
                             t->name, pid,
                             t->raise_priority ? t->priority : -1,
                             t->raise_limit ? t->limit_mb : -1);
        } else if (log) {
            fprintf(log, "[%s] pid=%d -> FAILED (%s)\n", t->name, pid, strerror(errno));
        }
    }
    return hit;
}
