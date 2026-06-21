#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <arpa/inet.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

#ifndef PROC_ALL_PIDS
#define PROC_ALL_PIDS 1
#endif

#ifndef PROC_PIDPATHINFO_MAXSIZE
#define PROC_PIDPATHINFO_MAXSIZE 4096
#endif

extern int proc_listpids(unsigned int type, unsigned int typeinfo, void *buffer, int buffersize);
extern int proc_pidpath(int pid, void *buffer, unsigned int buffersize);
extern int proc_pidinfo(int pid, int flavor, uint64_t arg, void *buffer, int buffersize);

#ifndef PROC_PIDTBSDINFO
#define PROC_PIDTBSDINFO 3
#endif
#ifndef MAXCOMLEN
#define MAXCOMLEN 16
#endif
#ifndef SZOMB
#define SZOMB 5
#endif

typedef struct {
    uint32_t flags;
    uint32_t status;
    uint32_t xstatus;
    uint32_t pid;
    uint32_t ppid;
    uid_t uid;
    gid_t gid;
    uid_t ruid;
    gid_t rgid;
    uid_t svuid;
    gid_t svgid;
    uint32_t reserved;
    char comm[MAXCOMLEN];
    char name[2 * MAXCOMLEN];
    uint32_t nfiles;
    uint32_t pgid;
    uint32_t pjobc;
    uint32_t tdev;
    uint32_t tpgid;
    int32_t nice;
    uint64_t startSec;
    uint64_t startUsec;
} ProcBSDInfo;

static int pid_is_live_non_zombie(int pid) {
    if (pid <= 0 || kill(pid, 0) != 0) return 0;
    ProcBSDInfo info;
    memset(&info, 0, sizeof(info));
    int got = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, (int)sizeof(info));
    if (got != (int)sizeof(info)) return 0;
    return info.status != SZOMB;
}

static const char *kLogPath = "/var/mobile/Library/Preferences/catmcp-autoinjectd.log";
static const char *kInjectLogPath = "/var/mobile/Library/Preferences/catmcp-inject.log";
static const char *kServerLogPath = "/var/mobile/Library/Preferences/catmcp-server.log";
static volatile sig_atomic_t gStop = 0;
static const int kHealthFailureThreshold = 6;
static const int kHealthCheckIntervalSeconds = 15;

static void rotate_file_if_needed(const char *path, off_t maxSize) {
    struct stat st;
    if (!path || stat(path, &st) != 0 || st.st_size < maxSize) return;
    char rotated[512];
    snprintf(rotated, sizeof(rotated), "%s.1", path);
    unlink(rotated);
    rename(path, rotated);
}

static void log_line(const char *fmt, ...) {
    rotate_file_if_needed(kLogPath, 131072);
    FILE *f = fopen(kLogPath, "a");
    time_t now = time(NULL);
    struct tm tmv;
    localtime_r(&now, &tmv);
    char stamp[32];
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &tmv);
    if (f) fprintf(f, "%s ", stamp);
    fprintf(stderr, "%s ", stamp);
    va_list ap;
    va_start(ap, fmt);
    va_list ap2;
    va_copy(ap2, ap);
    if (f) vfprintf(f, fmt, ap);
    vfprintf(stderr, fmt, ap2);
    va_end(ap2);
    va_end(ap);
    if (f) {
        fputc('\n', f);
        fclose(f);
    }
    fputc('\n', stderr);
}

static void on_signal(int sig) {
    (void)sig;
    gStop = 1;
}

static int catmcp_is_enabled(const char *root) {
    if (!root || !*root) return 1;
    char path[1024];
    snprintf(path, sizeof(path),
             "%s/.jbroot/var/mobile/Library/Preferences/com.catmcp.server.plist",
             root);
    int fd = open(path, O_RDONLY);
    if (fd < 0) return 1;

    struct stat st;
    if (fstat(fd, &st) != 0 || st.st_size <= 0 || st.st_size > 1048576) {
        close(fd);
        return 1;
    }
    UInt8 *bytes = (UInt8 *)malloc((size_t)st.st_size);
    if (!bytes) {
        close(fd);
        return 1;
    }
    size_t total = 0;
    while (total < (size_t)st.st_size) {
        ssize_t n = read(fd, bytes + total, (size_t)st.st_size - total);
        if (n > 0) total += (size_t)n;
        else if (n < 0 && errno == EINTR) continue;
        else break;
    }
    close(fd);

    int enabled = 1;
    if (total == (size_t)st.st_size) {
        CFDataRef data = CFDataCreate(kCFAllocatorDefault, bytes, (CFIndex)total);
        if (data) {
            CFErrorRef error = NULL;
            CFPropertyListRef plist = CFPropertyListCreateWithData(
                kCFAllocatorDefault, data, kCFPropertyListImmutable, NULL, &error);
            if (plist && CFGetTypeID(plist) == CFDictionaryGetTypeID()) {
                CFTypeRef value = CFDictionaryGetValue((CFDictionaryRef)plist, CFSTR("enabled"));
                if (value && CFGetTypeID(value) == CFBooleanGetTypeID()) {
                    enabled = CFBooleanGetValue((CFBooleanRef)value) ? 1 : 0;
                }
            }
            if (plist) CFRelease(plist);
            if (error) CFRelease(error);
            CFRelease(data);
        }
    }
    free(bytes);
    return enabled;
}

