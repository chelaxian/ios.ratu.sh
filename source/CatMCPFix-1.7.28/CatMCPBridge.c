#include <dlfcn.h>
#include <fcntl.h>
#include <notify.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/uio.h>
#include <time.h>
#include <unistd.h>
#include "fishhook.h"

extern void MSHookFunction(void *symbol, void *replace, void **result);

static const char *kLogPath = "/var/mobile/Library/Preferences/catmcp-touch-bridge.log";
static const char *kSlotNotifyPrefix = "com.ratush.catmcp.touchbridge.slot";
static const int kNotifySlots = 64;
static const uint8_t kFrameMagic[4] = { 0xf1, 0xd3, 0x03, 0xca };
static const size_t kMaxFrame = 4096;
static const int kMaxFD = 256;
static ssize_t (*orig_write)(int, const void *, size_t);
static ssize_t (*orig_read)(int, void *, size_t);
static ssize_t (*orig_readv)(int, const struct iovec *, int);
static ssize_t (*orig_recv)(int, void *, size_t, int);
static ssize_t (*orig_recvfrom)(int, void *, size_t, int, struct sockaddr *, socklen_t *);
static int gNotifyTokens[64];
static pthread_mutex_t gPublishLock = PTHREAD_MUTEX_INITIALIZER;
static uint32_t gSequence;
static uint8_t gEpoch;
static int gStartRequested = 0;
static int gStarted = 0;

typedef struct {
    uint8_t data[kMaxFrame + 8];
    size_t length;
} FrameBuffer;

static FrameBuffer gFdBuffers[kMaxFD];

typedef struct {
    uint16_t x;
    uint16_t y;
    uint64_t milliseconds;
} RecentEvent;

static RecentEvent gRecent[3][16];

typedef void (*TouchPointFn)(void *, int, double, double);
typedef void (*TouchUpFn)(void *, int);
static TouchPointFn gOriginalTouchDown;
static TouchPointFn gOriginalTouchMove;
static TouchUpFn gOriginalTouchUp;

static uint64_t monotonic_milliseconds(void) {
    struct timespec ts;
    if (clock_gettime(CLOCK_MONOTONIC, &ts) != 0) return 0;
    return (uint64_t)ts.tv_sec * 1000ULL + (uint64_t)ts.tv_nsec / 1000000ULL;
}

static void slot_name(int slot, char *name, size_t size) {
    snprintf(name, size, "%s.%02d", kSlotNotifyPrefix, slot);
}

static void bridge_log(const char *fmt, ...) {
    int fd = open(kLogPath, O_CREAT | O_WRONLY | O_APPEND, 0644);
    if (fd < 0) return;
    char buf[768];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n > 0) {
        if (n > (int)sizeof(buf)) n = (int)sizeof(buf);
        write(fd, buf, (size_t)n);
        write(fd, "\n", 1);
    }
    close(fd);
}

static const char *find_touch_json(const char *data, size_t len, size_t *outLen) {
    const char *end = data + len;
    const char *p = data;
    while (p < end) {
        const char *hit = memmem(p, (size_t)(end - p), "\"action\":\"touch/", 16);
        if (!hit) return NULL;
        const char *start = hit;
        while (start > data && *start != '{') start--;
        if (*start != '{') {
            p = hit + 1;
            continue;
        }
        const char *stop = hit;
        int depth = 0;
        int inString = 0;
        int escaped = 0;
        for (const char *q = start; q < end; q++) {
            char c = *q;
            if (inString) {
                if (escaped) escaped = 0;
                else if (c == '\\') escaped = 1;
                else if (c == '"') inString = 0;
            } else {
                if (c == '"') inString = 1;
                else if (c == '{') depth++;
                else if (c == '}') {
                    depth--;
                    if (depth == 0) {
                        stop = q + 1;
                        *outLen = (size_t)(stop - start);
                        return start;
                    }
                }
            }
        }
        p = hit + 1;
    }
    return NULL;
}

