#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>

static void Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *line = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSString *stamp = [[NSDate date] description];
    NSString *entry = [NSString stringWithFormat:@"%@ ratuvpnctl %@\n", stamp, line];
    fprintf(stderr, "%s", entry.UTF8String);
    NSData *data = [entry dataUsingEncoding:NSUTF8StringEncoding];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/var/mobile/Library/Preferences/com.ratush.vpnbridge.log"];
    if (!fh) {
        [data writeToFile:@"/var/mobile/Library/Preferences/com.ratush.vpnbridge.log" atomically:YES];
        return;
    }
    [fh seekToEndOfFile];
    [fh writeData:data];
    [fh closeFile];
}

static BOOL BoolMessage(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return NO;
    }
    BOOL (*send)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
    return send(object, selector);
}

static id ObjectMessage(id object, SEL selector) {
    if (!object || ![object respondsToSelector:selector]) {
        return nil;
    }
    id (*send)(id, SEL) = (id (*)(id, SEL))objc_msgSend;
    return send(object, selector);
}

static NSString *ManagerName(id manager) {
    id name = ObjectMessage(manager, NSSelectorFromString(@"localizedDescription"));
    return [name isKindOfClass:NSString.class] ? name : @"";
}

static BOOL LooksAppleVPNName(NSString *name) {
    NSString *lower = name.lowercaseString ?: @"";
    return [lower hasPrefix:@"com.apple"] ||
        [lower containsString:@"privaterelay"] ||
        [lower containsString:@"networkprivacy"];
}

static NSArray *LoadManagers(void) {
    dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension", RTLD_NOW);
    dlopen("/System/Library/PrivateFrameworks/NetworkExtension.framework/NetworkExtension", RTLD_NOW);
    Class managerClass = NSClassFromString(@"NETunnelProviderManager");
    if (!managerClass) {
        Log(@"NETunnelProviderManager unavailable");
        return @[];
    }

    __block NSArray *result = nil;
    __block NSError *loadError = nil;
    __block BOOL done = NO;
    void (^completion)(NSArray *, NSError *) = ^(NSArray *managers, NSError *error) {
        result = [managers copy];
        loadError = error;
        done = YES;
    };

    SEL selector = NSSelectorFromString(@"loadAllFromPreferencesWithCompletionHandler:");
    if (![managerClass respondsToSelector:selector]) {
        Log(@"manager class misses loadAll");
        return @[];
    }
    ((void (*)(id, SEL, id))objc_msgSend)(managerClass, selector, completion);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (!done && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    if (!done) {
        Log(@"load managers timed out");
        return @[];
    }
    if (loadError) {
        Log(@"load managers error=%@", loadError);
    }
    return [result isKindOfClass:NSArray.class] ? result : @[];
}

static id PickManager(NSArray *managers) {
    for (id manager in managers) {
        NSString *name = ManagerName(manager);
        if (BoolMessage(manager, NSSelectorFromString(@"isEnabled")) && !LooksAppleVPNName(name)) {
            return manager;
        }
    }
    for (id manager in managers) {
        NSString *name = ManagerName(manager);
        if (!LooksAppleVPNName(name)) {
            return manager;
        }
    }
    return nil;
}

static int StartVPN(void) {
    id manager = PickManager(LoadManagers());
    if (!manager) {
        Log(@"start: no manager");
        return 2;
    }
    id connection = ObjectMessage(manager, NSSelectorFromString(@"connection"));
    if (!connection) {
        Log(@"start: manager %@ has no connection", ManagerName(manager));
        return 3;
    }

    NSError *error = nil;
    SEL selector = NSSelectorFromString(@"startVPNTunnelAndReturnError:");
    BOOL ok = NO;
    if ([connection respondsToSelector:selector]) {
        ok = ((BOOL (*)(id, SEL, NSError **))objc_msgSend)(connection, selector, &error);
    }
    Log(@"start %@ ok=%d err=%@", ManagerName(manager), ok, error);
    return ok ? 0 : 4;
}

static int StopVPN(void) {
    NSArray *managers = LoadManagers();
    NSUInteger count = 0;
    for (id manager in managers) {
        NSString *name = ManagerName(manager);
        if (LooksAppleVPNName(name)) {
            continue;
        }
        id connection = ObjectMessage(manager, NSSelectorFromString(@"connection"));
        if ([connection respondsToSelector:NSSelectorFromString(@"stopVPNTunnel")]) {
            ((void (*)(id, SEL))objc_msgSend)(connection, NSSelectorFromString(@"stopVPNTunnel"));
            count++;
            Log(@"stop %@", name);
        }
    }
    return count ? 0 : 2;
}

int main(int argc, char **argv) {
    @autoreleasepool {
        if (argc < 2) {
            Log(@"missing command");
            return 64;
        }
        NSString *command = [NSString stringWithUTF8String:argv[1]];
        if ([command isEqualToString:@"start"]) {
            return StartVPN();
        }
        if ([command isEqualToString:@"stop"]) {
            return StopVPN();
        }
        Log(@"unknown command %@", command);
        return 64;
    }
}