static int find_jbroot(char *out, size_t outSize) {
    if (!out || outSize == 0) return -1;
    out[0] = 0;
    char selfPath[PROC_PIDPATHINFO_MAXSIZE];
    memset(selfPath, 0, sizeof(selfPath));
    int len = proc_pidpath(getpid(), selfPath, (unsigned int)sizeof(selfPath));
    if (len <= 0) return -1;
    const char *needle = "/usr/libexec/catmcp-autoinjectd";
    char *hit = strstr(selfPath, needle);
    if (!hit || (!strstr(selfPath, ".jbroot-") && !strstr(selfPath, "/var/jb/"))) return -1;
    size_t n = (size_t)(hit - selfPath);
    if (n == 0 || n >= outSize) return -1;
    memcpy(out, selfPath, n);
    out[n] = 0;
    return 0;
}

static int find_catmcp_pid(void) {
    int result = 0;

    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes > 0) {
        int count = bytes / (int)sizeof(pid_t);
        pid_t *pids = (pid_t *)calloc((size_t)count, sizeof(pid_t));
        if (pids) {
            int got = proc_listpids(PROC_ALL_PIDS, 0, pids, bytes);
            if (got > 0) {
                int gotCount = got / (int)sizeof(pid_t);
                char path[PROC_PIDPATHINFO_MAXSIZE];
                for (int i = 0; i < gotCount; i++) {
                    pid_t pid = pids[i];
                    if (pid <= 0 || pid == getpid()) continue;
                    memset(path, 0, sizeof(path));
                    int len = proc_pidpath((int)pid, path, (unsigned int)sizeof(path));
                    if (len <= 0) continue;
                    const char *base = strrchr(path, '/');
                    base = base ? base + 1 : path;
                    if ((strcmp(base, "catmcp") == 0 || strcmp(path, "/usr/bin/catmcp") == 0) &&
                        pid_is_live_non_zombie((int)pid)) {
                        // The vendor launcher may leave a short-lived parent next to the
                        // actual listener. The listener is the newer child on this build.
                        if (result == 0 || (int)pid > result) result = (int)pid;
                    }
                }
            }
            free(pids);
        }
    }
    return result;
}

static int file_exists_executable(const char *path) {
    struct stat st;
    return path && stat(path, &st) == 0 && (st.st_mode & S_IXUSR);
}

static int file_exists_readable(const char *path) {
    struct stat st;
    return path && stat(path, &st) == 0 && (st.st_mode & S_IRUSR);
}

static int wait_fd(int fd, int writeMode, int timeoutMs) {
    fd_set set;
    FD_ZERO(&set);
    FD_SET(fd, &set);
    struct timeval tv;
    tv.tv_sec = timeoutMs / 1000;
    tv.tv_usec = (timeoutMs % 1000) * 1000;
    int rc = select(fd + 1, writeMode ? NULL : &set, writeMode ? &set : NULL, NULL, &tv);
    return rc > 0 ? 0 : -1;
}

static int catmcp_http_healthcheck(void) {
    static const char *body = "{\"jsonrpc\":\"2.0\",\"id\":-1724,\"method\":\"tools/call\",\"params\":{\"name\":\"self_state\",\"arguments\":{}}}";
    char req[512];
    snprintf(req, sizeof(req),
             "POST /mcp HTTP/1.1\r\n"
             "Host: 127.0.0.1:9000\r\n"
             "Content-Type: application/json\r\n"
             "Accept: application/json, text/event-stream\r\n"
             "Connection: close\r\n"
             "Content-Length: %lu\r\n"
             "\r\n"
             "%s",
             (unsigned long)strlen(body), body);

    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;

    int flags = fcntl(fd, F_GETFL, 0);
    if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);

    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_port = htons(9000);
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

    int rc = connect(fd, (struct sockaddr *)&addr, sizeof(addr));
    if (rc != 0 && errno != EINPROGRESS) {
        close(fd);
        return -2;
    }
    if (rc != 0 && wait_fd(fd, 1, 1200) != 0) {
        close(fd);
        return -3;
    }

    int soerr = 0;
    socklen_t soerrLen = sizeof(soerr);
    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &soerr, &soerrLen) != 0 || soerr != 0) {
        close(fd);
        return -4;
    }

    size_t sent = 0;
    size_t reqLen = strlen(req);
    while (sent < reqLen) {
        ssize_t n = send(fd, req + sent, reqLen - sent, 0);
        if (n > 0) {
            sent += (size_t)n;
            continue;
        }
        if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
            if (wait_fd(fd, 1, 1200) != 0) {
                close(fd);
                return -5;
            }
            continue;
        }
        close(fd);
        return -6;
    }

    char resp[1024];
    memset(resp, 0, sizeof(resp));
    if (wait_fd(fd, 0, 4000) != 0) {
        close(fd);
        return -7;
    }
    ssize_t got = recv(fd, resp, sizeof(resp) - 1, 0);
    close(fd);
    if (got <= 0) return -8;
    resp[got] = 0;
    return strstr(resp, " 200 ") || strstr(resp, " 200\r\n") ? 0 : -9;
}

