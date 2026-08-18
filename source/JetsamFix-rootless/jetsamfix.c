/*
 * jetsamfix — command-line front end for the jetsam policy. Shares the same
 * memorystatus core as the daemon and holds the same entitlements so it can
 * query and change limits directly.
 *
 *   jetsamfix status         show lenient mode + a quick pressure note
 *   jetsamfix list [NAME]    dump the jetsam priority list (optionally grep)
 *   jetsamfix apply          apply the config policy once
 *   jetsamfix lenient on|off toggle global aggressive-lenient mode
 */
#include "jf_core.h"
#include "memorystatus.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <sys/sysctl.h>

#define JF_CONFIG_PATH "/var/mobile/Library/Preferences/com.ratush.jetsamfix.plist"

static const char *band_name(int priority) {
    if (priority < 0)            return "default";
    if (priority == 0)           return "idle";
    if (priority <= 30)          return "background";
    if (priority == 90)          return "fg-support";
    if (priority == 100)         return "foreground";
    if (priority == 160)         return "home (SB)";
    if (priority == 180)         return "important";
    if (priority == 190)         return "critical";
    if (priority >= 210)         return "max";
    return "?";
}

static int do_list(const char *grep) {
    /* query the needed size first */
    size_t size = 0;
    if (memorystatus_control(MEMORYSTATUS_CMD_GET_PRIORITY_LIST, 0, 0, NULL, 0) == -1
        && errno != ENOMEM) {
        /* some kernels return the size via the buffer-length-out trick; fall
         * through and try a reasonable fixed buffer */
    }
    size = 8192; /* the priority list is small; a fixed buffer is robust */
    memorystatus_priority_entry_t *buf =
        (memorystatus_priority_entry_t *)malloc(size);
    if (!buf) { fprintf(stderr, "oom\n"); return 1; }

    int r = memorystatus_control(MEMORYSTATUS_CMD_GET_PRIORITY_LIST, 0, 0,
                                 buf, (size_t)size);
    if (r != 0) {
        fprintf(stderr, "GET_PRIORITY_LIST failed: %s\n", strerror(errno));
        free(buf);
        return 1;
    }
    /* the syscall writes entries and returns count via the buffer; we infer
     * count from bytes-written using the struct size. The kernel updates the
     * buffer length through the same arg, so recompute from a fresh query. */
    size_t used = size;
    /* re-query to get exact size if possible */
    int count = (int)(used / sizeof(memorystatus_priority_entry_t));
    /* clamp: the list is typically a few hundred entries max */
    if (count > 1024) count = 1024;

    printf("%-8s %-8s %-12s %s\n", "PID", "PRIO", "BAND", "LIMIT(MB)");
    printf("-------- -------- ------------ ----------\n");
    int shown = 0;
    for (int i = 0; i < count; i++) {
        pid_t pid = buf[i].pid;
        if (pid == 0) break; /* end of list */
        int prio = buf[i].priority;
        int limit = buf[i].limit;
        /* resolve comm name */
        char comm[64] = {0};
        int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_PID, pid };
        struct kinfo_proc kp;
        size_t ks = sizeof(kp);
        if (sysctl(mib, 4, &kp, &ks, NULL, 0) == 0)
            strncpy(comm, kp.kp_proc.p_comm, sizeof(comm) - 1);

        char label[64];
        snprintf(label, sizeof(label), "%s", comm);

        if (grep && !strstr(label, grep) && !strstr(band_name(prio), grep))
            continue;
        printf("%-8d %-8d %-12s %d\n", pid, prio, band_name(prio), limit);
        shown++;
    }
    if (shown == 0) {
        printf("(no matching processes; total entries=%d)\n", count);
    }
    free(buf);
    return 0;
}

static void usage(const char *p) {
    fprintf(stderr,
        "usage: %s <command>\n"
        "  status         show lenient mode + pressure\n"
        "  list [NAME]    dump jetsam priority list (optionally filter)\n"
        "  apply          apply the config policy once\n"
        "  lenient on|off toggle global aggressive-lenient mode\n",
        p);
}

int main(int argc, char *argv[]) {
    if (argc < 2) { usage(argv[0]); return 1; }
    const char *cmd = argv[1];

    if (strcmp(cmd, "status") == 0) {
        int lm = jf_lenient_get();
        printf("aggressive-lenient mode: ");
        if (lm < 0) printf("unknown (%s)\n", strerror(errno));
        else printf("%s\n", lm ? "ON" : "OFF");

        /* rough vm pressure via sysctl */
        int vm_pressure = 0;
        size_t sz = sizeof(vm_pressure);
        if (sysctlbyname("kern.memorystatus_vm_pressure_level",
                         &vm_pressure, &sz, NULL, 0) == 0) {
            const char *lvl = "normal";
            if (vm_pressure == 1) lvl = "warn";
            else if (vm_pressure == 2) lvl = "urgent";
            else if (vm_pressure == 3) lvl = "critical";
            printf("vm pressure: %s (%d)\n", lvl, vm_pressure);
        }
        return 0;
    }

    if (strcmp(cmd, "list") == 0) {
        return do_list(argc > 2 ? argv[2] : NULL);
    }

    if (strcmp(cmd, "apply") == 0) {
        jf_config_t cfg;
        if (jf_load_config(JF_CONFIG_PATH, &cfg) != 0) {
            fprintf(stderr, "no config at %s; using built-in defaults\n", JF_CONFIG_PATH);
            jf_builtin_config(&cfg);
        }
        int hit = jf_apply(&cfg, stdout);
        printf("applied; targets hit=%d/%d\n", hit, cfg.count);
        return 0;
    }

    if (strcmp(cmd, "lenient") == 0) {
        if (argc < 3) { usage(argv[0]); return 1; }
        int on = (strcmp(argv[2], "on") == 0);
        if (jf_lenient_enable(on) != 0) {
            fprintf(stderr, "failed: %s\n", strerror(errno));
            return 1;
        }
        printf("aggressive-lenient mode: %s\n", on ? "ON" : "OFF");
        return 0;
    }

    usage(argv[0]);
    return 1;
}
