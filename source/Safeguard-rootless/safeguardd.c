/*
 * safeguardd — privileged RootHide LaunchDaemon.
 *
 * Samples memory pressure and resident debug-daemon hogs every Interval
 * seconds and, when armed and the device is under pressure (AMBER or RED), SIGKILLs
 * allowlisted hogs (default: leftover frida-server/frida-helper) — but only once
 * a hog's RSS exceeds kill_min_rss_mb, so a small/idle instance (e.g. a needed
 * frida-server) is tolerated. Detection is
 * syscall-only (container-safe). Logs to stderr -> launchd redirect; steady
 * state is log-silent.
 *
 * Runtime toggles (no files, namespace-safe):
 *   SIGUSR1  -> arm   (resume auto-kill)
 *   SIGUSR2  -> disarm (suspend auto-kill)
 */
#include "sg_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>

static volatile sig_atomic_t g_running = 1;
static volatile sig_atomic_t g_armed_override = -1;  /* -1 = use config */

static void on_signal(int sig) {
    switch (sig) {
        case SIGTERM:
        case SIGINT:  g_running = 0; break;
        case SIGUSR1: g_armed_override = 1; break;     /* arm   */
        case SIGUSR2: g_armed_override = 0; break;     /* disarm */
        default: break;
    }
}

static void ts_log(FILE *log, const char *msg) {
    if (!log || !msg) return;
    time_t now = time(NULL);
    struct tm tm;
    localtime_r(&now, &tm);
    char ts[32];
    strftime(ts, sizeof(ts), "%Y-%m-%d %H:%M:%S", &tm);
    fprintf(log, "[%s] %s", ts, msg);
    fflush(log);
}

int main(int argc, char *argv[]) {
    int once = 0, interval_override = 0, dry_override = -1;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--once") == 0) once = 1;
        else if (strcmp(argv[i], "--interval") == 0 && i + 1 < argc)
            interval_override = atoi(argv[++i]);
        else if (strcmp(argv[i], "--dry-run") == 0) dry_override = 1;
        else if (strcmp(argv[i], "--no-dry-run") == 0) dry_override = 0;
    }

    FILE *log = stderr;   /* launchd hands us this fd; reliable in-container */
    ts_log(log, "safeguardd starting\n");

    /* Self-protect FIRST: launchd caps this daemon at a low jetsam limit
     * (observed 6 MB), which a process-enumerating watchdog exceeds. Remove
     * our own cap before doing any scanning, or we get jetsammed (-9). */
    sg_protect_self(log);

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT,  &sa, NULL);
    sigaction(SIGUSR1, &sa, NULL);
    sigaction(SIGUSR2, &sa, NULL);
    signal(SIGPIPE, SIG_IGN);

    sg_config_t cfg;
    sg_builtin_config(&cfg);
    if (interval_override > 0) cfg.interval = interval_override;
    if (dry_override >= 0)     cfg.dry_run  = dry_override;

    char mb[160];
    snprintf(mb, sizeof(mb),
             "config: armed=%d dry_run=%d interval=%ds red=%dMB amber=%dMB "
             "kill_allow=%d never_kill=%d kill_min_rss=%dMB\n",
             cfg.armed, cfg.dry_run, cfg.interval, cfg.red_mb, cfg.amber_mb,
             cfg.kill_allow_count, cfg.never_kill_count, cfg.kill_min_rss_mb);
    ts_log(log, mb);

    /* Phase-0 namespace probe: once, to stderr so we learn whether tool/fs
     * remediation is even possible from this container. */
    sg_probe(log);

    sg_state_t st;
    memset(&st, 0, sizeof(st));

    int prev_armed = -1;
    do {
        sg_config_t c = cfg;
        if (g_armed_override >= 0) c.armed = g_armed_override;

        if (c.armed != prev_armed) {
            snprintf(mb, sizeof(mb), "armed state: %s\n",
                     c.armed ? "ARMED (auto-kill on AMBER/RED)" : "DISARMED");
            ts_log(log, mb);
            memset(&st, 0, sizeof(st));  /* force a detail log next cycle */
            prev_armed = c.armed;
        }

        sg_cycle(&c, log, &st);

        if (once) break;

        int remaining = c.interval;
        while (remaining > 0 && g_running) {
            int chunk = remaining > 5 ? 5 : remaining;
            sleep(chunk);
            remaining -= chunk;
        }
    } while (g_running);

    ts_log(log, "safeguardd exiting\n");
    return 0;
}