static void publish_touch_values(int action, int finger, double x, double y) {
    if (action < 0 || action > 2) return;
    if (finger < 0) finger = 0;
    if (finger > 15) finger = 15;
    if (x < 0.0) x = 0.0;
    if (x > 1.0) x = 1.0;
    if (y < 0.0) y = 0.0;
    if (y > 1.0) y = 1.0;

    uint16_t xq = (uint16_t)(x * 65535.0 + 0.5);
    uint16_t yq = (uint16_t)(y * 65535.0 + 0.5);
    uint64_t now = monotonic_milliseconds();
    pthread_mutex_lock(&gPublishLock);
    RecentEvent *recent = &gRecent[action][finger];
    if (recent->x == xq && recent->y == yq && now >= recent->milliseconds &&
        now - recent->milliseconds <= 20) {
        pthread_mutex_unlock(&gPublishLock);
        return;
    }
    recent->x = xq;
    recent->y = yq;
    recent->milliseconds = now;
    if (gSequence > 0) usleep(12000);
    gSequence = (gSequence % 0x3ffffU) + 1U;
    uint64_t packed = ((uint64_t)action & 3ULL) |
        (((uint64_t)finger & 15ULL) << 2) |
        ((uint64_t)xq << 6) |
        ((uint64_t)yq << 22) |
        (((uint64_t)gSequence & 0x3ffffULL) << 38) |
        ((uint64_t)gEpoch << 56);
    int slot = (int)(gSequence % (uint32_t)kNotifySlots);
    int token = gNotifyTokens[slot];
    char name[96];
    slot_name(slot, name, sizeof(name));
    int stateRc = notify_set_state(token, packed);
    int postRc = notify_post(name);
    pthread_mutex_unlock(&gPublishLock);
    if (stateRc != NOTIFY_STATUS_OK || postRc != NOTIFY_STATUS_OK) {
        bridge_log("catmcp bridge publish failed slot=%d epoch=%u seq=%u action=%d finger=%d state=%d post=%d",
                   slot, gEpoch, gSequence, action, finger, stateRc, postRc);
    }
}

static void publish_touch_command(const char *json, size_t len) {
    if (len == 0 || len > 4096) return;
    char tmp[4097];
    memcpy(tmp, json, len);
    tmp[len] = 0;
    int action = -1;
    if (strstr(tmp, "\"touch/down\"")) action = 0;
    else if (strstr(tmp, "\"touch/move\"")) action = 1;
    else if (strstr(tmp, "\"touch/up\"")) action = 2;
    if (action < 0) return;

    int finger = 0;
    double x = 0.0;
    double y = 0.0;
    char *p = strstr(tmp, "\"finger\"");
    if (p && (p = strchr(p, ':'))) finger = (int)strtol(p + 1, NULL, 10);
    p = strstr(tmp, "\"x\"");
    if (p && (p = strchr(p, ':'))) x = strtod(p + 1, NULL);
    p = strstr(tmp, "\"y\"");
    if (p && (p = strchr(p, ':'))) y = strtod(p + 1, NULL);
    publish_touch_values(action, finger, x, y);
}

static void replacement_touch_down(void *self, int finger, double x, double y) {
    (void)self;
    publish_touch_values(0, finger, x, y);
}

static void replacement_touch_move(void *self, int finger, double x, double y) {
    (void)self;
    publish_touch_values(1, finger, x, y);
}

static void replacement_touch_up(void *self, int finger) {
    (void)self;
    publish_touch_values(2, finger, 0.0, 0.0);
}

