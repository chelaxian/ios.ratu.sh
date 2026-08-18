// catmcpcchelper - toggles the CatMCP server via the canonical preference.
//
// Source of truth for "is CatMCP enabled" is the boolean `enabled` key in
// /var/mobile/Library/Preferences/com.catmcp.server.plist. That plist is what
// the CatMCP Settings pane switch reads/writes AND what autoinjectd reads to
// decide whether to keep the server alive. Writing it therefore keeps the
// Settings switch and the live server in sync.
//
// To make the change take effect immediately (rather than waiting for
// autoinjectd's slow poll loop), we kickstart -k the user/501 job, which
// relaunches autoinjectd so it re-reads the plist right now.
//
// Ground truth for "is the server actually up right now" is a TCP connect to
// 127.0.0.1:9000.

#include <arpa/inet.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dirent.h>
#include <errno.h>
#include <netinet/in.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

extern char **environ;

static char gJBRoot[512];

static int exists(const char *p) {
    struct stat st;
    return p && stat(p, &st) == 0;
}

static void init_jbroot(void) {
    const char *bases[] = {
        "/var/containers/Bundle/Application",
        "/private/var/containers/Bundle/Application",
        NULL
    };
    for (int i = 0; bases[i] && !gJBRoot[0]; i++) {
        DIR *d = opendir(bases[i]);
        if (!d) continue;
        struct dirent *de;
        while ((de = readdir(d))) {
            if (strncmp(de->d_name, ".jbroot-", 8) != 0) continue;
            snprintf(gJBRoot, sizeof(gJBRoot), "%s/%s", bases[i], de->d_name);
            break;
        }
        closedir(d);
    }
    if (!gJBRoot[0] && exists("/var/jb/usr/bin/sh")) {
        snprintf(gJBRoot, sizeof(gJBRoot), "/var/jb");
    }
    if (!gJBRoot[0]) {
        snprintf(gJBRoot, sizeof(gJBRoot), "/");
    }
}

#include <fcntl.h>

// Forward decl — defined later; we use it from pref_set_enabled.
static int run_root_shell(const char *fmt, ...);

// The helper runs in a chrooted namespace where its own /var/mobile maps to
// /rootfs/private/var/mobile in the real FS — a different file than the one
// autoinjectd and Settings read. autoinjectd resolves the pref via
// "%s/.jbroot/var/mobile/Library/Preferences/com.catmcp.server.plist", which
// (because .jbroot-* symlinks back to the jailbreak root) lands at
// <jbroot>/var/mobile/Library/Preferences/com.catmcp.server.plist — the file
// that is actually authoritative. We must write THAT path, not our chroot's
// /var/mobile.
static char gPrefPath[768];
static const char *pref_path(void) {
    if (!gPrefPath[0]) {
        snprintf(gPrefPath, sizeof(gPrefPath),
                 "%s/var/mobile/Library/Preferences/com.catmcp.server.plist", gJBRoot);
    }
    return gPrefPath;
}

// Read the whole file into a CFData via plain open()/read() (the same path
// autoinjectd uses internally — CFReadStream is unreliable inside a setuid
// root helper on this RootHide setup).
static CFDataRef read_file_data(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;

    // Read up to 1 MB.
    CFMutableDataRef data = CFDataCreateMutable(kCFAllocatorDefault, 0);
    if (!data) { close(fd); return NULL; }

    char buf[4096];
    ssize_t n;
    while ((n = read(fd, buf, sizeof(buf))) > 0) {
        CFDataAppendBytes(data, (const UInt8 *)buf, (CFIndex)n);
    }
    close(fd);
    if (n < 0) { CFRelease(data); return NULL; }
    if (CFDataGetLength(data) == 0) { CFRelease(data); return NULL; }
    return data;
}

// Parse the plist from a byte buffer.
static CFPropertyListRef parse_plist_from_file(const char *path) {
    CFDataRef data = read_file_data(path);
    if (!data) return NULL;
    CFPropertyListRef pl = CFPropertyListCreateWithData(
        kCFAllocatorDefault, data, kCFPropertyListImmutable, NULL, NULL);
    CFRelease(data);
    return pl;
}

// Coerce a CF value into a boolean int.
static int cf_value_to_bool(CFTypeRef v) {
    if (!v) return -1;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) {
        return CFBooleanGetValue((CFBooleanRef)v) ? 1 : 0;
    }
    if (CFGetTypeID(v) == CFNumberGetTypeID()) {
        int n = 0;
        if (CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n)) return n ? 1 : 0;
        return -1;
    }
    if (CFGetTypeID(v) == CFStringGetTypeID()) {
        char buf[8] = {0};
        if (CFStringGetCString((CFStringRef)v, buf, sizeof(buf), kCFStringEncodingUTF8)) {
            if (strcmp(buf, "1") == 0 || strcasecmp(buf, "true") == 0 ||
                strcasecmp(buf, "yes") == 0) return 1;
            if (strcmp(buf, "0") == 0 || strcasecmp(buf, "false") == 0 ||
                strcasecmp(buf, "no") == 0) return 0;
        }
    }
    return -1;
}