static int terminate_pid_bounded(int pid) {
    if (pid <= 0 || kill(pid, 0) != 0) return 0;
    kill(pid, SIGTERM);
    for (int i = 0; i < 20; i++) {
        if (kill(pid, 0) != 0) return 0;
        usleep(100000);
    }
    kill(pid, SIGKILL);
    for (int i = 0; i < 10; i++) {
        if (kill(pid, 0) != 0) return 0;
        usleep(100000);
    }
    return kill(pid, 0) == 0 ? -1 : 0;
}

static void terminate_all_catmcp(void) {
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, NULL, 0);
    if (bytes <= 0) return;
    int count = bytes / (int)sizeof(pid_t);
    pid_t *pids = (pid_t *)calloc((size_t)count, sizeof(pid_t));
    if (!pids) return;
    int got = proc_listpids(PROC_ALL_PIDS, 0, pids, bytes);
    int gotCount = got > 0 ? got / (int)sizeof(pid_t) : 0;
    char path[PROC_PIDPATHINFO_MAXSIZE];
    for (int i = 0; i < gotCount; i++) {
        pid_t pid = pids[i];
        if (pid <= 0 || pid == getpid()) continue;
        memset(path, 0, sizeof(path));
        if (proc_pidpath((int)pid, path, (unsigned int)sizeof(path)) <= 0) continue;
        const char *base = strrchr(path, '/');
        base = base ? base + 1 : path;
        if ((strcmp(base, "catmcp") == 0 || strcmp(path, "/usr/bin/catmcp") == 0) &&
            pid_is_live_non_zombie((int)pid)) {
            log_line("terminate owned catmcp pid=%d", (int)pid);
            terminate_pid_bounded((int)pid);
        }
    }
    free(pids);
}

static int spawn_catmcp(const char *root, pid_t *spawnedPid) {
    if (!root || !*root) return 1;
    char server[768];
    snprintf(server, sizeof(server), "%s/usr/bin/catmcp", root);
    if (!file_exists_executable(server)) {
        log_line("server missing path=%s", server);
        return 2;
    }
    rotate_file_if_needed(kServerLogPath, 262144);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, kServerLogPath,
                                     O_CREAT | O_WRONLY | O_APPEND, 0644);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    char *argv[] = { server, NULL };
    pid_t child = 0;
    int rc = posix_spawn(&child, server, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (rc != 0) {
        log_line("server spawn failed rc=%d errno=%d", rc, errno);
        return 3;
    }
    if (spawnedPid) *spawnedPid = child;
    log_line("server spawned pid=%d", child);
    return 0;
}

static int inject_pid(int pid) {
    char root[512];
    if (find_jbroot(root, sizeof(root)) != 0 || root[0] == 0) {
        log_line("no jbroot found");
        return 1;
    }

    char inject[768];
    char bridge[768];
    snprintf(inject, sizeof(inject), "%s/usr/libexec/catmcp-inject", root);
    snprintf(bridge, sizeof(bridge), "%s/usr/lib/catmcp-touch-bridge.dylib", root);
    if (!file_exists_executable(inject) || !file_exists_readable(bridge)) {
        log_line("missing inject=%s bridge=%s", inject, bridge);
        return 2;
    }

    log_line("inject pid=%d", pid);
    char pidBuf[32];
    snprintf(pidBuf, sizeof(pidBuf), "%d", pid);
    char *argv[] = { inject, pidBuf, bridge, NULL };
    rotate_file_if_needed(kInjectLogPath, 262144);
    posix_spawn_file_actions_t actions;
    posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, kInjectLogPath, O_CREAT | O_WRONLY | O_APPEND, 0644);
    posix_spawn_file_actions_adddup2(&actions, STDOUT_FILENO, STDERR_FILENO);
    pid_t child = 0;
    int spawnRc = posix_spawn(&child, inject, &actions, NULL, argv, environ);
    posix_spawn_file_actions_destroy(&actions);
    if (spawnRc != 0) {
        log_line("inject spawn failed rc=%d errno=%d", spawnRc, errno);
        return 3;
    }
    int status = 0;
    for (int i = 0; i < 100 && !gStop; i++) {
        pid_t waited = waitpid(child, &status, WNOHANG);
        if (waited == child) {
            if (WIFEXITED(status)) {
                int code = WEXITSTATUS(status);
                log_line("inject exited code=%d pid=%d", code, pid);
                return code;
            }
            log_line("inject abnormal status=%d pid=%d", status, pid);
            return 4;
        }
        if (waited < 0 && errno != EINTR) return 4;
        usleep(100000);
    }
    kill(child, SIGKILL);
    for (int i = 0; i < 20; i++) {
        pid_t waited = waitpid(child, &status, WNOHANG);
        if (waited == child || (waited < 0 && errno == ECHILD)) break;
        usleep(50000);
    }
    log_line("inject timeout pid=%d child=%d", pid, child);
    return 5;
}

