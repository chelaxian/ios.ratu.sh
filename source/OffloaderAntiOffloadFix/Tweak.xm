#import <Foundation/Foundation.h>

static NSString *const OffloaderAntiOffloadPath =
    @"/var/mobile/Library/Preferences/com.level3tjg.offloader.anti.plist";
static NSString *const OffloaderAntiOffloadErrorDomain =
    @"com.ratush.offloader.anti";

@interface IXAppInstallCoordinator : NSObject
@end

static BOOL OffloaderIsProtectedBundleID(NSString *bundleID) {
    if (![bundleID isKindOfClass:NSString.class] || bundleID.length == 0) {
        return NO;
    }

    NSDictionary *preferences =
        [NSDictionary dictionaryWithContentsOfFile:OffloaderAntiOffloadPath];
    return [preferences[bundleID] boolValue];
}

static NSString *OffloaderBundleIDFromIdentity(id identity) {
    SEL selector = @selector(bundleIdentifier);
    if (![identity respondsToSelector:selector]) {
        return nil;
    }

    id (*implementation)(id, SEL) =
        (id (*)(id, SEL))[identity methodForSelector:selector];
    id value = implementation(identity, selector);
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSError *OffloaderProtectionError(NSString *bundleID) {
    return [NSError errorWithDomain:OffloaderAntiOffloadErrorDomain
                               code:1
                           userInfo:@{
        NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"%@ is protected from offloading.",
                                       bundleID ?: @"The application"]
    }];
}

static BOOL OffloaderRejectSynchronousDemotion(NSString *bundleID,
                                                NSError **error) {
    if (!OffloaderIsProtectedBundleID(bundleID)) {
        return NO;
    }

    if (error) {
        *error = OffloaderProtectionError(bundleID);
    }
    return YES;
}

static BOOL OffloaderRejectAsynchronousDemotion(
    NSString *bundleID,
    void (^completion)(NSError *error)
) {
    if (!OffloaderIsProtectedBundleID(bundleID)) {
        return NO;
    }

    if (completion) {
        completion(OffloaderProtectionError(bundleID));
    }
    return YES;
}

%hook IXAppInstallCoordinator

+ (BOOL)demoteAppToPlaceholderWithBundleID:(NSString *)bundleID
                                 forReason:(NSUInteger)reason
                                     error:(NSError **)error {
    if (OffloaderRejectSynchronousDemotion(bundleID, error)) {
        return NO;
    }
    return %orig;
}

+ (BOOL)demoteAppToPlaceholderWithBundleID:(NSString *)bundleID
                                 forReason:(NSUInteger)reason
                           waitForDeletion:(BOOL)waitForDeletion
                                     error:(NSError **)error {
    if (OffloaderRejectSynchronousDemotion(bundleID, error)) {
        return NO;
    }
    return %orig;
}

+ (BOOL)demoteAppToPlaceholderWithBundleID:(NSString *)bundleID
                                 forReason:(NSUInteger)reason
                           waitForDeletion:(BOOL)waitForDeletion
                      ignoreRemovability:(BOOL)ignoreRemovability
                                     error:(NSError **)error {
    if (OffloaderRejectSynchronousDemotion(bundleID, error)) {
        return NO;
    }
    return %orig;
}

+ (void)demoteAppToPlaceholderWithBundleID:(NSString *)bundleID
                                  forReason:(NSUInteger)reason
                            waitForDeletion:(BOOL)waitForDeletion
                                completion:(void (^)(NSError *error))completion {
    if (OffloaderRejectAsynchronousDemotion(bundleID, completion)) {
        return;
    }
    %orig;
}

+ (void)demoteAppToPlaceholderWithBundleID:(NSString *)bundleID
                                  forReason:(NSUInteger)reason
                            waitForDeletion:(BOOL)waitForDeletion
                       ignoreRemovability:(BOOL)ignoreRemovability
                                completion:(void (^)(NSError *error))completion {
    if (OffloaderRejectAsynchronousDemotion(bundleID, completion)) {
        return;
    }
    %orig;
}

+ (void)_demoteAppToPlaceholderWithBundleID:(NSString *)bundleID
                                   forReason:(NSUInteger)reason
                             waitForDeletion:(BOOL)waitForDeletion
                        ignoreRemovability:(BOOL)ignoreRemovability
                                 completion:(void (^)(NSError *error))completion {
    if (OffloaderRejectAsynchronousDemotion(bundleID, completion)) {
        return;
    }
    %orig;
}

+ (BOOL)demoteAppToPlaceholderWithApplicationIdentity:(id)identity
                                             forReason:(NSUInteger)reason
                                       waitForDeletion:(BOOL)waitForDeletion
                                  ignoreRemovability:(BOOL)ignoreRemovability
                                                 error:(NSError **)error {
    NSString *bundleID = OffloaderBundleIDFromIdentity(identity);
    if (OffloaderRejectSynchronousDemotion(bundleID, error)) {
        return NO;
    }
    return %orig;
}

+ (void)demoteAppToPlaceholderWithApplicationIdentity:(id)identity
                                              forReason:(NSUInteger)reason
                                        waitForDeletion:(BOOL)waitForDeletion
                                   ignoreRemovability:(BOOL)ignoreRemovability
                                             completion:(void (^)(NSError *error))completion {
    NSString *bundleID = OffloaderBundleIDFromIdentity(identity);
    if (OffloaderRejectAsynchronousDemotion(bundleID, completion)) {
        return;
    }
    %orig;
}

%end
