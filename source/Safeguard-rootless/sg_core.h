/*
 * safeguard shared interface: memory-pressure sampling, process/RSS
 * scanning, hog detection, the kill primitive, and a one-shot namespace
 * probe. Shared by the daemon and the CLI.
 *
 * Design note: detection is syscall-only (host_statistics64, sysctl,
 * proc_pidinfo, kill). A launchd daemon on RootHide runs inside a
 * data-container namespace where open() of /var/mobile files fails but
 * these syscalls succeed, so everything that must work at runtime avoids
 * filesystem reads. Config is therefore built into the binary.
 */
#ifndef SG_CORE_H
#define SG_CORE_H

#include <stdio.h>
#include <stdint.h>
#include <sys/types.h>

#define SG_MAX_PROCS  2048
#define SG_MAX_KILL   16
#define SG_MAX_NEVER  32
#define SG_MAX_NAME   64

typedef enum {
    SG_ZONE_GREEN = 0,
    SG_ZONE_AMBER = 1,
    SG_ZONE_RED   = 2
} sg_zone_t;

typedef struct {
    uint64_t  free_mb;    /* free + purgeable pages, in MB */
    uint64_t  swapouts;   /* cumulative swapouts */
    int       vm_level;   /* kern.memorystatus_vm_pressure_level 0..3 */
    sg_zone_t zone;       /* classified from free_mb vs thresholds */
} sg_pressure_t;

typedef struct {
    pid_t    pid;
    char     name[SG_MAX_NAME];
    uint64_t rss_mb;      /* resident size in MB */
} sg_proc_t;

typedef struct {
    int  armed;           /* 1 = auto-kill when zone is RED */
    int  dry_run;         /* 1 = log only, never kill */
    int  interval;        /* sample period, seconds */
    int  red_mb;          /* RED: free+purgeable below this */
    int  amber_mb;        /* AMBER threshold */
    int  hog_ceiling_mb;  /* advisory: flag procs above this RSS */
    int  kill_min_rss_mb; /* only auto-kill a hog if its RSS >= this; a small
                           * idle instance (e.g. a needed frida-server) is
                           * tolerated even under AMBER/RED pressure */
    char kill_allow[SG_MAX_KILL][SG_MAX_NAME]; /* names eligible for auto-kill */
    int  kill_allow_count;
    char never_kill[SG_MAX_NEVER][SG_MAX_NAME]; /* explicit blocklist */
    int  never_kill_count;
} sg_config_t;

/* Persisted across cycles by the daemon to drive state-change logging. */
typedef struct {
    int       inited;
    sg_zone_t zone;
    int       killable;   /* count of kill-allow hogs present last cycle */
} sg_state_t;

/* ---- pressure ---- */
int sg_read_pressure(sg_pressure_t *out);

/* ---- process scan ---- */
/* Fills procs[] sorted by RSS desc. Returns count (<= max). */
int sg_scan_procs(sg_proc_t *procs, int max);
pid_t sg_find_pid(const char *name);

/* ---- classification / predicates ---- */
int sg_name_killable(const sg_config_t *cfg, const char *name);
int sg_name_neverkill(const sg_config_t *cfg, const char *name);
sg_zone_t sg_classify(const sg_config_t *cfg, const sg_pressure_t *pr);

/* ---- config ---- */
void sg_builtin_config(sg_config_t *cfg);

/* ---- one detect+remediate cycle ----
 * Logs full detail on the first cycle, on zone/killable change, and on
 * every real kill; otherwise steady-state-silent (NULL detail sink).
 * Updates *st. */
void sg_cycle(const sg_config_t *cfg, FILE *log, sg_state_t *st);

/* ---- daemon self-protection ----
 * Lifts this process's own launchd jetsam cap so the watchdog is not itself
 * jetsammed. Returns 0 on success. */
int sg_protect_self(FILE *log);

/* ---- namespace probe (Phase-0) ----
 * Runs once at daemon start. Tests whether the data-container daemon can
 * (A) posix_spawn a tool and capture output, (B) write a file under
 * /var/mobile. Result goes to log (stderr -> launchd redirect). */
void sg_probe(FILE *log);

#endif /* SG_CORE_H */
