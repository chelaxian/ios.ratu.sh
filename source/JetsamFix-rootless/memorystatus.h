/*
 * Private memorystatus interface — constants extracted from XNU's
 * sys/kern_memorystatus.h (matches the values overb0ard/jetsamctl use and
 * that are current through iOS 17). memorystatus_control() is a private
 * libc/libsystem_kernel symbol; we declare it ourselves.
 *
 * Gated by the com.apple.private.memorystatus entitlement.
 */
#ifndef JF_MEMSTATUS_H
#define JF_MEMSTATUS_H

#include <stdint.h>
#include <sys/types.h>

/* memorystatus_control command numbers */
#define MEMORYSTATUS_CMD_GET_PRIORITY_LIST                 1
#define MEMORYSTATUS_CMD_SET_PRIORITY_PROPERTIES           2
#define MEMORYSTATUS_CMD_GET_JETSAM_SNAPSHOT               3
#define MEMORYSTATUS_CMD_GET_PRESSURE_STATUS               4
#define MEMORYSTATUS_CMD_SET_JETSAM_HIGH_WATER_MARK        5
#define MEMORYSTATUS_CMD_SET_JETSAM_TASK_LIMIT             6
#define MEMORYSTATUS_CMD_AGGRESSIVE_JETSAM_LENIENT_MODE_ENABLE   11
#define MEMORYSTATUS_CMD_AGGRESSIVE_JETSAM_LENIENT_MODE_DISABLE  12
#define MEMORYSTATUS_CMD_SET_PROCESS_IS_MANAGED            16
#define MEMORYSTATUS_CMD_GET_AGGRESSIVE_JETSAM_LENIENT_MODE      21
#define MEMORYSTATUS_CMD_GRP_SET_PROPERTIES                100

/* flags for MEMORYSTATUS_CMD_GRP_SET_PROPERTIES */
#define MEMORYSTATUS_FLAGS_GRP_SET_PRIORITY                0x8

#define MEMORYSTATUS_MPE_VERSION_1                         1
#define MAXCOMLEN                                          16

/* iOS 16+ jetsam priority bands are multiplied by 10. */
#define JETSAM_PRIORITY_FOREGROUND_SUPPORT                 90
#define JETSAM_PRIORITY_FOREGROUND                         100
#define JETSAM_PRIORITY_HOME                               160   /* SpringBoard */
#define JETSAM_PRIORITY_IMPORTANT                          180
#define JETSAM_PRIORITY_CRITICAL                           190
#define JETSAM_PRIORITY_MAX                                210

/* Property entry for GRP_SET_PROPERTIES (version 1). */
typedef struct memorystatus_properties_entry_v1 {
    int      version;
    pid_t    pid;
    int32_t  priority;
    int      use_probability;
    uint64_t user_data;
    int32_t  limit;        /* MB; 0 = no per-process fatal cap */
    uint32_t state;
    char     proc_name[MAXCOMLEN + 1];
    char     __pad1[3];
} memorystatus_properties_entry_v1_t;

/* Priority-list entry returned by GET_PRIORITY_LIST. */
typedef struct memorystatus_priority_entry {
    pid_t    pid;
    int32_t  priority;
    uint64_t user_data;
    int32_t  limit;        /* MB */
    uint32_t state;
} memorystatus_priority_entry_t;

/* Private syscall (libsystem_kernel). Returns 0 on success, -1 + errno. */
int memorystatus_control(uint32_t command, int32_t pid, uint32_t flags,
                         void *buffer, size_t buffersize);

#endif /* JF_MEMSTATUS_H */
