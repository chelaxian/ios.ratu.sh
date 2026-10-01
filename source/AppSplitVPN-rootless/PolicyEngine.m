#import "PolicyEngine.h"
@implementation ASVPolicyEngine {
    NEPolicySession *_session;
    NSUInteger _count;
    NSArray *_unresolved;
}
- (NSUInteger)count { return _count; }
- (NSArray *)unresolved { return _unresolved ?: @[]; }
- (BOOL)clear {
    BOOL result = YES;
    if (_session) {
        result = [_session removeAllPolicies] && [_session apply];
        // Closing this owned session also removes its kernel policies, including
        // when an explicit apply failed. Never touch another process's policies.
        _session = nil;
    }
    _count = 0;
    _unresolved = @[];
    return result;
}
- (void)dealloc { [self clear]; }
- (BOOL)replaceMode:(NSString *)mode applications:(NSArray<NSString *> *)apps error:(NSString **)error {
    if (![@[@"tunnelOnly", @"bypass"] containsObject:mode]) {
        if (error) *error = @"Invalid routing mode";
        return NO;
    }
    NSMutableOrderedSet<NSUUID *> *uuids = [NSMutableOrderedSet orderedSet];
    NSMutableArray *unresolved = [NSMutableArray array];
    [NSClassFromString(@"NEProcessInfo") clearUUIDCache];
    for (NSString *identifier in apps) {
        NSArray *resolved = [NSClassFromString(@"NEProcessInfo") copyUUIDsForBundleID:identifier uid:501];
        id proxy = [NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:identifier];
        NSURL *bundleURL = [proxy respondsToSelector:@selector(bundleURL)] ? [proxy bundleURL] : nil;
        if (!resolved.count && bundleURL) {
            NSString *path=[NSBundle bundleWithURL:bundleURL].executablePath;
            if (path.length) resolved=[NSClassFromString(@"NEProcessInfo") copyUUIDsForExecutable:path];
        }
        if (!resolved.count) {
            [unresolved addObject:identifier];
            // A deleted/offloaded app cannot launch traffic. Keep its selection
            // for a later reinstall, but do not let it block unrelated rules.
            // An installed app whose identity cannot be resolved is different:
            // TUNNEL ONLY must fail closed rather than leak that app directly.
            BOOL installedExecutable = [NSBundle bundleWithURL:bundleURL].executablePath.length > 0;
            if (installedExecutable && [mode isEqualToString:@"tunnelOnly"]) {
                _unresolved = [unresolved copy];
                if (error) *error=@"Could not resolve a selected VPN application's identity";
                return NO;
            }
            continue;
        }
        for (id uuid in resolved) if ([uuid isKindOfClass:NSUUID.class]) [uuids addObject:uuid];
        // Include extensions even if a later iOS implementation stops including
        // them in copyUUIDsForBundleID. WebKit's effective identity remains the host.
        if ([proxy respondsToSelector:@selector(plugInKitPlugins)]) {
            for (id plugin in [proxy plugInKitPlugins]) {
                if (![plugin respondsToSelector:@selector(bundleURL)]) continue;
                NSURL *url = [plugin bundleURL];
                NSString *executable = [NSBundle bundleWithURL:url].executablePath;
                if (!executable.length) continue;
                for (id uuid in [NSClassFromString(@"NEProcessInfo") copyUUIDsForExecutable:executable])
                    if ([uuid isKindOfClass:NSUUID.class]) [uuids addObject:uuid];
            }
        }
    }
    if (uuids.count > 4096) {
        if (error) *error = @"Application rule limit exceeded";
        return NO;
    }
    NEPolicySession *candidate = [NSClassFromString(@"NEPolicySession") new];
    if (!candidate) { if (error) *error = @"NECP session unavailable"; return NO; }
    candidate.priority = 1; // control, ahead of ordinary tunnel policies; verified live.
    BOOL tunnelOnly = [mode isEqualToString:@"tunnelOnly"];
    id selectedResult = tunnelOnly
        ? [NSClassFromString(@"NEPolicyResult") skipWithOrder:0]
        : [NSClassFromString(@"NEPolicyResult") scopeToDirectInterface];
    NSUInteger count = 0;
    for (NSUUID *uuid in uuids) {
        NSArray *conditions = @[[NSClassFromString(@"NEPolicyCondition") effectiveApplication:uuid],
                                [NSClassFromString(@"NEPolicyCondition") allInterfaces]];
        id policy = [[NSClassFromString(@"NEPolicy") alloc] initWithOrder:100 result:selectedResult conditions:conditions];
        if (![candidate addPolicy:policy]) {
            if (error) *error = @"NECP rejected application rule";
            return NO;
        }
        count++;
    }
    if (tunnelOnly) {
        for (id uuid in self.selfUUIDs) {
            if (![uuid isKindOfClass:NSUUID.class]) continue;
            id own = [[NSClassFromString(@"NEPolicy") alloc] initWithOrder:100
                result:[NSClassFromString(@"NEPolicyResult") skipWithOrder:0]
                conditions:@[[NSClassFromString(@"NEPolicyCondition") effectiveApplication:uuid],[NSClassFromString(@"NEPolicyCondition") allInterfaces]]];
            [candidate addPolicy:own];
        }
        id policy = [[NSClassFromString(@"NEPolicy") alloc] initWithOrder:1000
            result:[NSClassFromString(@"NEPolicyResult") scopeToDirectInterface]
            conditions:@[[NSClassFromString(@"NEPolicyCondition") allInterfaces]]];
        if (![candidate addPolicy:policy]) { if (error) *error = @"NECP rejected default rule"; return NO; }
        count++;
    }
    // Stage before publishing. Keep the previous working session if staging/apply fails.
    if (![candidate apply]) { if (error) *error = @"NECP could not apply rules"; return NO; }
    NEPolicySession *previous = _session;
    _session = candidate;
    _count = count;
    _unresolved = [unresolved copy];
    [previous removeAllPolicies];
    [previous apply];
    return YES;
}
@end