static void install_direct_touch_hooks(void) {
    void *down = dlsym(RTLD_DEFAULT, "_ZN14_0x2b2cf4e8ec713_0xda6f580d09Eidd");
    void *move = dlsym(RTLD_DEFAULT, "_ZN14_0x2b2cf4e8ec74moveEidd");
    void *up = dlsym(RTLD_DEFAULT, "_ZN14_0x2b2cf4e8ec714_0x61b84fb3185Ei");
    if (down) MSHookFunction(down, (void *)replacement_touch_down, (void **)&gOriginalTouchDown);
    if (move) MSHookFunction(move, (void *)replacement_touch_move, (void **)&gOriginalTouchMove);
    if (up) MSHookFunction(up, (void *)replacement_touch_up, (void **)&gOriginalTouchUp);
    bridge_log("catmcp direct hooks down=%p move=%p up=%p", down, move, up);
}

static ssize_t hooked_write(int fd, const void *buf, size_t count) {
    if (buf && count > 0 && count <= 8192) {
        size_t jsonLen = 0;
        const char *json = find_touch_json((const char *)buf, count, &jsonLen);
        if (json) publish_touch_command(json, jsonLen);
    }
    return orig_write(fd, buf, count);
}

static void consume_frames(FrameBuffer *fb) {
    size_t offset = 0;
    while (fb->length - offset >= 8) {
        if (memcmp(fb->data + offset, kFrameMagic, sizeof(kFrameMagic)) != 0) {
            offset++;
            continue;
        }

        uint32_t bodyLength = 0;
        memcpy(&bodyLength, fb->data + offset + sizeof(kFrameMagic), sizeof(bodyLength));
        if (bodyLength == 0 || bodyLength > kMaxFrame) {
            offset++;
            continue;
        }
        if (fb->length - offset < sizeof(kFrameMagic) + sizeof(bodyLength) + bodyLength) {
            break;
        }

        publish_touch_command((const char *)fb->data + offset + sizeof(kFrameMagic) + sizeof(bodyLength),
                              bodyLength);
        offset += sizeof(kFrameMagic) + sizeof(bodyLength) + bodyLength;
    }

    if (offset > 0) {
        fb->length -= offset;
        memmove(fb->data, fb->data + offset, fb->length);
    }
    if (fb->length > kMaxFrame) fb->length = 0;
}

static void feed_bytes(int fd, const void *data, size_t length) {
    if (fd < 0 || fd >= kMaxFD || !data || length == 0) return;
    FrameBuffer *fb = &gFdBuffers[fd];
    if (length > sizeof(fb->data) - fb->length) fb->length = 0;
    if (length > sizeof(fb->data)) {
        data = (const uint8_t *)data + length - sizeof(fb->data);
        length = sizeof(fb->data);
    }
    memcpy(fb->data + fb->length, data, length);
    fb->length += length;
    consume_frames(fb);
}

static void replace_json_null_number(char *data, size_t len, const char *key, char digit) {
    if (!data || !key) return;
    size_t keyLen = strlen(key);
    char *p = data;
    char *end = data + len;
    while (p < end) {
        char *hit = memmem(p, (size_t)(end - p), key, keyLen);
        if (!hit) return;
        char *colon = memchr(hit + keyLen, ':', (size_t)(end - (hit + keyLen)));
        if (!colon) return;
        char *v = colon + 1;
        while (v < end && (*v == ' ' || *v == '\t' || *v == '\r' || *v == '\n')) v++;
        if ((size_t)(end - v) >= 4 && memcmp(v, "null", 4) == 0) {
            v[0] = digit;
            v[1] = ' ';
            v[2] = ' ';
            v[3] = ' ';
            bridge_log("catmcp bridge sanitized %.*s null", (int)keyLen, key);
        }
        p = colon + 1;
    }
}

static void sanitize_http_json(char *data, size_t len) {
    if (!data || len == 0) return;
    if (!memmem(data, len, "\"method\":\"tools/call\"", 21)) return;
    replace_json_null_number(data, len, "\"finger\"", '0');
    replace_json_null_number(data, len, "\"duration\"", '0');
    replace_json_null_number(data, len, "\"quality\"", '0');
    replace_json_null_number(data, len, "\"scale\"", '1');
}

