#include <arpa/inet.h>
#include <CoreFoundation/CoreFoundation.h>
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
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
static char gConfig[768];
static char gPlist[768];
static char gPrefs[768];
static const char *kPrefs = "/var/mobile/Library/Preferences/com.ratush.ccopenssh.plist";

static int exists(const char *p) { struct stat st; return p && stat(p, &st) == 0; }

static void init_jbroot(void) {
    const char *bases[] = {"/var/containers/Bundle/Application", "/private/var/containers/Bundle/Application", NULL};
    for (int i = 0; bases[i] && !gJBRoot[0]; i++) {
        DIR *d = opendir(bases[i]);
        if (!d) continue;
        struct dirent *de;
        while ((de = readdir(d))) {
            if (strncmp(de->d_name, ".jbroot-", 8) == 0) {
                snprintf(gJBRoot, sizeof(gJBRoot), "%s/%s", bases[i], de->d_name);
                break;
            }
        }
        closedir(d);
    }
    if (!gJBRoot[0] && exists("/var/jb/usr/bin/sh")) snprintf(gJBRoot, sizeof(gJBRoot), "/var/jb");
    if (!gJBRoot[0]) snprintf(gJBRoot, sizeof(gJBRoot), "/");
    snprintf(gConfig, sizeof(gConfig), "%s/etc/ssh/sshd_config", gJBRoot);
    snprintf(gPlist, sizeof(gPlist), "%s/Library/LaunchDaemons/com.openssh.sshd.plist", gJBRoot);
    snprintf(gPrefs, sizeof(gPrefs), "%s/var/mobile/Library/Preferences/com.ratush.ccopenssh.plist", gJBRoot);
}

static int run_wait(char *const argv[]) {
    pid_t pid = 0;
    int rc = posix_spawn(&pid, argv[0], NULL, NULL, argv, environ);
    if (rc != 0) return 127;
    int st = 0;
    while (waitpid(pid, &st, 0) < 0 && errno == EINTR) {}
    if (WIFEXITED(st)) return WEXITSTATUS(st);
    if (WIFSIGNALED(st)) return 128 + WTERMSIG(st);
    return 126;
}

static int run_root_shell(const char *fmt, ...) {
    char inner[2048];
    va_list ap; va_start(ap, fmt); vsnprintf(inner, sizeof(inner), fmt, ap); va_end(ap);
    char sh[640], cat[640], sudo[640], cmd[2600];
    snprintf(sh, sizeof(sh), "%s/usr/bin/sh", gJBRoot);
    snprintf(cat, sizeof(cat), "%s/usr/bin/cat", gJBRoot);
    snprintf(sudo, sizeof(sudo), "%s/usr/bin/sudo", gJBRoot);
    snprintf(cmd, sizeof(cmd), "(%s /var/mobile/sudoi.pass 2>/dev/null || %s %s/var/mobile/sudoi.pass 2>/dev/null) | %s -S -p '' %s",
             cat, cat, gJBRoot, sudo, inner);
    char *argv[] = { sh, "-c", cmd, NULL };
    return run_wait(argv);
}

static int port_open(int port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return 0;
    struct sockaddr_in a; memset(&a, 0, sizeof(a));
    a.sin_family = AF_INET; a.sin_port = htons((uint16_t)port); a.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    int ok = connect(fd, (struct sockaddr *)&a, sizeof(a)) == 0;
    close(fd);
    return ok;
}

static CFPropertyListRef read_plist(const char *path) {
    int fd = open(path, O_RDONLY);
    if (fd < 0) return NULL;
    CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
    char b[4096]; ssize_t n;
    while ((n = read(fd, b, sizeof(b))) > 0) CFDataAppendBytes(data, (UInt8 *)b, n);
    close(fd);
    if (CFDataGetLength(data) == 0) { CFRelease(data); return NULL; }
    CFPropertyListRef pl = CFPropertyListCreateWithData(NULL, data, kCFPropertyListImmutable, NULL, NULL);
    CFRelease(data);
    return pl;
}

static int cf_bool(CFDictionaryRef d, CFStringRef k, int def) {
    CFTypeRef v = d ? CFDictionaryGetValue(d, k) : NULL;
    return v && CFGetTypeID(v) == CFBooleanGetTypeID() ? CFBooleanGetValue(v) : def;
}

