/*
 * safeguard shared core implementation.
 */
#include "sg_core.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <sys/wait.h>
#include <sys/sysctl.h>
#include <sys/types.h>

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/host_info.h>
#include <mach/vm_statistics.h>

/*
 * <libproc.h> and <sys/proc_info.h> are NOT shipped in the iPhoneOS SDK
 * headers, but the symbols (proc_pidinfo) and the proc_taskinfo layout
 * exist in libsystem at runtime and are stable across iOS versions. Declare
 * the minimal shim here instead of including the missing headers.
 */
#define SG_PROC_PIDTASKINFO 4   /* flavor for struct proc_taskinfo */

struct sg_proc_taskinfo {
    uint64_t pti_virtual_size;
    uint64_t pti_resident_size;   /* resident memory size (bytes) */
    uint64_t pti_total_user;
    uint64_t pti_total_system;
    uint64_t pti_threads_user;
    uint64_t pti_threads_system;
    int32_t  pti_policy;
    int32_t  pti_faults;
    int32_t  pti_pageins;
    int32_t  pti_cow_faults;
    int32_t  pti_messages_sent;
    int32_t  pti_messages_received;
    int32_t  pti_syscalls_mach;
    int32_t  pti_syscalls_unix;
    int32_t  pti_csw;
    int32_t  pti_threadnum;
    int32_t  pti_numrunning;
    int32_t  pti_priority;
};

extern int proc_pidinfo(int pid, int flavor, uint64_t arg,
                        void *buffer, int buffersize);

/* memorystatus_control: private libsystem_kernel symbol. Used here ONLY for
 * daemon self-protection (lifting this process's own launchd jetsam cap) so
 * the watchdog is not itself jetsammed under pressure. Gated by the
 * com.apple.private.memorystatus entitlement on the calling binary. */
#define SG_MEM_SET_JETSAM_TASK_LIMIT 6   /* per-process fatal cap (MB); 0 = none */
extern int memorystatus_control(uint32_t command, int32_t pid,
                                uint32_t flags, void *buffer, size_t buffersize);

extern char **environ;

int sg_read_pressure(sg_pressure_t *out) {
    if (!out) return -1;
    memset(out, 0, sizeof(*out));

    vm_size_t page_size = 4096;
    if (host_page_size(mach_host_self(), &page_size) != KERN_SUCCESS)
        page_size = 4096;

    vm_statistics64_data_t vmstat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    kern_return_t kr = host_statistics64(mach_host_self(), HOST_VM_INFO64,
                                         (host_info64_t)&vmstat, &count);
    if (kr != KERN_SUCCESS) {
        return -1;
    }

    uint64_t reclaimable = ((uint64_t)vmstat.free_count
                            + (uint64_t)vmstat.purgeable_count) * (uint64_t)page_size;
    out->free_mb   = reclaimable / (1024ULL * 1024ULL);
    out->swapouts  = (uint64_t)vmstat.swapouts;

    int lvl = 0;
    size_t sz = sizeof(lvl);
    if (sysctlbyname("kern.memorystatus_vm_pressure_level",
                     &lvl, &sz, NULL, 0) == 0) {
        out->vm_level = lvl;
    }
    return 0;
}

/* ---- process scan ---------------------------------------------------- */

static int kinfo_list(struct kinfo_proc **out) {
    int mib[4] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0 };
    size_t size = 0;
    if (sysctl(mib, 4, NULL, &size, NULL, 0) == -1) return -1;
    if (size == 0) return -1;
    struct kinfo_proc *kp = (struct kinfo_proc *)malloc(size);
    if (!kp) return -1;
    if (sysctl(mib, 4, kp, &size, NULL, 0) == -1) { free(kp); return -1; }
    *out = kp;
    return (int)(size / sizeof(struct kinfo_proc));
}