// Read the `enabled` boolean from the preference plist.
static int pref_enabled(int default_value) {
    CFPropertyListRef pl = parse_plist_from_file(pref_path());
    if (!pl) return default_value;
    int enabled = default_value;
    if (CFGetTypeID(pl) == CFDictionaryGetTypeID()) {
        CFTypeRef v = CFDictionaryGetValue((CFDictionaryRef)pl, CFSTR("enabled"));
        int b = cf_value_to_bool(v);
        if (b >= 0) enabled = b;
    }
    CFRelease(pl);
    return enabled;
}

// Write the whole plist back with the new enabled value, preserving any other
// keys (notably `port`). We serialize with CFPropertyListCreateData and write
// with a plain open()/write() so we don't depend on CFWriteStream here.
//
// We also run `defaults write` via the privileged shell so that cfprefsd's
// in-memory cache stays in sync — some readers (notably `defaults read`) and
// parts of the CatMCP Settings pane go through cfprefsd rather than reading
// the file directly.
static int pref_set_enabled(int enabled) {
    const char *p = pref_path();

    // Load existing dict (or start empty) so we don't drop `port`.
    CFMutableDictionaryRef dict = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks,
        &kCFTypeDictionaryValueCallBacks);

    CFPropertyListRef pl = parse_plist_from_file(p);
    if (pl) {
        if (CFGetTypeID(pl) == CFDictionaryGetTypeID()) {
            // Copy each existing key into our mutable dict.
            CFIndex count = CFDictionaryGetCount((CFDictionaryRef)pl);
            const void **keys = count ? malloc(sizeof(void *) * count) : NULL;
            const void **vals = count ? malloc(sizeof(void *) * count) : NULL;
            if (keys && vals) {
                CFDictionaryGetKeysAndValues((CFDictionaryRef)pl, keys, vals);
                for (CFIndex i = 0; i < count; i++) {
                    CFDictionarySetValue(dict, keys[i], vals[i]);
                }
            }
            free(keys); free(vals);
        }
        CFRelease(pl);
    } else {
        fprintf(stderr, "pref_set_enabled: parse_plist_from_file returned NULL path=%s\n", p);
    }

    CFDictionarySetValue(dict, CFSTR("enabled"),
                         enabled ? kCFBooleanTrue : kCFBooleanFalse);

    CFDataRef out = CFPropertyListCreateData(
        kCFAllocatorDefault, dict, kCFPropertyListXMLFormat_v1_0, 0, NULL);
    CFRelease(dict);
    if (!out) {
        fprintf(stderr, "pref_set_enabled: CFPropertyListCreateData returned NULL\n");
        return 0;
    }

    int ok = 0;
    int fd = open(p, O_WRONLY | O_TRUNC | O_CREAT, 0600);
    if (fd < 0) {
        fprintf(stderr, "pref_set_enabled: open(%s) failed errno=%d (%s)\n",
                p, errno, strerror(errno));
    } else {
        const UInt8 *bytes = CFDataGetBytePtr(out);
        CFIndex len = CFDataGetLength(out);
        ssize_t w = write(fd, bytes, (size_t)len);
        if (w == (ssize_t)len) {
            ok = 1;
        } else {
            fprintf(stderr, "pref_set_enabled: short write w=%zd len=%ld errno=%d\n",
                    w, (long)len, errno);
        }
        close(fd);
    }
    CFRelease(out);

    // Also run `defaults write` through the privileged shell so cfprefsd's
    // cache matches the file. The direct file write above is what autoinjectd
    // reads, but Settings/defaults readers see the cfprefsd cache.
    run_root_shell("%s/usr/bin/defaults write com.catmcp.server enabled -bool %s 2>/dev/null || true",
                   gJBRoot, enabled ? "true" : "false");

    return ok;
}

static int run_wait(char *const argv[]) {
    pid_t pid = 0;
    int rc = posix_spawnp(&pid, argv[0], NULL, NULL, argv, environ);
    if (rc != 0) {
        fprintf(stderr, "spawn %s failed rc=%d errno=%d (%s)\n",
                argv[0], rc, errno, strerror(errno));
        return 127;
    }
    int st = 0;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(st)) return WEXITSTATUS(st);
    if (WIFSIGNALED(st)) return 128 + WTERMSIG(st);
    return 126;
}