static ssize_t hooked_read(int fd, void *buffer, size_t length) {
    ssize_t result = orig_read(fd, buffer, length);
    if (result > 0) {
        sanitize_http_json((char *)buffer, (size_t)result);
        feed_bytes(fd, buffer, (size_t)result);
    }
    return result;
}

static ssize_t hooked_readv(int fd, const struct iovec *iov, int iovcnt) {
    ssize_t result = orig_readv(fd, iov, iovcnt);
    if (result <= 0 || !iov) return result;

    ssize_t remaining = result;
    for (int i = 0; i < iovcnt && remaining > 0; i++) {
        size_t n = iov[i].iov_len;
        if ((ssize_t)n > remaining) n = (size_t)remaining;
        sanitize_http_json((char *)iov[i].iov_base, n);
        feed_bytes(fd, iov[i].iov_base, n);
        remaining -= (ssize_t)n;
    }
    return result;
}

static ssize_t hooked_recv(int fd, void *buffer, size_t length, int flags) {
    ssize_t result = orig_recv(fd, buffer, length, flags);
    if (result > 0) {
        sanitize_http_json((char *)buffer, (size_t)result);
        feed_bytes(fd, buffer, (size_t)result);
    }
    return result;
}

static ssize_t hooked_recvfrom(int fd, void *buffer, size_t length, int flags, struct sockaddr *addr, socklen_t *addrLen) {
    ssize_t result = orig_recvfrom(fd, buffer, length, flags, addr, addrLen);
    if (result > 0) {
        sanitize_http_json((char *)buffer, (size_t)result);
        feed_bytes(fd, buffer, (size_t)result);
    }
    return result;
}

__attribute__((visibility("default")))
int catmcp_touch_bridge_start_now(void) {
    if (__sync_lock_test_and_set(&gStarted, 1)) {
        bridge_log("catmcp-touch-bridge start skipped pid=%d", getpid());
        return 1;
    }
    bridge_log("catmcp-touch-bridge start pid=%d", getpid());
    gEpoch = (uint8_t)(((uint32_t)getpid() ^ (uint32_t)time(NULL)) & 0xffU);
    if (gEpoch == 0) gEpoch = 1;
    for (int i = 0; i < kNotifySlots; i++) {
        char name[96];
        slot_name(i, name, sizeof(name));
        int rc = notify_register_check(name, &gNotifyTokens[i]);
        if (rc != NOTIFY_STATUS_OK) bridge_log("notify register failed slot=%d rc=%d", i, rc);
    }
    bridge_log("catmcp-touch-bridge notify slots=%d epoch=%u", kNotifySlots, gEpoch);
    install_direct_touch_hooks();
    struct rebinding b[] = {
        {"write", (void *)hooked_write, (void **)&orig_write},
        {"read", (void *)hooked_read, (void **)&orig_read},
        {"readv", (void *)hooked_readv, (void **)&orig_readv},
        {"recv", (void *)hooked_recv, (void **)&orig_recv},
        {"recvfrom", (void *)hooked_recvfrom, (void **)&orig_recvfrom},
    };
    int rc = rebind_symbols(b, sizeof(b) / sizeof(b[0]));
    bridge_log("catmcp-touch-bridge rebind rc=%d write=%p read=%p readv=%p recv=%p recvfrom=%p",
               rc, orig_write, orig_read, orig_readv, orig_recv, orig_recvfrom);
    return rc;
}

static void *bridge_init_thread(void *unused) {
    (void)unused;
    sleep(1);
    catmcp_touch_bridge_start_now();
    return NULL;
}

__attribute__((visibility("default")))
int catmcp_touch_bridge_start(void) {
    if (__sync_lock_test_and_set(&gStartRequested, 1)) {
        return 1;
    }
    pthread_t t;
    int rc = pthread_create(&t, NULL, bridge_init_thread, NULL);
    if (rc == 0) {
        pthread_detach(t);
    }
    return rc;
}

__attribute__((constructor))
static void catmcp_touch_bridge_init(void) {
    catmcp_touch_bridge_start();
}