int sg_scan_procs(sg_proc_t *procs, int max) {
    if (!procs || max <= 0) return 0;

    struct kinfo_proc *kp = NULL;
    int count = kinfo_list(&kp);
    if (count <= 0 || !kp) return 0;

    int filled = 0;
    for (int i = 0; i < count && filled < max; i++) {
        pid_t pid = kp[i].kp_proc.p_pid;
        if (pid <= 1) continue;            /* skip kernel_task/launchd base */

        struct sg_proc_taskinfo pti;
        int r = proc_pidinfo(pid, SG_PROC_PIDTASKINFO, 0, &pti, (int)sizeof(pti));
        if (r <= 0) continue;
        uint64_t rss = pti.pti_resident_size;
        if (rss == 0) continue;

        sg_proc_t *p = &procs[filled];
        p->pid    = pid;
        p->rss_mb = rss / (1024ULL * 1024ULL);
        strncpy(p->name, kp[i].kp_proc.p_comm, SG_MAX_NAME - 1);
        p->name[SG_MAX_NAME - 1] = '\0';
        filled++;
    }
    free(kp);

    /* insertion sort by RSS desc (n is modest) */
    for (int i = 1; i < filled; i++) {
        sg_proc_t key = procs[i];
        int j = i - 1;
        while (j >= 0 && procs[j].rss_mb < key.rss_mb) {
            procs[j + 1] = procs[j];
            j--;
        }
        procs[j + 1] = key;
    }
    return filled;
}

pid_t sg_find_pid(const char *name) {
    if (!name || !*name) return 0;
    struct kinfo_proc *kp = NULL;
    int count = kinfo_list(&kp);
    if (count <= 0 || !kp) return 0;
    pid_t found = 0;
    for (int i = 0; i < count; i++) {
        if (strcmp(kp[i].kp_proc.p_comm, name) == 0) {
            found = kp[i].kp_proc.p_pid;
            break;
        }
    }
    free(kp);
    return found;
}

/* ---- classification / predicates ------------------------------------- */

sg_zone_t sg_classify(const sg_config_t *cfg, const sg_pressure_t *pr) {
    if (!cfg || !pr) return SG_ZONE_GREEN;
    if ((int)pr->free_mb < cfg->red_mb)   return SG_ZONE_RED;
    if ((int)pr->free_mb < cfg->amber_mb) return SG_ZONE_AMBER;
    return SG_ZONE_GREEN;
}

int sg_name_neverkill(const sg_config_t *cfg, const char *name) {
    if (!cfg || !name) return 0;
    for (int i = 0; i < cfg->never_kill_count; i++)
        if (strcmp(cfg->never_kill[i], name) == 0) return 1;
    return 0;
}

int sg_name_killable(const sg_config_t *cfg, const char *name) {
    if (!cfg || !name) return 0;
    if (sg_name_neverkill(cfg, name)) return 0;       /* blocklist wins */
    for (int i = 0; i < cfg->kill_allow_count; i++)
        if (strcmp(cfg->kill_allow[i], name) == 0) return 1;
    return 0;
}

/* ---- config ---------------------------------------------------------- */

void sg_builtin_config(sg_config_t *cfg) {
    if (!cfg) return;
    memset(cfg, 0, sizeof(*cfg));

    /* Hybrid posture: low-risk auto-kill armed, high-risk stays advisory. */
    cfg->armed          = 1;
    cfg->dry_run        = 0;
    cfg->interval       = 20;
    cfg->red_mb         = 60;     /* case-study danger line: ~58MB was crashing */
    cfg->amber_mb       = 120;
    cfg->hog_ceiling_mb = 200;
    cfg->kill_min_rss_mb = 100;  /* a <100MB hog is tolerated (idle frida ~10MB;
                                  * a 150MB+ frida is the real hog to kill) */

    /* Only these names may ever be auto-killed. Defaults = the classic
     * leftover debug hogs from the jetsam safe-mode case study. */
    strncpy(cfg->kill_allow[0], "frida-server", SG_MAX_NAME - 1);
    strncpy(cfg->kill_allow[1], "frida-helper", SG_MAX_NAME - 1);
    cfg->kill_allow_count = 2;

    /* Explicit blocklist — never touched, even if somehow allowlisted. */
    static const char *nk[] = {
        "SpringBoard", "backboardd", "launchd", "kernel_task",
        "debugserver", "cfprefsd", "runningboardd", "amfid",
        "UserManager", "init"
    };
    int n = (int)(sizeof(nk) / sizeof(nk[0]));
    if (n > SG_MAX_NEVER) n = SG_MAX_NEVER;
    for (int i = 0; i < n; i++)
        strncpy(cfg->never_kill[i], nk[i], SG_MAX_NAME - 1);
    cfg->never_kill_count = n;
}

