#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>
#import <spawn.h>
#import <sys/wait.h>
#import <unistd.h>
#import <string.h>
#import <fcntl.h>
#import <mach-o/dyld.h>
#import <notify.h>
#import <dispatch/dispatch.h>

extern char **environ;

static NSString *const AVDPrefsPath = @"/var/mobile/Library/Preferences/com.snail.autovpnpref.plist";
static NSString *const AVDEventPath = @"/var/mobile/Library/Preferences/com.ratush.vpnbridge.event.plist";
static NSString *const AVDLogPath = @"/var/mobile/Library/Preferences/com.ratush.vpnbridged.log";
static const char *AVDStateNotification = "com.ratush.vpnbridge.state";

static NSMutableSet *AVDRegisteredNotifications;
static NSMutableDictionary *AVDLastActionAt;
static NSString *AVDLastPrefsPath;
static NSTimeInterval AVDStartedAt;
static BOOL AVDVPNActive;

typedef void *WiFiManagerRef;
typedef void *WiFiDeviceRef;
typedef void *WiFiNetworkRef;
typedef WiFiManagerRef (*WiFiManagerClientCreateFn)(CFAllocatorRef allocator, int flags);
typedef CFArrayRef (*WiFiManagerClientCopyDevicesFn)(WiFiManagerRef manager);
typedef WiFiNetworkRef (*WiFiDeviceClientCopyCurrentNetworkFn)(WiFiDeviceRef device);
typedef CFStringRef (*WiFiNetworkGetSSIDFn)(WiFiNetworkRef network);
typedef CFTypeRef (*WiFiNetworkGetPropertyFn)(WiFiNetworkRef network, CFStringRef property);
typedef void (*MRMediaRemoteGetNowPlayingApplicationIsPlayingFn)(dispatch_queue_t queue, void (^completion)(Boolean isPlaying));

static void AVDSetVPNState(BOOL active) {
    AVDVPNActive = active;
    int token = 0;
    if (notify_register_check(AVDStateNotification, &token) == NOTIFY_STATUS_OK) {
        notify_set_state(token, active ? 1 : 0);
        notify_post(AVDStateNotification);
        notify_cancel(token);
    }
}

static void AVDCLog(const char *line) {
    write(STDERR_FILENO, line, strlen(line));
    write(STDERR_FILENO, "\n", 1);
}

static void AVDLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *entry = [NSString stringWithFormat:@"%@ ratuvpnd %@\n", [[NSDate date] description], line];
    fprintf(stderr, "%s", entry.UTF8String);
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:AVDLogPath];
    if (!fh) {
        [data writeToFile:AVDLogPath atomically:YES];
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:data];
    [fh closeFile];
}

static NSString *AVDExecutableRoot(void) {
    char exe[4096];
    uint32_t size = sizeof(exe);
    if (_NSGetExecutablePath(exe, &size) != 0) {
        return nil;
    }
    NSString *path = [NSString stringWithUTF8String:exe];
    NSRange range = [path rangeOfString:@"/usr/bin/" options:NSBackwardsSearch];
    if (range.location == NSNotFound) {
        return nil;
    }
    return [path substringToIndex:range.location];
}

static NSDictionary *AVDPrefsFromEvent(NSDictionary *event) {
    id prefs = event[@"prefs"];
    if ([prefs isKindOfClass:NSDictionary.class] && [(NSDictionary *)prefs count] > 0) {
        AVDLastPrefsPath = @"<event>";
        return prefs;
    }
    NSArray *paths = @[
        @"/private/var/mobile/Library/Preferences/com.ratush.vpnbridge.prefs.plist",
        @"/var/mobile/Library/Preferences/com.ratush.vpnbridge.prefs.plist"
    ];
    for (NSString *path in paths) {
        NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([snapshot isKindOfClass:NSDictionary.class]) {
            AVDLastPrefsPath = path;
            return snapshot;
        }
    }
    return nil;
}

