#import "PrivateNetwork.h"
#import "ASVBundleIdentity.h"

// Resolve a fresh snapshot on every reconciliation. Never persist executable
// paths/UUIDs across app updates. A broken LS record must not poison other apps.
static inline NSArray<NSUUID *> *ASVApplicationIdentities(id identifier) {
    if (![identifier isKindOfClass:NSString.class] || ![identifier length]) return @[];
    NSMutableOrderedSet *identities=[NSMutableOrderedSet orderedSet];
    @try {
        id proxy=[NSClassFromString(@"LSApplicationProxy") applicationProxyForIdentifier:identifier];
        id url=[proxy respondsToSelector:@selector(bundleURL)]?[proxy bundleURL]:nil;
        NSString *path=ASVExecutableForBundleURL(url);
        // Missing executable means removed/offloaded/updating, even if LS still
        // returns stale Mach-O UUIDs from a previous installation.
        if (!path.length) return @[];
        id resolved=[NSClassFromString(@"NEProcessInfo") copyUUIDsForBundleID:identifier uid:501];
        if (![resolved isKindOfClass:NSArray.class] || ![resolved count])
            resolved=[NSClassFromString(@"NEProcessInfo") copyUUIDsForExecutable:path];
        if ([resolved isKindOfClass:NSArray.class]) for(id uuid in resolved)
            if([uuid isKindOfClass:NSUUID.class])[identities addObject:uuid];
        id plugins=[proxy respondsToSelector:@selector(plugInKitPlugins)]?[proxy plugInKitPlugins]:nil;
        if ([plugins isKindOfClass:NSArray.class]) for(id plugin in plugins) {
            @try {
                id pluginURL=[plugin respondsToSelector:@selector(bundleURL)]?[plugin bundleURL]:nil;
                NSString *executable=ASVExecutableForBundleURL(pluginURL);
                if(!executable.length)continue;
                id extensions=[NSClassFromString(@"NEProcessInfo") copyUUIDsForExecutable:executable];
                if([extensions isKindOfClass:NSArray.class])for(id uuid in extensions)
                    if([uuid isKindOfClass:NSUUID.class])[identities addObject:uuid];
            } @catch(NSException *exception) {
                NSLog(@"AppSplitVPN: skipped extension of %@ (%@)",identifier,exception.name);
            }
        }
    } @catch(NSException *exception) {
        NSLog(@"AppSplitVPN: skipped application %@ (%@)",identifier,exception.name);
        return @[];
    }
    return identities.array;
}
