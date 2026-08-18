/*
 * jetsamfixd — privileged RootHide LaunchDaemon that keeps jetsam limits
 * and the global lenient mode raised for the configured target processes.
 *
 * On launch it applies the policy once, then re-applies every Interval
 * seconds (processes that relaunch inherit the default limits). It logs
 * to /var/mobile/Library/Preferences/com.ratush.jetsamfix.log and exits
 * cleanly on SIGTERM/SIGINT.
 */
#include "jf_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>
#include <time.h>

/* rootfs-side config/log, reachable because the daemon is no-sandbox + root */
#define JF_CONFIG_PATH "/var/mobile/Library/Preferences/com.ratush.jetsamfix.plist"
#define JF_LOG_PATH    "/var/mobile/Library/Preferences/com.ratush.jetsamfix.log"

static volatile sig_atomic_t g_running = 1;

static void on_signal(int sig) {
    (void)sig;
    g_running = 0;
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
    int once = 0;
    int interval_override = 0;
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--once") == 0) once = 1;
        else if (strcmp(argv[i], "--interval") == 0 && i + 1 < argc)
            interval_override = atoi(argv[++i]);
    }

    /* Log to stderr — launchd captures this reliably even inside the iOS
     * data-container (it opens the redirect fd and hands it to us), unlike
     * a file we try to open() ourselves. */
    FILE *log = stderr;

    ts_log(log, "jetsamfixd starting\n");

    struct sigaction sa;
    memset(&sa, 0, sizeof(sa));
    sa.sa_handler = on_signal;
    sigaction(SIGTERM, &sa, NULL);
    sigaction(SIGINT, &sa, NULL);
    /* ignore SIGPIPE; we never want to die on a broken pipe */
    signal(SIGPIPE, SIG_IGN);

    jf_config_t cfg;
    if (jf_load_config(JF_CONFIG_PATH, &cfg) != 0) {
        ts_log(log, "no config file; using built-in defaults\n");
        jf_builtin_config(&cfg);
    }
    if (interval_override > 0) cfg.interval = interval_override;

    char mb[128];
    snprintf(mb, sizeof(mb), "config: lenient=%d interval=%ds targets=%d\n",
             cfg.lenient, cfg.interval, cfg.count);
    ts_log(log, mb);

    int prev_hit = -1;
    do {
        /* Full per-target detail only on the first apply; subsequent cycles
         * apply silently unless the hit count changes (a process appeared or
         * disappeared), which avoids filling the non-rotating launchd log. */
        int hit = jf_apply(&cfg, (prev_hit == -1) ? log : NULL);
        if (hit != prev_hit) {
            snprintf(mb, sizeof(mb), "applied policy; targets hit=%d/%d\n",
                     hit, cfg.count);
            ts_log(log, mb);
        }
        prev_hit = hit;

        if (once) break;

        /* sleep in small chunks so SIGTERM is responsive */
        int remaining = cfg.interval;
        while (remaining > 0 && g_running) {
            int chunk = remaining > 5 ? 5 : remaining;
            sleep(chunk);
            remaining -= chunk;
        }
    } while (g_running);

    ts_log(log, "jetsamfixd exiting\n");
    if (log) fclose(log);
    return 0;
}