static NSDictionary *AVDPrefs(NSDictionary *event) {
    NSDictionary *eventPrefs = AVDPrefsFromEvent(event);
    if (eventPrefs) {
        return eventPrefs;
    }
    NSMutableArray *paths = [NSMutableArray array];
    NSString *root = AVDExecutableRoot();
    if (root.length) {
        [paths addObjectsFromArray:@[
            [root stringByAppendingPathComponent:@"var/mobile/Library/Preferences/com.snail.autovpnpref.plist"],
            [root stringByAppendingPathComponent:@"private/var/mobile/Library/Preferences/com.snail.autovpnpref.plist"],
            [root stringByAppendingPathComponent:@"usr/share/ratuvpnbridge/apps.plist"]
        ]];
    }
    [paths addObjectsFromArray:@[
        AVDPrefsPath,
        @"/var/jb/var/mobile/Library/Preferences/com.snail.autovpnpref.plist",
        @"/private/var/mobile/Library/Preferences/com.snail.autovpnpref.plist",
        @"/var/jb/usr/share/ratuvpnbridge/apps.plist",
        @"/usr/share/ratuvpnbridge/apps.plist"
    ]];
    for (NSString *path in paths) {
        NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([prefs isKindOfClass:NSDictionary.class]) {
            AVDLastPrefsPath = path;
            return prefs;
        }
    }
    AVDLastPrefsPath = @"<none>";
    return @{};
}

static NSDictionary *AVDEvent(void) {
    NSDictionary *event = [NSDictionary dictionaryWithContentsOfFile:AVDEventPath];
    return [event isKindOfClass:NSDictionary.class] ? event : @{};
}

static BOOL AVDBool(NSDictionary *prefs, NSString *key, BOOL fallback) {
    id value = prefs[key];
    return value ? [value boolValue] : fallback;
}

static BOOL AVDContains(NSDictionary *prefs, NSString *key, NSString *value) {
    id array = prefs[key];
    if (!value.length || ![array isKindOfClass:NSArray.class]) {
        return NO;
    }
    for (id item in (NSArray *)array) {
        if ([item isKindOfClass:NSString.class] && [(NSString *)item isEqualToString:value]) {
            return YES;
        }
    }
    return NO;
}

static NSArray *AVDStringArray(NSDictionary *prefs, NSString *key) {
    id array = prefs[key];
    if (![array isKindOfClass:NSArray.class]) {
        return @[];
    }
    NSMutableArray *out = [NSMutableArray array];
    for (id value in (NSArray *)array) {
        if ([value isKindOfClass:NSString.class] && [value length]) {
            [out addObject:value];
        } else if ([value isKindOfClass:NSDictionary.class]) {
            NSDictionary *dict = value;
            id ssid = dict[@"ssid"] ?: dict[@"SSID"] ?: dict[@"name"];
            if ([ssid isKindOfClass:NSString.class] && [ssid length]) {
                [out addObject:ssid];
            }
        }
    }
    return out;
}

static NSString *AVDCurrentSSID(void) {
    void *handle = dlopen("/System/Library/PrivateFrameworks/MobileWiFi.framework/MobileWiFi", RTLD_LAZY);
    if (!handle) {
        return nil;
    }
    WiFiManagerClientCreateFn create = (WiFiManagerClientCreateFn)dlsym(handle, "WiFiManagerClientCreate");
    WiFiManagerClientCopyDevicesFn copyDevices = (WiFiManagerClientCopyDevicesFn)dlsym(handle, "WiFiManagerClientCopyDevices");
    WiFiDeviceClientCopyCurrentNetworkFn copyCurrent = (WiFiDeviceClientCopyCurrentNetworkFn)dlsym(handle, "WiFiDeviceClientCopyCurrentNetwork");
    WiFiNetworkGetSSIDFn getSSID = (WiFiNetworkGetSSIDFn)dlsym(handle, "WiFiNetworkGetSSID");
    if (!create || !copyDevices || !copyCurrent || !getSSID) {
        return nil;
    }
    WiFiManagerRef manager = create(kCFAllocatorDefault, 0);
    if (!manager) {
        return nil;
    }
    CFArrayRef devices = copyDevices(manager);
    if (!devices || CFArrayGetCount(devices) == 0) {
        if (devices) CFRelease(devices);
        CFRelease(manager);
        return nil;
    }
    WiFiDeviceRef device = (WiFiDeviceRef)CFArrayGetValueAtIndex(devices, 0);
    WiFiNetworkRef network = copyCurrent(device);
    NSString *ssid = nil;
    if (network) {
        CFStringRef cfSSID = getSSID(network);
        if (cfSSID) {
            ssid = [(__bridge NSString *)cfSSID copy];
        }
        CFRelease(network);
    }
    CFRelease(devices);
    CFRelease(manager);
    return ssid;
}

