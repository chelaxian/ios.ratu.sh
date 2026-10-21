#import "PolicyEngine.h"
#import "ASVApplicationIdentity.h"
@implementation ASVPolicyEngine {
    NEPolicySession *_session;
    NSUInteger _count;
    NSArray *_unresolved;
    NSArray *_installedDNSRules;
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
    _installedDNSRules=nil;
    self.directDNSRules=nil;
    return result;
}
- (void)dealloc { [self clear]; }
- (BOOL)replaceMatrix:(NSDictionary<NSString *,NSString *> *)matrix interfaces:(NSDictionary<NSString *,NSString *> *)interfaces providerIDs:(NSArray<NSString *> *)providers error:(NSString **)error {
    Class result=NSClassFromString(@"NEPolicyResult");
    NEPolicySession *candidate=[NSClassFromString(@"NEPolicySession") new];candidate.priority=1;
    NSMutableArray *unresolved=[NSMutableArray array];NSUInteger count=0;
    [NSClassFromString(@"NEProcessInfo") clearUUIDCache];
    // Do not override Apple's native provider transport attribution with an
    // effectiveApplication DIRECT rule: it changes native flow attribution. The
    // ordinary DIRECT fallback below covers nonassigned transport processes;
    // assigned flows SKIP into Apple's per-app socket/DNS policies. The working
    // research prototype had no accepted provider-specific policies either.
    (void)providers;
    for(NSUUID *uuid in self.selfUUIDs) {
        id p=[[NSClassFromString(@"NEPolicy") alloc] initWithOrder:20 result:[result skipWithOrder:0] conditions:@[[NSClassFromString(@"NEPolicyCondition") effectiveApplication:uuid],[NSClassFromString(@"NEPolicyCondition") allInterfaces]]];
        if(![candidate addPolicy:p]){if(error)*error=@"Supervisor exception rejected";return NO;}count++;
    }
    for(NSString *identifier in matrix) {
        NSArray *identities=ASVApplicationIdentities(identifier);
        if(!identities.count){
            [unresolved addObject:identifier];
            continue;
        }
        NSString *interface=interfaces[matrix[identifier]];
        // Native NEVPNApp rules select the assigned session. A hand-written
        // IP_TUNNEL result failed live tests; don't replace Apple's per-app
        // socket and DNS selection. Not-ready assignments remain fail-closed.
        id outcome=interface.length?[result skipWithOrder:0]:[result drop];
        for(NSUUID *uuid in identities) {
            if(count>=4096){if(error)*error=@"Matrix application rule limit exceeded";return NO;}
            id p=[[NSClassFromString(@"NEPolicy") alloc] initWithOrder:100 result:outcome conditions:@[[NSClassFromString(@"NEPolicyCondition") effectiveApplication:uuid],[NSClassFromString(@"NEPolicyCondition") allInterfaces]]];
            if(![candidate addPolicy:p]){if(error)*error=@"Matrix application policy rejected";return NO;}count++;
        }
    }
    id fallback=[[NSClassFromString(@"NEPolicy") alloc] initWithOrder:1000 result:[result scopeToDirectInterface] conditions:@[[NSClassFromString(@"NEPolicyCondition") allInterfaces]]];
    if(![candidate addPolicy:fallback] || ![candidate apply]){if(error)*error=@"Matrix policies could not be applied";return NO;}
    NEPolicySession *previous=_session;_session=candidate;_count=count+1;_unresolved=unresolved;
    [previous removeAllPolicies];[previous apply];_installedDNSRules=nil;return YES;
}
- (BOOL)replaceMode:(NSString *)mode applications:(NSArray<NSString *> *)apps error:(NSString **)error {
    if (![@[@"tunnelOnly", @"bypass"] containsObject:mode]) {
        if (error) *error = @"Invalid routing mode";
        return NO;
    }
    NSMutableOrderedSet<NSUUID *> *uuids = [NSMutableOrderedSet orderedSet];
    NSMutableArray *unresolved = [NSMutableArray array];
    [NSClassFromString(@"NEProcessInfo") clearUUIDCache];
    for (NSString *identifier in apps) {
        NSArray *resolved = ASVApplicationIdentities(identifier);
        if (!resolved.count) {
            [unresolved addObject:identifier];
            // Keep the user's selection for reinstall/update; skip only this
            // app. Unresolved apps follow the mode's ordinary default route.
            continue;
        }
        for (id uuid in resolved) if ([uuid isKindOfClass:NSUUID.class]) [uuids addObject:uuid];
    }
    if (uuids.count > 4096) {
        if (error) *error = @"Application rule limit exceeded";
        return NO;
    }
    NEPolicySession *candidate = [NSClassFromString(@"NEPolicySession") new];
    if (!candidate) { if (error) *error = @"NECP session unavailable"; return NO; }
    candidate.priority = 1; // control, ahead of ordinary tunnel policies; verified live.
    BOOL tunnelOnly = [mode isEqualToString:@"tunnelOnly"];
    NSArray *dnsRules=tunnelOnly?@[]:(self.directDNSRules ?: @[]);
    BOOL preserveDNS=dnsRules.count>0 && uuids.count>0;
    NSUInteger dnsCount=dnsRules.count;
    for(NSDictionary *entry in dnsRules)dnsCount+=[entry[@"excluded"] count];
    if (preserveDNS && uuids.count+dnsCount+2>4096) {
        if(error)*error=@"DNS/application rule limit exceeded";
        return NO;
    }
    id selectedResult = tunnelOnly
        ? [NSClassFromString(@"NEPolicyResult") skipWithOrder:0]
        : (preserveDNS?[NSClassFromString(@"NEPolicyResult") skipWithOrder:200]:[NSClassFromString(@"NEPolicyResult") scopeToDirectInterface]);
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
    if (preserveDNS) {
        // Only selected apps jump past this guard. Everyone else leaves this
        // owned session and keeps Apple's VPN and DNS policy unchanged.
        id guard=[[NSClassFromString(@"NEPolicy") alloc] initWithOrder:150 result:[NSClassFromString(@"NEPolicyResult") skipWithOrder:0] conditions:@[[NSClassFromString(@"NEPolicyCondition") allInterfaces]]];
        if(![candidate addPolicy:guard]){if(error)*error=@"DNS application guard rejected";return NO;}count++;
        unsigned order=200;
        for(NSDictionary *entry in dnsRules) {
            id agent=entry[@"agent"];NSString *domain=entry[@"domain"];
            if(![agent isKindOfClass:NSUUID.class] || ![domain isKindOfClass:NSString.class]){if(error)*error=@"Invalid DNS rule";return NO;}
            NSArray *excluded=entry[@"excluded"] ?: @[];
            unsigned next=order+(unsigned)excluded.count+1;
            for(NSString *exception in excluded){
                id skip=[[NSClassFromString(@"NEPolicy") alloc] initWithOrder:order++ result:[NSClassFromString(@"NEPolicyResult") skipWithOrder:next] conditions:@[[NSClassFromString(@"NEPolicyCondition") allInterfaces],[NSClassFromString(@"NEPolicyCondition") domain:exception]]];
                if(![candidate addPolicy:skip]){if(error)*error=@"DNS exclusion rejected";return NO;}count++;
            }
            NSMutableArray *conditions=[NSMutableArray arrayWithObject:[NSClassFromString(@"NEPolicyCondition") allInterfaces]];
            if(domain.length)[conditions addObject:[NSClassFromString(@"NEPolicyCondition") domain:domain]];
            id policy=[[NSClassFromString(@"NEPolicy") alloc] initWithOrder:order++ result:[NSClassFromString(@"NEPolicyResult") netAgentUUID:agent] conditions:conditions];
            if(![candidate addPolicy:policy]){if(error)*error=@"Encrypted DNS policy rejected";return NO;}count++;
        }
        id direct=[[NSClassFromString(@"NEPolicy") alloc] initWithOrder:100000 result:[NSClassFromString(@"NEPolicyResult") scopeToDirectInterface] conditions:@[[NSClassFromString(@"NEPolicyCondition") allInterfaces]]];
        if(![candidate addPolicy:direct]){if(error)*error=@"DNS-preserving DIRECT policy rejected";return NO;}count++;
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
    // Keep published native resolvers alive until their old policy session closes.
    _installedDNSRules=dnsRules;
    return YES;
}
@end