int main(void) {
    signal(SIGTERM, on_signal);
    signal(SIGINT, on_signal);
    signal(SIGPIPE, SIG_IGN);
    log_line("catmcp-autoinjectd start pid=%d", getpid());

    char root[512];
    if (find_jbroot(root, sizeof(root)) != 0) {
        log_line("cannot discover active jbroot");
        return 1;
    }
    log_line("active jbroot=%s", root);

    int currentPid = find_catmcp_pid();
    int lastInjectedPid = 0;
    int healthFailures = 0;
    int serverHealthy = 0;
    int enabledLast = -1;
    int restartCooldown = 15;
    time_t lastRestartAt = 0;
    time_t lastStartAttempt = 0;
    time_t lastHealthCheck = 0;
    log_line("server pid=%d", currentPid);

    while (!gStop) {
        time_t now = time(NULL);
        int enabled = catmcp_is_enabled(root);
        if (enabled != enabledLast) {
            log_line("enabled=%d", enabled);
            enabledLast = enabled;
        }

        if (currentPid > 0 && !pid_is_live_non_zombie(currentPid)) {
            int exitedPid = currentPid;
            currentPid = find_catmcp_pid();
            log_line("server exited pid=%d rediscovered=%d", exitedPid, currentPid);
            lastInjectedPid = 0;
            healthFailures = 0;
            serverHealthy = 0;
            lastHealthCheck = 0;
        }

        if (!enabled) {
            healthFailures = 0;
            serverHealthy = 0;
            sleep(3);
            continue;
        }

        if (currentPid <= 0) {
            if (now - lastStartAttempt >= 5) {
                pid_t child = 0;
                lastStartAttempt = now;
                if (spawn_catmcp(root, &child) == 0) {
                    currentPid = (int)child;
                    lastRestartAt = now;
                    healthFailures = 0;
                    serverHealthy = 0;
                    lastHealthCheck = 0;
                    sleep(2);
                }
            }
            sleep(1);
            continue;
        }

        if (lastHealthCheck == 0 || now - lastHealthCheck >= kHealthCheckIntervalSeconds) {
            int health = catmcp_http_healthcheck();
            lastHealthCheck = now;
            if (health == 0) {
                if (healthFailures > 0) log_line("http recovered failures=%d", healthFailures);
                healthFailures = 0;
                serverHealthy = 1;
                if (restartCooldown > 15 && now - lastRestartAt > 180) restartCooldown = 15;
            } else {
                healthFailures++;
                serverHealthy = 0;
                log_line("http failed rc=%d failures=%d pid=%d", health, healthFailures, currentPid);
            }
        }

        if (healthFailures >= kHealthFailureThreshold && now - lastRestartAt >= restartCooldown) {
            log_line("restart pid=%d reason=http_unhealthy cooldown=%d", currentPid, restartCooldown);
            terminate_all_catmcp();
            currentPid = 0;
            lastRestartAt = now;
            if (restartCooldown < 120) restartCooldown *= 2;
            lastInjectedPid = 0;
            healthFailures = 0;
            serverHealthy = 0;
            lastHealthCheck = 0;
            sleep(2);
            continue;
        }

        if (serverHealthy && currentPid != lastInjectedPid) {
            int rc = inject_pid(currentPid);
            if (rc == 0) {
                lastInjectedPid = currentPid;
            } else {
                int discovered = find_catmcp_pid();
                if (discovered > 0 && discovered != currentPid) {
                    log_line("inject failed rc=%d pid=%d switching=%d", rc, currentPid, discovered);
                    currentPid = discovered;
                    healthFailures = 0;
                    serverHealthy = 0;
                    lastHealthCheck = 0;
                } else {
                    sleep(2);
                }
            }
        }
        sleep(2);
    }

    log_line("catmcp-autoinjectd stop pid=%d", getpid());
    return 0;
}