static BOOL AVDWiFiDisabled(NSDictionary *prefs) {
    NSArray *banned = AVDStringArray(prefs, @"bannedWiFis");
    if (banned.count == 0) {
        return NO;
    }
    NSString *ssid = AVDCurrentSSID();
    if (!ssid.length) {
        return NO;
    }
    return [banned containsObject:ssid];
}

static BOOL AVDLikelyMediaPlayingForBundle(NSString *bundleID) {
    (void)bundleID;
    void *handle = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    if (!handle) {
        return NO;
    }
    MRMediaRemoteGetNowPlayingApplicationIsPlayingFn isPlayingFn =
        (MRMediaRemoteGetNowPlayingApplicationIsPlayingFn)dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    if (!isPlayingFn) {
        return NO;
    }
    __block BOOL playing = NO;
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    isPlayingFn(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^(Boolean isPlaying) {
        playing = isPlaying ? YES : NO;
        dispatch_semaphore_signal(semaphore);
    });
    dispatch_time_t timeout = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(500 * NSEC_PER_MSEC));
    dispatch_semaphore_wait(semaphore, timeout);
    return playing;
}

static void AVDSpawn(NSString *command, NSString *bundleID) {
    NSString *key = [NSString stringWithFormat:@"%@:%@", command, bundleID ?: @""];
    NSTimeInterval now = [NSDate date].timeIntervalSince1970;
    NSNumber *last = AVDLastActionAt[key];
    if (last && (now - last.doubleValue) < 5.0) {
        AVDLog(@"%@ for %@ skipped debounce", command, bundleID);
        return;
    }
    AVDLastActionAt[key] = @(now);

    NSMutableArray *candidates = [NSMutableArray arrayWithObjects:
        @"/usr/bin/ratuvpnctl",
        @"/var/jb/usr/bin/ratuvpnctl",
        nil];
    char exe[4096];
    uint32_t size = sizeof(exe);
    if (_NSGetExecutablePath(exe, &size) == 0) {
        NSString *path = [NSString stringWithUTF8String:exe];
        NSString *sibling = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"ratuvpnctl"];
        if (sibling.length) {
            [candidates insertObject:sibling atIndex:0];
        }
    }
    int lastRC = 0;
    for (NSString *candidate in candidates) {
        const char *tool = candidate.UTF8String;
        char *argv[] = {
            (char *)tool,
            (char *)command.UTF8String,
            (char *)(bundleID ?: @"").UTF8String,
            NULL
        };
        pid_t pid = 0;
        int rc = posix_spawn(&pid, tool, NULL, NULL, argv, environ);
        if (rc != 0) {
            lastRC = rc;
            continue;
        }
        int status = 0;
        waitpid(pid, &status, 0);
        BOOL ok = WIFEXITED(status) && WEXITSTATUS(status) == 0;
        if ([command isEqualToString:@"start"] && ok) {
            AVDSetVPNState(YES);
        } else if ([command isEqualToString:@"stop"] && ok) {
            AVDSetVPNState(NO);
        }
        AVDLog(@"%@ for %@ via %@ pid=%d status=%d", command, bundleID, candidate, pid, status);
        return;
    }
    AVDLog(@"spawn %@ for %@ failed lastRC=%d", command, bundleID, lastRC);
}

