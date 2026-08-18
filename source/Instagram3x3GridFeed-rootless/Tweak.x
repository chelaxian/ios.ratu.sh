#import <Foundation/Foundation.h>
static NSString *const IGGFPrefs = @"/var/mobile/Library/Preferences/rocket-settings.plist";
static BOOL IGGFIsInstagram(void) { NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @""; return [bid isEqualToString:@"com.burbn.instagram"]; }
static void IGGFWrite(void) {
    NSMutableDictionary *p = [[NSDictionary dictionaryWithContentsOfFile:IGGFPrefs] mutableCopy];
    if (!p) p = [NSMutableDictionary dictionary];
    p[@"GridLayoutEnabled"] = @YES; p[@"DefaultFeedLayout"] = @"Grid";
    p[@"kGridLayoutEnabled"] = @YES; p[@"kDefaultFeedLayout"] = @"Grid";
    [p writeToFile:IGGFPrefs atomically:YES];
}
%ctor { @autoreleasepool { if (IGGFIsInstagram()) IGGFWrite(); } }