static int cf_int(CFDictionaryRef d, CFStringRef k, int def) {
    CFTypeRef v = d ? CFDictionaryGetValue(d, k) : NULL;
    int out = def;
    if (v && CFGetTypeID(v) == CFNumberGetTypeID()) CFNumberGetValue(v, kCFNumberIntType, &out);
    return out;
}

static void cf_str(CFDictionaryRef d, CFStringRef k, char *buf, size_t len, const char *def) {
    snprintf(buf, len, "%s", def ? def : "");
    CFTypeRef v = d ? CFDictionaryGetValue(d, k) : NULL;
    if (v && CFGetTypeID(v) == CFStringGetTypeID()) CFStringGetCString(v, buf, len, kCFStringEncodingUTF8);
}

static int valid_ipv4_cidr(const char *s) {
    if (!s || !*s) return 0;
    char tmp[64]; snprintf(tmp, sizeof(tmp), "%s", s);
    char *slash = strchr(tmp, '/');
    if (slash) {
        *slash++ = 0;
        char *end = NULL; long m = strtol(slash, &end, 10);
        if (!end || *end || m < 0 || m > 32) return 0;
    }
    struct in_addr a;
    return inet_pton(AF_INET, tmp, &a) == 1;
}

static void append_acl(CFDictionaryRef prefs, char *out, size_t len) {
    CFTypeRef v = prefs ? CFDictionaryGetValue(prefs, CFSTR("acl")) : NULL;
    if (!v || CFGetTypeID(v) != CFArrayGetTypeID()) return;
    CFArrayRef arr = (CFArrayRef)v;
    char user[128]; cf_str(prefs, CFSTR("username"), user, sizeof(user), "mobile");
    if (!user[0]) snprintf(user, sizeof(user), "mobile");
    strncat(out, "AllowUsers", len - strlen(out) - 1);
    int any = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(arr); i++) {
        CFTypeRef e = CFArrayGetValueAtIndex(arr, i);
        char cidr[64] = {0};
        if (e && CFGetTypeID(e) == CFStringGetTypeID()) CFStringGetCString(e, cidr, sizeof(cidr), kCFStringEncodingUTF8);
        if (!valid_ipv4_cidr(cidr)) continue;
        char item[220]; snprintf(item, sizeof(item), " %s@%s", user, cidr);
        strncat(out, item, len - strlen(out) - 1);
        any = 1;
    }
    if (any) strncat(out, "\n", len - strlen(out) - 1);
    else out[0] = 0;
}

static char *read_text(const char *p) {
    int fd = open(p, O_RDONLY);
    if (fd < 0) return strdup("");
    struct stat st; if (fstat(fd, &st) != 0 || st.st_size < 0 || st.st_size > 1024 * 1024) { close(fd); return strdup(""); }
    char *buf = calloc(1, (size_t)st.st_size + 1);
    read(fd, buf, (size_t)st.st_size);
    close(fd);
    return buf;
}

static int write_text_atomic(const char *p, const char *text, mode_t mode) {
    char tmp[512]; snprintf(tmp, sizeof(tmp), "%s.ccopenssh.tmp", p);
    int fd = open(tmp, O_WRONLY | O_CREAT | O_TRUNC, mode);
    if (fd < 0) return 0;
    size_t len = strlen(text);
    int ok = write(fd, text, len) == (ssize_t)len;
    close(fd);
    if (!ok) { unlink(tmp); return 0; }
    return rename(tmp, p) == 0;
}