static void AVDHandleEvent(NSString *action, NSString *bundleID, NSDictionary *event) {
    NSDictionary *prefs = AVDPrefs(event ?: @{});
    BOOL enabled = AVDBool(prefs, @"isEnabled", YES);
    BOOL wifiDisabled = AVDWiFiDisabled(prefs);

    if (!enabled || wifiDisabled) {
        AVDLog(@"event=%@ bundle=%@ ignored enabled=%d wifiDisabled=%d", action, bundleID, enabled, wifiDisabled);
        if (AVDVPNActive || [action isEqualToString:@"prefs"]) {
            AVDSpawn(@"stop", wifiDisabled ? @"wifi-disabled" : @"disabled");
        }
        return;
    }

    NSTimeInterval uptime = [NSDate date].timeIntervalSince1970 - AVDStartedAt;
    if ([action isEqualToString:@"active"]) {
        BOOL stopRule = AVDContains(prefs, @"noNeedVPNApps", bundleID);
        BOOL startRule = AVDContains(prefs, @"needVPNApps", bundleID);
        if (stopRule) {
            AVDLog(@"active %@ stopRule=1 prefs=%@", bundleID, AVDLastPrefsPath);
            AVDSpawn(@"stop", bundleID);
        } else if (startRule) {
            if (uptime < 10.0 && !AVDBool(prefs, @"isTrunonVPNAfterSpring", NO)) {
                AVDLog(@"active %@ start skipped startup grace", bundleID);
                return;
            }
            AVDLog(@"active %@ startRule=1 prefs=%@", bundleID, AVDLastPrefsPath);
            AVDSpawn(@"start", bundleID);
        }
        return;
    }

    if ([action isEqualToString:@"home"] || [action isEqualToString:@"background"]) {
        if (AVDBool(prefs, @"isTrunoffVPNOnSpringBoard", NO)) {
            if (AVDBool(prefs, @"isTurnHoldWhenPlaying", YES) && AVDLikelyMediaPlayingForBundle(bundleID)) {
                AVDLog(@"%@ %@ held for playback", action, bundleID);
            } else {
                AVDSpawn(@"stop", bundleID.length ? bundleID : @"springboard");
            }
        }
        return;
    }

    if ([action isEqualToString:@"killed"]) {
        if (AVDBool(prefs, @"isTurnoffVPNWhenDeleted", YES)) {
            AVDSpawn(@"stop", bundleID.length ? bundleID : @"killed");
        }
        return;
    }

    if ([action isEqualToString:@"lock"]) {
        if (AVDBool(prefs, @"isTurnoffVPNWhenLocked", YES)) {
            AVDSpawn(@"stop", @"lock");
        }
        return;
    }

    if ([action isEqualToString:@"prefs"]) {
        if (AVDVPNActive && (!enabled || wifiDisabled)) {
            AVDSpawn(@"stop", @"prefs");
        }
        return;
    }
}

static void AVDDarwinCallback(CFNotificationCenterRef center,
                              void *observer,
                              CFStringRef name,
                              const void *object,
                              CFDictionaryRef userInfo) {
    (void)center; (void)observer; (void)object; (void)userInfo;
    NSString *notification = (__bridge NSString *)name;
    if ([notification isEqualToString:@"com.ratush.vpnbridge.event"]) {
        NSDictionary *event = AVDEvent();
        NSString *action = [event[@"action"] isKindOfClass:NSString.class] ? event[@"action"] : @"";
        NSString *bundleID = [event[@"bundle"] isKindOfClass:NSString.class] ? event[@"bundle"] : @"";
        AVDLog(@"event=%@ bundle=%@", action, bundleID);
        AVDHandleEvent(action, bundleID, event);
        return;
    }
    if ([notification isEqualToString:@"com.snail.autovpnpref/ReloadPrefs"]) {
        AVDLog(@"prefs reload");
        AVDHandleEvent(@"prefs", @"prefs", @{});
    }
}

static void AVDRegister(NSString *name) {
    if ([AVDRegisteredNotifications containsObject:name]) {
        return;
    }
    [AVDRegisteredNotifications addObject:name];
    CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                    NULL,
                                    AVDDarwinCallback,
                                    (__bridge CFStringRef)name,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
    AVDLog(@"registered %@", name);
}

int main(int argc, char **argv) {
    AVDCLog("ratuvpnd main entered");
    @autoreleasepool {
        BOOL once = argc > 1 && strcmp(argv[1], "--once") == 0;
        AVDStartedAt = [NSDate date].timeIntervalSince1970;
        AVDRegisteredNotifications = [NSMutableSet set];
        AVDLastActionAt = [NSMutableDictionary dictionary];
        AVDSetVPNState(NO);
        AVDLog(@"starting once=%d", once);
        AVDRegister(@"com.ratush.vpnbridge.event");
        AVDRegister(@"com.snail.autovpnpref/ReloadPrefs");

        NSDictionary *prefs = AVDPrefs(@{});
        if (AVDBool(prefs, @"isEnabled", YES) &&
            !AVDWiFiDisabled(prefs) &&
            AVDBool(prefs, @"isTrunonVPNAfterSpring", NO)) {
            AVDSpawn(@"start", @"daemon-startup");
        }
        if (once) {
            AVDLog(@"once registered=%lu", (unsigned long)AVDRegisteredNotifications.count);
            return 0;
        }
        CFRunLoopRun();
    }
    return 0;
}
