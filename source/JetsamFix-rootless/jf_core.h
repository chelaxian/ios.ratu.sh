/*
 * jetsamfix shared interface.
 */
#ifndef JF_CORE_H
#define JF_CORE_H

#include <stdio.h>
#include <sys/types.h>

#define JF_MAX_TARGETS 32
#define JF_MAX_NAME    64

typedef struct {
    char  name[JF_MAX_NAME];
    int   limit_mb;        /* desired fatal cap in MB */
    int   priority;        /* desired jetsam priority band */
    int   raise_limit;     /* set LimitMB */
    int   raise_priority;  /* set Priority */
    pid_t pid;             /* resolved at apply time */
} jf_target_t;

typedef struct {
    int         lenient;    /* global lenient mode on/off */
    int         interval;   /* re-apply period in seconds */
    int         count;
    jf_target_t targets[JF_MAX_TARGETS];
} jf_config_t;

pid_t jf_find_pid(const char *name);

int jf_set_task_limit(pid_t pid, int mb);
int jf_set_priority(pid_t pid, int priority);
int jf_set_priority_and_limit(pid_t pid, int priority, int mb);
int jf_lenient_enable(int on);
int jf_lenient_get(void);

int jf_load_config(const char *path, jf_config_t *cfg);
void jf_builtin_config(jf_config_t *cfg);
int jf_apply(const jf_config_t *cfg, FILE *log);

#endif /* JF_CORE_H */