/* ---- one detect+remediate cycle -------------------------------------- */

static const char *zone_name(sg_zone_t z) {
    switch (z) {
        case SG_ZONE_RED:   return "RED";
        case SG_ZONE_AMBER: return "AMBER";
        default:            return "GREEN";
    }
}

void sg_cycle(const sg_config_t *cfg, FILE *log, sg_state_t *st) {
    sg_pressure_t pr;
    if (sg_read_pressure(&pr) != 0) {
        if (log) fprintf(log, "pressure read FAILED (%s)\n", strerror(errno));
        return;
    }
    pr.zone = sg_classify(cfg, &pr);

    sg_proc_t procs[SG_MAX_PROCS];
    int n = sg_scan_procs(procs, SG_MAX_PROCS);

    int killable = 0;
    for (int i = 0; i < n; i++)
        if (sg_name_killable(cfg, procs[i].name)) killable++;

    /* Emit full detail only on first cycle, zone change, or killable-count
     * change — steady state stays log-silent. Real kills always emit. */
    int first  = !(st && st->inited);
    int changed = first;
    if (st && st->inited &&
        (pr.zone != st->zone || killable != st->killable))
        changed = 1;
    FILE *detail = (changed && log) ? log : NULL;

    if (detail) {
        fprintf(detail, "[%s] free=%lluMB swapouts=%llu vmlevel=%d procs=%d killable=%d%s\n",
                zone_name(pr.zone),
                (unsigned long long)pr.free_mb,
                (unsigned long long)pr.swapouts,
                pr.vm_level, n, killable,
                cfg->armed ? (cfg->dry_run ? " (armed/dry-run)" : " (armed)")
                           : " (disarmed)");
        /* Audit: name the kill-allowlisted processes we see this cycle, so
         * an operator can verify the target before any RED-zone action. */
        if (killable > 0) {
            for (int i = 0; i < n; i++) {
                if (sg_name_killable(cfg, procs[i].name))
                    fprintf(detail, "  killable %s pid=%d rss=%lluMB\n",
                            procs[i].name, procs[i].pid,
                            (unsigned long long)procs[i].rss_mb);
            }
        }
    }

    /* E1/E3 remediation: armed + (AMBER or RED) => SIGKILL allowlisted hogs
     * that have bloated past kill_min_rss_mb. We act at AMBER (not RED-only)
     * because a starved process can SIGSEGV before free memory crosses the RED
     * line (observed June 2026: SB SIGSEGV in ImageIO/lzfse at ~100MB free,
     * 100% swap). BUT a hog is only killed once its RSS is large enough to
     * matter: a small/idle instance is tolerated even under pressure. This
     * matters when the tool is legitimately needed — a debug frida-server
     * sitting at ~10MB is fine and is left alone; one ballooned to 150MB under
     * active use is the hog. GREEN is always hands-off, so an intentional live
     * debug session on a healthy device is never disturbed. */
    if (cfg->armed && pr.zone != SG_ZONE_GREEN) {
        for (int i = 0; i < n; i++) {
            if (!sg_name_killable(cfg, procs[i].name)) continue;
            if (procs[i].pid <= 1) continue;
            if (procs[i].rss_mb < (uint64_t)cfg->kill_min_rss_mb) {
                /* tolerated: small enough that killing it won't relieve real
                 * pressure, and the tool may be intentionally in use. */
                if (detail)
                    fprintf(detail, "tolerated %s pid=%d rss=%lluMB (<%dMB floor)\n",
                            procs[i].name, procs[i].pid,
                            (unsigned long long)procs[i].rss_mb,
                            cfg->kill_min_rss_mb);
                continue;
            }
            if (cfg->dry_run) {
                if (detail)
                    fprintf(detail, "[dry-run] would kill %s pid=%d rss=%lluMB\n",
                            procs[i].name, procs[i].pid,
                            (unsigned long long)procs[i].rss_mb);
            } else {
                if (kill(procs[i].pid, SIGKILL) == 0) {
                    if (log)
                        fprintf(log, "KILLED %s pid=%d rss=%lluMB\n",
                                procs[i].name, procs[i].pid,
                                (unsigned long long)procs[i].rss_mb);
                } else if (log) {
                    fprintf(log, "kill %s pid=%d FAILED (%s)\n",
                            procs[i].name, procs[i].pid, strerror(errno));
                }
            }
        }
    }

    /* Advisory hogs (logged only on a detail cycle). */
    if (detail && pr.zone != SG_ZONE_GREEN) {
        int shown = 0;
        for (int i = 0; i < n && shown < 5; i++) {
            if ((int)procs[i].rss_mb >= cfg->hog_ceiling_mb) {
                fprintf(detail, "advisory %s pid=%d rss=%lluMB\n",
                        procs[i].name, procs[i].pid,
                        (unsigned long long)procs[i].rss_mb);
                shown++;
            }
        }
    }

    if (st) {
        st->zone     = pr.zone;
        st->killable = killable;
        st->inited   = 1;
    }
}