static int run_root_shell(const char *fmt, ...) {
    char inner[1024];
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(inner, sizeof(inner), fmt, ap);
    va_end(ap);

    char cmd[1536];
    char sh[640], cat[640], sudo[640];
    snprintf(sh, sizeof(sh), "%s/usr/bin/sh", gJBRoot);
    snprintf(cat, sizeof(cat), "%s/usr/bin/cat", gJBRoot);
    snprintf(sudo, sizeof(sudo), "%s/usr/bin/sudo", gJBRoot);
    snprintf(cmd, sizeof(cmd),
             "(%s /var/mobile/sudoi.pass 2>/dev/null || "
             "%s %s/var/mobile/sudoi.pass 2>/dev/null) | "
             "%s -S -p '' %s", cat, cat, gJBRoot, sudo, inner);
    char *argv[] = { sh, "-c", cmd, NULL };
    return run_wait(argv);
}

static int catmcp_port_open(void) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 0;
    struct sockaddr_in a;
    memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET;
    a.sin_port = htons(9000);
    a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int ok = (connect(fd, (struct sockaddr *)&a, sizeof(a)) == 0);
    close(fd);
    return ok;
}

// Restart autoinjectd so it re-reads the plist immediately. kickstart -k kills
// the running instance and starts a fresh one in the same job domain.
static int kickstart_autoinjectd(void) {
    int rc = run_root_shell("%s/usr/bin/launchctl kickstart -k user/501/com.ratush.catmcp-autoinjectd",
                             gJBRoot);
    fprintf(stderr, "kickstart autoinjectd rc=%d\n", rc);
    return rc;
}

// Hard kill any leftover catmcp server processes (used when disabling, since
// autoinjectd can take ~20s to notice enabled=false on its poll).
static int killall_catmcp(void) {
    int rc = run_root_shell("%s/usr/bin/killall -9 catmcp 2>/dev/null; true", gJBRoot);
    fprintf(stderr, "killall catmcp rc=%d\n", rc);
    return rc;
}

static int do_enable(void) {
    if (!pref_set_enabled(1)) {
        fprintf(stderr, "failed to write enabled=1\n");
        return 1;
    }
    kickstart_autoinjectd();
    // CatMCP server startup can take a few seconds; wait up to ~30s.
    for (int i = 0; i < 30; i++) {
        if (catmcp_port_open()) {
            printf("on\n");
            return 0;
        }
        sleep(1);
    }
    printf("on-pending\n");
    return 0;
}

static int do_disable(void) {
    if (!pref_set_enabled(0)) {
        fprintf(stderr, "failed to write enabled=0\n");
        return 1;
    }
    kickstart_autoinjectd();
    // autoinjectd may take ~20s to stop the server on its poll loop; help it
    // along by killing the server process directly after a short grace period.
    for (int i = 0; i < 6; i++) {
        if (!catmcp_port_open()) {
            printf("off\n");
            return 0;
        }
        sleep(1);
    }
    killall_catmcp();
    for (int i = 0; i < 6; i++) {
        if (!catmcp_port_open()) {
            printf("off\n");
            return 0;
        }
        sleep(1);
    }
    printf("off-failed\n");
    return 1;
}

int main(int argc, char **argv) {
    // Fully become root: set both real and effective uid/gid to 0. With only
    // setuid-root (euid=0 but ruid=mobile), writes to /private/var/mobile
    // (which is a "protect" APFS mount) are blocked by the kernel MAC policy
    // even though the file is owned by mobile. Calling setuid(0)/setgid(0)
    // promotes ruid too, which is what `sudo` does and the reason sudo writes
    // succeed where a plain setuid binary's do not.
    setgid(0);
    setuid(0);

    init_jbroot();

    int enabled_in_pref = pref_enabled(1);
    int port_open = catmcp_port_open();
    fprintf(stderr,
            "catmcpcchelper euid=%d pref.enabled=%d port9000=%d jbroot=%s\n",
            (int)geteuid(), enabled_in_pref, port_open, gJBRoot);

    const char *cmd = (argc > 1) ? argv[1] : "toggle";

    if (strcmp(cmd, "status") == 0) {
        // Ground truth is the port; the pref is the user intent.
        printf("%s\n", port_open ? "on" : "off");
        return port_open ? 0 : 1;
    }
    if (strcmp(cmd, "pref") == 0) {
        // Report only the preference state (what the Settings switch shows).
        printf("%s\n", enabled_in_pref ? "on" : "off");
        return enabled_in_pref ? 0 : 1;
    }
    if (strcmp(cmd, "on") == 0) {
        return port_open ? (printf("on\n"), 0) : do_enable();
    }
    if (strcmp(cmd, "off") == 0) {
        return port_open ? do_disable() : (printf("off\n"), 0);
    }
    if (strcmp(cmd, "enable") == 0) {
        return do_enable();
    }
    if (strcmp(cmd, "disable") == 0) {
        return do_disable();
    }

    // Default: toggle from observable runtime truth, not just the Settings
    // preference. If CatMCP was started externally while enabled=false, the
    // CC tile must still turn the live service off instead of rewriting
    // enabled=true and showing a fake transition.
    if (port_open) {
        return do_disable();
    } else {
        return do_enable();
    }
}
