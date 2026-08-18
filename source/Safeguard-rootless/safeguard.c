/*
 * safeguard — command-line front end. Shares the detection core with the
 * daemon and runs unprivileged-ish (it reads pressure/RSS; the kill path
 * needs root like the daemon).
 *
 *   safeguard status            show zone + pressure + top hogs + posture
 *   safeguard top [N]           top-N processes by RSS
 *   safeguard check             one-shot detect pass (dry-run style)
 *   safeguard probe             run the Phase-0 namespace probe
 *   safeguard kill <name|pid>   manually SIGKILL (allowlist enforced)
 *   safeguard arm               SIGUSR1 the daemon -> resume auto-kill
 *   safeguard disarm            SIGUSR2 the daemon -> suspend auto-kill
 */
#include "sg_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>

static const char *zone_name(sg_zone_t z) {
    switch (z) {
        case SG_ZONE_RED:   return "RED";
        case SG_ZONE_AMBER: return "AMBER";
        default:            return "GREEN";
    }
}

static int cmd_status(void) {
    sg_config_t cfg;
    sg_builtin_config(&cfg);

    sg_pressure_t pr;
    if (sg_read_pressure(&pr) != 0) {
        fprintf(stderr, "pressure read failed: %s\n", strerror(errno));
        return 1;
    }
    pr.zone = sg_classify(&cfg, &pr);

    const char *vml[] = { "normal", "warn", "urgent", "critical" };
    printf("zone:       %s\n", zone_name(pr.zone));
    printf("free:       %llu MB  (free+purgeable)\n", (unsigned long long)pr.free_mb);
    printf("swapouts:   %llu\n", (unsigned long long)pr.swapouts);
    printf("vm level:   %s (%d)\n",
           pr.vm_level >= 0 && pr.vm_level <= 3 ? vml[pr.vm_level] : "?", pr.vm_level);
    printf("thresholds: red<%dMB amber<%dMB\n", cfg.red_mb, cfg.amber_mb);
    printf("posture:    %s%s (default)\n",
           cfg.armed ? "ARMED" : "disarmed",
           cfg.dry_run ? "/dry-run" : "");

    sg_proc_t procs[16];
    int n = sg_scan_procs(procs, 16);
    printf("\ntop %d by RSS:\n", n > 5 ? 5 : n);
    printf("%-8s %-10s %s\n", "PID", "RSS(MB)", "NAME");
    for (int i = 0; i < n && i < 5; i++)
        printf("%-8d %-10llu %s%s\n", procs[i].pid,
               (unsigned long long)procs[i].rss_mb, procs[i].name,
               sg_name_killable(&cfg, procs[i].name) ? "  <killable>" : "");
    return 0;
}

static int cmd_top(int n) {
    if (n <= 0 || n > SG_MAX_PROCS) n = 10;
    sg_proc_t procs[SG_MAX_PROCS];
    int got = sg_scan_procs(procs, n);
    printf("%-8s %-10s %s\n", "PID", "RSS(MB)", "NAME");
    for (int i = 0; i < got; i++)
        printf("%-8d %-10llu %s\n", procs[i].pid,
               (unsigned long long)procs[i].rss_mb, procs[i].name);
    return 0;
}

static int cmd_check(void) {
    sg_config_t cfg;
    sg_builtin_config(&cfg);
    cfg.dry_run = 1;          /* never kill from a manual check */
    sg_state_t st;
    memset(&st, 0, sizeof(st));
    sg_cycle(&cfg, stdout, &st);
    return 0;
}

static int signal_daemon(int signo, const char *label) {
    pid_t pid = sg_find_pid("safeguardd");
    if (pid <= 0) {
        fprintf(stderr, "safeguardd not running\n");
        return 1;
    }
    if (kill(pid, signo) != 0) {
        fprintf(stderr, "signal failed: %s\n", strerror(errno));
        return 1;
    }
    printf("sent %s to safeguardd (pid=%d)\n", label, pid);
    return 0;
}

static int cmd_kill(const char *target) {
    sg_config_t cfg;
    sg_builtin_config(&cfg);

    pid_t pid = (pid_t)strtol(target, NULL, 10);
    char name[SG_MAX_NAME] = {0};
    if (pid <= 0) {
        pid = sg_find_pid(target);
        strncpy(name, target, SG_MAX_NAME - 1);
    } else {
        /* resolve name from pid via scan */
        sg_proc_t procs[SG_MAX_PROCS];
        int n = sg_scan_procs(procs, SG_MAX_PROCS);
        for (int i = 0; i < n; i++) {
            if (procs[i].pid == pid) {
                strncpy(name, procs[i].name, SG_MAX_NAME - 1);
                break;
            }
        }
    }
    if (pid <= 0) {
        fprintf(stderr, "no such process: %s\n", target);
        return 1;
    }
    if (name[0] == '\0') {
        fprintf(stderr, "pid %d not in process list (cannot enforce allowlist)\n", pid);
        return 1;
    }
    if (!sg_name_killable(&cfg, name)) {
        fprintf(stderr, "REFUSED: '%s' is not in the kill-allowlist "
                "(or is blocklisted). Manual kill denied for safety.\n", name);
        return 1;
    }
    if (kill(pid, SIGKILL) != 0) {
        fprintf(stderr, "kill failed: %s\n", strerror(errno));
        return 1;
    }
    printf("killed %s pid=%d\n", name, pid);
    return 0;
}

static void usage(const char *p) {
    fprintf(stderr,
        "usage: %s <command>\n"
        "  status            zone + pressure + top hogs\n"
        "  top [N]           top-N processes by RSS\n"
        "  check             one-shot detect (no kill)\n"
        "  probe             namespace probe\n"
        "  kill <name|pid>   SIGKILL a hog (allowlist enforced)\n"
        "  arm               resume daemon auto-kill\n"
        "  disarm            suspend daemon auto-kill\n",
        p);
}

int main(int argc, char *argv[]) {
    if (argc < 2) { usage(argv[0]); return 1; }
    const char *cmd = argv[1];

    if (strcmp(cmd, "status") == 0) return cmd_status();
    if (strcmp(cmd, "top") == 0)    return cmd_top(argc > 2 ? atoi(argv[2]) : 10);
    if (strcmp(cmd, "check") == 0)  return cmd_check();
    if (strcmp(cmd, "probe") == 0)  { sg_probe(stdout); return 0; }
    if (strcmp(cmd, "arm") == 0)    return signal_daemon(SIGUSR1, "ARM");
    if (strcmp(cmd, "disarm") == 0) return signal_daemon(SIGUSR2, "DISARM");
    if (strcmp(cmd, "kill") == 0) {
        if (argc < 3) { usage(argv[0]); return 1; }
        return cmd_kill(argv[2]);
    }

    usage(argv[0]);
    return 1;
}