/* ---- daemon self-protection ----------------------------------------- */

int sg_protect_self(FILE *log) {
    /* A launchd daemon is capped at a low per-process jetsam limit (observed
     * 6 MB on this device). A memory watchdog that enumerates every process
     * exceeds that and gets jetsammed. Remove our own fatal cap so we survive
     * pressure. Requires com.apple.private.memorystatus on this binary. */
    pid_t me = getpid();
    int r = memorystatus_control(SG_MEM_SET_JETSAM_TASK_LIMIT, me, 0, NULL, 0);
    if (log) {
        if (r == 0)
            fprintf(log, "self-protect: removed own jetsam cap (pid=%d)\n", me);
        else
            fprintf(log, "self-protect: FAILED (%s) — daemon may be jetsammed\n",
                    strerror(errno));
    }
    return r;
}

/* ---- namespace probe (Phase-0) --------------------------------------- */

void sg_probe(FILE *log) {
    if (!log) return;

    /* (A) can the data-container daemon spawn a tool and read its output? */
    pid_t pid = -1;
    int pipefd[2];
    if (pipe(pipefd) == 0) {
        posix_spawn_file_actions_t fa;
        posix_spawn_file_actions_init(&fa);
        posix_spawn_file_actions_adddup2(&fa, pipefd[1], STDOUT_FILENO);
        posix_spawn_file_actions_addclose(&fa, pipefd[0]);
        char *argv[] = { "/var/jb/usr/bin/launchctl", "list", NULL };
        int pserr = posix_spawnp(&pid, "launchctl", &fa, NULL, argv, environ);
        posix_spawn_file_actions_destroy(&fa);
        close(pipefd[1]);
        if (pserr == 0) {
            char line[256];
            memset(line, 0, sizeof(line));
            ssize_t r = read(pipefd[0], line, sizeof(line) - 1);
            close(pipefd[0]);
            int status = 0;
            waitpid(pid, &status, 0);
            fprintf(log, "probe[A] spawn launchctl: OK read=%ld first=\"%.60s\"\n",
                    (long)(r > 0 ? r : 0), r > 0 ? line : "(none)");
        } else {
            close(pipefd[0]);
            fprintf(log, "probe[A] spawn launchctl: FAILED (%s)\n", strerror(pserr));
        }
    } else {
        fprintf(log, "probe[A] pipe: FAILED (%s)\n", strerror(errno));
    }

    /* (B) can the daemon write a file under /var/mobile prefs?
     * (We already know open() for READ fails in this namespace; this tests
     *  WRITE/CREATE, which any fs-based undo-log or remediation needs.) */
    const char *p = "/var/mobile/Library/Preferences/com.ratush.safeguard.probe";
    int fd = open(p, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        ssize_t w = write(fd, "ok\n", 3);
        close(fd);
        fprintf(log, "probe[B] write %s: OK wrote=%ld\n", p, (long)w);
    } else {
        fprintf(log, "probe[B] write %s: FAILED (%s)\n", p, strerror(errno));
    }
}
