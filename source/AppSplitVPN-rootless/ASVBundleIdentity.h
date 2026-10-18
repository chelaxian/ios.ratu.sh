#import <Foundation/Foundation.h>

// LaunchServices retains records for offloaded apps and can return no bundleURL
// for removed apps/extensions. NSBundle rejects nil instead of returning nil.
// An unavailable bundle is not an installed executable and must not abort an
// otherwise valid routing transaction.
static inline NSString *ASVExecutableForBundleURL(id url) {
    if (![url isKindOfClass:NSURL.class] || ![url isFileURL]) return nil;
    @try { return [NSBundle bundleWithURL:url].executablePath; }
    @catch (__unused NSException *exception) { return nil; }
}