static int apply_config(CFDictionaryRef prefs) {
    int port = cf_int(prefs, CFSTR("port"), 2222);
    if (port < 1 || port > 65535) port = 2222;
    int pass = cf_bool(prefs, CFSTR("allowPassword"), 1);
    int key = cf_bool(prefs, CFSTR("allowKey"), 1);
    char block[4096];
    snprintf(block, sizeof(block),
             "\n# BEGIN CCOPENSSH MANAGED\nPort %d\nPasswordAuthentication %s\nKbdInteractiveAuthentication %s\nPubkeyAuthentication %s\n",
             port, pass ? "yes" : "no", pass ? "yes" : "no", key ? "yes" : "no");
    char acl[2048] = {0}; append_acl(prefs, acl, sizeof(acl));
    strncat(block, acl, sizeof(block) - strlen(block) - 1);
    strncat(block, "# END CCOPENSSH MANAGED\n", sizeof(block) - strlen(block) - 1);

    char *old = read_text(gConfig);
    char *start = strstr(old, "# BEGIN CCOPENSSH MANAGED");
    char *end = strstr(old, "# END CCOPENSSH MANAGED");
    char *out = calloc(1, strlen(old) + strlen(block) + 4096);
    if (start && end) {
        end = strchr(end, '\n');
        size_t pre = (size_t)(start - old);
        memcpy(out, old, pre);
        strcat(out, block);
        if (end) strcat(out, end + 1);
    } else {
        strcpy(out, old);
        strcat(out, block);
    }
    int ok = write_text_atomic(gConfig, out, 0644);
    free(old); free(out);

    CFMutableDictionaryRef pl = (CFMutableDictionaryRef)read_plist(gPlist);
    if (pl && CFGetTypeID(pl) == CFDictionaryGetTypeID()) {
        CFMutableDictionaryRef m = CFDictionaryCreateMutableCopy(NULL, 0, pl);
        CFMutableDictionaryRef sockets = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFMutableDictionaryRef listener = CFDictionaryCreateMutable(NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        char ps[16]; snprintf(ps, sizeof(ps), "%d", port);
        CFStringRef pstr = CFStringCreateWithCString(NULL, ps, kCFStringEncodingUTF8);
        CFDictionarySetValue(listener, CFSTR("SockServiceName"), pstr);
        CFDictionarySetValue(sockets, CFSTR("SSHListener"), listener);
        CFDictionarySetValue(m, CFSTR("Sockets"), sockets);
        CFDataRef data = CFPropertyListCreateData(NULL, m, kCFPropertyListXMLFormat_v1_0, 0, NULL);
        if (data) {
            int fd = open(gPlist, O_WRONLY | O_CREAT | O_TRUNC, 0644);
            if (fd >= 0) { write(fd, CFDataGetBytePtr(data), CFDataGetLength(data)); close(fd); ok = 1; }
            CFRelease(data);
        }
        CFRelease(pstr); CFRelease(listener); CFRelease(sockets); CFRelease(m);
    }
    if (pl) CFRelease(pl);
    return ok;
}

static void append_authorized_key(const char *ak, const char *key) {
    if (!key || !*key) return;
    char *old = read_text(ak);
    if (!strstr(old, key)) {
        int fd = open(ak, O_WRONLY | O_CREAT | O_APPEND, 0600);
        if (fd >= 0) { dprintf(fd, "%s\n", key); close(fd); }
    }
    free(old);
}

static void apply_key(CFDictionaryRef prefs) {
    char user[128];
    cf_str(prefs, CFSTR("username"), user, sizeof(user), "mobile");
    char home[768];
    snprintf(home, sizeof(home), "%s/%s", gJBRoot, strcmp(user, "root") == 0 ? "var/root" : "var/mobile");
    char dir[900], ak[960];
    snprintf(dir, sizeof(dir), "%s/.ssh", home);
    snprintf(ak, sizeof(ak), "%s/authorized_keys", dir);
    mkdir(dir, 0700);

    CFTypeRef keys = prefs ? CFDictionaryGetValue(prefs, CFSTR("publicKeys")) : NULL;
    if (keys && CFGetTypeID(keys) == CFArrayGetTypeID()) {
        CFArrayRef arr = (CFArrayRef)keys;
        for (CFIndex i = 0; i < CFArrayGetCount(arr); i++) {
            CFTypeRef e = CFArrayGetValueAtIndex(arr, i);
            char key[4096] = {0};
            if (e && CFGetTypeID(e) == CFStringGetTypeID()) CFStringGetCString(e, key, sizeof(key), kCFStringEncodingUTF8);
            append_authorized_key(ak, key);
        }
    } else {
        char legacy[4096];
        cf_str(prefs, CFSTR("publicKey"), legacy, sizeof(legacy), "");
        append_authorized_key(ak, legacy);
    }

    if (strcmp(user, "root") == 0) run_root_shell("%s/usr/sbin/chown -R root:wheel /var/root/.ssh 2>/dev/null || true", gJBRoot);
    else run_root_shell("%s/usr/sbin/chown -R mobile:mobile /var/mobile/.ssh 2>/dev/null || true", gJBRoot);
}

static void apply_password(CFDictionaryRef prefs) {
    char user[128], pass[256];
    cf_str(prefs, CFSTR("username"), user, sizeof(user), "mobile");
    cf_str(prefs, CFSTR("password"), pass, sizeof(pass), "");
    if (!pass[0] || strchr(pass, '\'') || strchr(user, '\'')) return;
    run_root_shell("printf '%%s\\n%%s\\n' '%s' '%s' | %s/usr/bin/passwd '%s' >/dev/null 2>&1 || true",
                   pass, pass, gJBRoot, user);
}

static CFDictionaryRef load_prefs(void) {
    CFPropertyListRef pl = read_plist(gPrefs);
    if (!pl) pl = read_plist(kPrefs);
    if (pl && CFGetTypeID(pl) == CFDictionaryGetTypeID()) return (CFDictionaryRef)pl;
    if (pl) CFRelease(pl);
    return NULL;
}

static int restart_sshd(int enable) {
    if (enable) {
        run_root_shell("%s/usr/bin/launchctl enable system/com.openssh.sshd 2>/dev/null || true", gJBRoot);
        run_root_shell("%s/usr/bin/launchctl bootout system/com.openssh.sshd 2>/dev/null || true", gJBRoot);
        run_root_shell("%s/usr/bin/launchctl bootstrap system /Library/LaunchDaemons/com.openssh.sshd.plist 2>/dev/null || true", gJBRoot);
        run_root_shell("%s/usr/bin/launchctl kickstart -k system/com.openssh.sshd 2>/dev/null || true", gJBRoot);
    } else {
        run_root_shell("%s/usr/bin/launchctl disable system/com.openssh.sshd 2>/dev/null || true", gJBRoot);
        run_root_shell("%s/usr/bin/launchctl bootout system/com.openssh.sshd 2>/dev/null || true", gJBRoot);
        run_root_shell("%s/usr/bin/killall -9 sshd 2>/dev/null || true", gJBRoot);
    }
    return 0;
}

static int configured_port(CFDictionaryRef prefs) {
    int p = cf_int(prefs, CFSTR("port"), 2222);
    return (p > 0 && p < 65536) ? p : 2222;
}

int main(int argc, char **argv) {
    setgid(0); setuid(0); init_jbroot();
    const char *cmd = argc > 1 ? argv[1] : "status";
    CFDictionaryRef prefs = load_prefs();
    int p = configured_port(prefs);
    if (!strcmp(cmd, "status")) { int on = port_open(p); puts(on ? "on" : "off"); if (prefs) CFRelease(prefs); return on ? 0 : 1; }
    if (!strcmp(cmd, "apply")) { apply_config(prefs); apply_key(prefs); apply_password(prefs); restart_sshd(cf_bool(prefs, CFSTR("enabled"), 1)); if (prefs) CFRelease(prefs); return 0; }
    if (!strcmp(cmd, "on")) { apply_config(prefs); apply_key(prefs); apply_password(prefs); restart_sshd(1); sleep(1); puts(port_open(p) ? "on" : "on-pending"); if (prefs) CFRelease(prefs); return 0; }
    if (!strcmp(cmd, "off")) { restart_sshd(0); sleep(1); puts(port_open(p) ? "off-failed" : "off"); if (prefs) CFRelease(prefs); return port_open(p) ? 1 : 0; }
    if (!strcmp(cmd, "toggle")) { int on = port_open(p); if (prefs) CFRelease(prefs); char *a[] = { argv[0], on ? "off" : "on", NULL }; return main(2, a); }
    if (!strcmp(cmd, "respring")) { if (prefs) CFRelease(prefs); return run_root_shell("%s/usr/bin/sbreload >/dev/null 2>&1 || %s/usr/bin/killall -9 SpringBoard >/dev/null 2>&1", gJBRoot, gJBRoot); }
    fprintf(stderr, "Usage: ccopenssh [status|on|off|toggle|apply|respring]\n");
    if (prefs) CFRelease(prefs);
    return 64;
}
