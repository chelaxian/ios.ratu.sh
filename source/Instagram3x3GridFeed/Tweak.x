#import <Foundation/Foundation.h>

static NSString *const IGGFLogPath = @"/var/mobile/Library/Preferences/com.ratush.iggridfeed.log";
static NSString *const IGGFRocketPrefsPath = @"/var/mobile/Library/Preferences/rocket-settings.plist";

static BOOL IGGFIsInstagram(void) {
    NSString *bid = NSBundle.mainBundle.bundleIdentifier ?: @"";
    NSString *exe = NSProcessInfo.processInfo.arguments.firstObject.lastPathComponent ?: @"";
    return [bid isEqualToString:@"com.burbn.instagram"] ||
           [exe isEqualToString:@"Instagram"];
}

static void IGGFLog(NSString *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);

    NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", NSDate.date, line];
    FILE *f = fopen(IGGFLogPath.fileSystemRepresentation, "a");
    if (f) {
        fputs(stamped.UTF8String, f);
        fclose(f);
    }
}

static void IGGFWriteRocketGridPrefs(void) {
    NSMutableDictionary *prefs = [[NSDictionary dictionaryWithContentsOfFile:IGGFRocketPrefsPath] mutableCopy];
    if (!prefs) prefs = [NSMutableDictionary dictionary];

    prefs[@"GridLayoutEnabled"] = @YES;
    prefs[@"DefaultFeedLayout"] = @"Grid";
    prefs[@"kGridLayoutEnabled"] = @YES;
    prefs[@"kDefaultFeedLayout"] = @"Grid";

    BOOL ok = [prefs writeToFile:IGGFRocketPrefsPath atomically:YES];
    IGGFLog(@"rocket grid prefs %@ %@", ok ? @"written" : @"write-failed", prefs);
}

%ctor {
    @autoreleasepool {
        if (!IGGFIsInstagram()) return;
        IGGFWriteRocketGridPrefs();
    }
}
