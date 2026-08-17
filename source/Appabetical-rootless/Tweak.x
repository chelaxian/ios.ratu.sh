// =============================================================================
//  Appabetical RH — Dopamine icon sorter (SpringBoard tweak)
//
//  Fork/adaptation of Avangelista/Appabetical
//  (https://github.com/Avangelista/Appabetical). The IconState.plist model +
//  validation approach is ported from the original (Swift). This derivative is
//  licensed under GPLv3 (see LICENSE), same as the original.
//
//  Layout-preset save/restore is inspired by OwnGoalStudio/IconRestore.
//
//  Sort order (top priority wins):
//   1. Offloaded apps last (toggle): cloud-badge apps to the very end.
//   2. Bookmarks last (toggle): web-clip shortcuts to the very end (after
//      offloaded if both are on).
//   3. Item-kind tier: single app icons (t0) before folders (t1) before
//      home-screen Shortcuts icons (t2) on the Home Screen.
//   4. Language bucket: Latin A-Z, then Cyrillic А-Я, then other (stable).
//   5. Within a group: case-insensitive numeric-aware compare.
//
//  "Ignore emoji" strips emoji/pictograph glyphs from the sort key so e.g. a
//  name like 🌍VPN🌏 sorts under V.
//
//  Layout presets: snapshot the current IconState to a named preset, restore it
//  later, or delete it. Stored in a shared plist, triggered from the prefs
//  bundle via Darwin notifications.
//
//  Paths use the real view (SpringBoard is a real process).
// =============================================================================

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <notify.h>
#import <unistd.h>
#import <dlfcn.h>

// Forward declaration so jbroot/CC helpers (defined just below) can log.
static void ABLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);

// -----------------------------------------------------------------------------
// Paths & keys.
// -----------------------------------------------------------------------------
static NSString *const kDomain        = @"com.ratush.appabetical";
static NSString *const kIconStatePath = @"/var/mobile/Library/SpringBoard/IconState.plist";
static NSString *const kIconStateNew  = @"/var/mobile/Library/SpringBoard/IconState.plist.new";
static NSString *const kIconStateBkp  = @"/var/mobile/Library/SpringBoard/IconState.plist.appabkp";
static NSString *const kLogPath       = @"/var/mobile/Library/Preferences/com.ratush.appabetical.debug.log";
static NSString *const kWebClipsDir   = @"/var/mobile/Library/WebClips";
// Presets live next to IconState so they survive and are easy to inspect.
static NSString *const kPresetsPath   = @"/var/mobile/Library/SpringBoard/AppabeticalPresets.plist";

static NSString *const kNotifSortNow      = @"com.ratush.appabetical.sortnow";
static NSString *const kNotifReload       = @"com.ratush.appabetical.reload";
static NSString *const kNotifPresetSave   = @"com.ratush.appabetical.preset.save";
static NSString *const kNotifPresetApply  = @"com.ratush.appabetical.preset.apply";
static NSString *const kNotifPresetDelete = @"com.ratush.appabetical.preset.delete";
static NSString *const kNotifSortDone     = @"com.ratush.appabetical.sortdone";

static NSString *const kKeyEnabled       = @"enabled";
static NSString *const kKeyPlaceOffEnd   = @"placeOffloadedAtEnd";
static NSString *const kKeyPlaceBkmkEnd  = @"placeBookmarksAtEnd";
static NSString *const kKeyIgnoreEmoji   = @"ignoreEmoji";
static NSString *const kKeySortFolders   = @"sortFolders";
static NSString *const kKeySortInside    = @"sortInsideFolders";
static NSString *const kKeyIncludeDock   = @"includeDock";
static NSString *const kKeyAutoSort      = @"autoSortOnRespring";
// Layout-preset toggle: also snapshot/restore the Control Center layout.
static NSString *const kKeyPreserveCC   = @"preserveCC";

static NSString *ABCCSupportPath(void) {
    return @"/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist";
}
static NSString *ABCCConfigPath(void) {
    return @"/var/mobile/Library/ControlCenter/ModuleConfiguration.plist";
}

// -----------------------------------------------------------------------------
// File logger. Only short summaries, so it does not grow unbounded.
// -----------------------------------------------------------------------------
static void ABLog(NSString *fmt, ...) NS_FORMAT_FUNCTION(1, 2);
static void ABLog(NSString *fmt, ...) {
    va_list ap; va_start(ap, fmt);
    NSString *line = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSString *stamped = [NSString stringWithFormat:@"%@ %@\n", [NSDate date], line];
    FILE *f = fopen(kLogPath.fileSystemRepresentation, "a");
    if (f) { fputs(stamped.UTF8String, f); fclose(f); }
}

// -----------------------------------------------------------------------------
// Preferences (read from the real view SpringBoard actually sees).
// -----------------------------------------------------------------------------
static NSDictionary *gPrefs;

static NSDictionary *DictionaryFromPaths(NSArray<NSString *> *paths) {
    for (NSString *p in paths) {
        NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:p];
        if (d.count) return d;
    }
    return @{};
}

static void LoadPrefs(void) {
    // Keep a raw-file fallback cache for defaults/diagnostics. Individual
    // boolean reads use CFPreferencesCopyAppValue(key, domain), which is the
    // live cfprefsd path Preferences.app writes to.
    gPrefs = DictionaryFromPaths(@[
        @"/var/mobile/Library/Preferences/com.ratush.appabetical.plist",
    ]) ?: @{};
    if (![gPrefs isKindOfClass:[NSDictionary class]]) gPrefs = @{};
}

static BOOL PKey(NSString *key, BOOL def) {
    // Try cfprefsd first (live, cross-namespace), then the cached dict.
    id v = CFBridgingRelease(CFPreferencesCopyAppValue(
        (__bridge CFStringRef)key, (__bridge CFStringRef)kDomain));
    if (v == nil) v = gPrefs[key];
    if (v == nil) return def;
    return [v boolValue];
}
static BOOL PrefEnabled(void)      { return PKey(kKeyEnabled, YES); }
static BOOL PrefPlaceOff(void)     { return PKey(kKeyPlaceOffEnd, YES); }
static BOOL PrefPlaceBkmk(void)    { return PKey(kKeyPlaceBkmkEnd, NO); }
static BOOL PrefIgnoreEmoji(void)  { return PKey(kKeyIgnoreEmoji, YES); }
static BOOL PrefSortFolders(void)  { return PKey(kKeySortFolders, YES); }
static BOOL PrefSortInside(void)   { return PKey(kKeySortInside, YES); }
static BOOL PrefDock(void)         { return PKey(kKeyIncludeDock, NO); }
static BOOL PrefAutoSort(void)     { return PKey(kKeyAutoSort, YES); }
static BOOL PrefPreserveCC(void)   { return PKey(kKeyPreserveCC, YES); }

static void ABPostSortDone(void) {
    notify_post([kNotifSortDone UTF8String]);
}

// -----------------------------------------------------------------------------
// Emoji / symbol stripping for the "Ignore emoji" sort key.
//
// A glyph is ignorable only when it is a known emoji/presentation code point.
// We deliberately do NOT drop unknown glyphs: that previously stripped
// Cyrillic (0x0400-0x04FF) and broke А-Я sorting. Now everything is KEPT
// except a curated list of emoji blocks + variation/joiner selectors.
// -----------------------------------------------------------------------------
static BOOL ABIsIgnoredEmoji(unichar c, BOOL surrogate) {
    if (surrogate) return YES;          // any non-BMP code point (4-byte emoji)
    if (c < 0x80) {
        return (c < 0x20 && c != 0x09 && c != 0x0A && c != 0x0D); // drop C0 control
    }
    // Presentation / joiner selectors.
    if (c == 0xFE0F || c == 0xFE0E) return YES; // emoji / text presentation
    if (c == 0x200D || c == 0x200C) return YES; // ZWJ / ZWNJ
    if (c == 0x20E3) return YES;                // combining enclosing keycap
    // Tag code points (U+E0020-E007F, used in flag sequences) are > 0xFFFF, so
    // they arrive as surrogate pairs and are caught by the surrogate branch.
    // Emoji-rich BMP blocks (drop); regional indicators are surrogates (above).
    if (c >= 0x2600 && c <= 0x27BF) return YES; // misc symbols & dingbats
    if (c >= 0x2B00 && c <= 0x2BFF) return YES; // misc symbols & arrows
    if (c >= 0xFE50 && c <= 0xFE6F) return YES; // small form variants
    // Keep everything else (Latin, Cyrillic, Greek, CJK, punctuation, math,
    // non-pictographic geometric shapes, half/fullwidth forms, etc.).
    return NO;
}

// Returns a copy of `title` with emoji-like glyphs removed. Plain C buffer +
// one NSString creation (ARC-safe; the CFStringAppendCharacters path on a
// bridged NSMutableString over-retained the buffer and crashed under ARC).
static NSString *ABStripEmoji(NSString *title) {
    if (!title.length) return title;
    NSUInteger len = title.length;
    unichar *buf = (unichar *)malloc(len * sizeof(unichar));
    if (!buf) return title;
    NSUInteger outLen = 0;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [title characterAtIndex:i];
        unichar c2 = 0;
        BOOL surrogate = NO;
        if (CFStringIsSurrogateHighCharacter(c) && i + 1 < len) {
            c2 = [title characterAtIndex:i + 1];
            if (CFStringIsSurrogateLowCharacter(c2)) surrogate = YES;
        }
        if (ABIsIgnoredEmoji(c, surrogate)) {
            if (surrogate) i++;
            continue;
        }
        buf[outLen++] = c;
        if (surrogate) { buf[outLen++] = c2; i++; }
    }
    NSString *stripped;
    if (outLen == 0 || outLen == len) {
        stripped = [title copy];
    } else {
        stripped = [[NSString alloc] initWithCharacters:buf length:outLen];
    }
    free(buf);
    return stripped;
}

// -----------------------------------------------------------------------------
// Language bucket: 0 Latin, 1 Cyrillic, 2 Other (stable). Computed on the
// already-emoji-stripped sort key so an emoji-prefixed Latin name lands Latin.
// -----------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, ABBucket) {
    ABBucketLatin = 0,
    ABBucketCyrillic = 1,
    ABBucketOther = 2,
};

static ABBucket ABBucketForSortKey(NSString *key) {
    if (!key.length) return ABBucketOther;
    NSUInteger len = key.length;
    for (NSUInteger i = 0; i < len; i++) {
        unichar c = [key characterAtIndex:i];
        if ((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')) return ABBucketLatin;
        if (c >= 0x0400 && c <= 0x04FF) return ABBucketCyrillic;
    }
    return ABBucketOther;
}

// -----------------------------------------------------------------------------
// Item model.
//   typeTier ranks item KINDS on the desktop:
//     apps/webclips -> 0, folders -> 1, Shortcuts icons -> 2.
//   endRank controls who goes to the very end of the sort:
//     normal=0, bookmark=1, offloaded=2. Offloaded always beats bookmark when
//     both flags could apply (offloaded is the stronger signal).
//   sortKey is the title used for comparison, emoji-stripped when enabled.
//   bucket is precomputed from sortKey.
// -----------------------------------------------------------------------------
typedef NS_ENUM(NSInteger, ABItemType) {
    ABItemTypeApp,
    ABItemTypeFolder,
    ABItemTypeShortcut,
    ABItemTypeWidget,
    ABItemTypeOther,
};

@interface ABItem : NSObject
@property (nonatomic, assign) ABItemType type;
@property (nonatomic, assign) NSInteger typeTier;   // 0 app, 1 folder, 2 shortcut
@property (nonatomic, assign) NSInteger endRank;    // 0 normal, 1 bookmark, 2 offloaded
@property (nonatomic, copy)   NSString *title;      // display title (raw)
@property (nonatomic, copy)   NSString *sortKey;    // emoji-stripped when enabled
@property (nonatomic, assign) ABBucket bucket;
@property (nonatomic, copy)   NSString *bundleID;
@property (nonatomic, assign) BOOL widget;
@property (nonatomic, assign) BOOL offloaded;       // temp; folded into endRank
@property (nonatomic, assign) NSUInteger origIndex;
@property (nonatomic, strong) id original;
@end
@implementation ABItem
@end

// Returns YES if `bid` looks like a 32-hex-char UUID (web clip / shortcut id).
static BOOL ABIsHexUUID(NSString *bid) {
    if (bid.length != 32) return NO;
    for (NSUInteger i = 0; i < 32; i++) {
        unichar c = [bid characterAtIndex:i];
        BOOL hex = (c >= '0' && c <= '9') || (c >= 'A' && c <= 'F') || (c >= 'a' && c <= 'f');
        if (!hex) return NO;
    }
    return YES;
}

// -----------------------------------------------------------------------------
// Sorter: resolves app names / offloaded / bookmark state via LSApplicationProxy
// at runtime (no private headers needed). Per-run caches keyed by bundle id.
// -----------------------------------------------------------------------------
@interface ABSorter : NSObject
@property (nonatomic, strong) NSMutableDictionary *nameCache;
@property (nonatomic, strong) NSMutableDictionary *offloadedCache;
@property (nonatomic, strong) NSMutableDictionary *bookmarkCache;
@property (nonatomic, strong) NSMutableSet *webClipSet;
@end

@implementation ABSorter

- (instancetype)init {
    self = [super init];
    if (self) {
        _nameCache = [NSMutableDictionary dictionary];
        _offloadedCache = [NSMutableDictionary dictionary];
        _bookmarkCache = [NSMutableDictionary dictionary];
        _webClipSet = [NSMutableSet set];
        // Enumerate web clips once so we can classify hex-UUID ids cheaply.
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *entries = [fm contentsOfDirectoryAtPath:kWebClipsDir error:nil];
        for (NSString *e in entries) {
            if ([e hasSuffix:@".webclip"]) {
                NSString *bid = [e substringToIndex:e.length - @".webclip".length];
                [_webClipSet addObject:bid];
            }
        }
    }
    return self;
}

- (NSString *)displayNameForBundleID:(NSString *)bid {
    if (!bid) return @"";
    NSString *cached = self.nameCache[bid];
    if (cached) return cached;
    NSString *name = bid;
    @try {
        Class cls = NSClassFromString(@"LSApplicationProxy");
        if (cls) {
            id proxy = [cls performSelector:@selector(applicationProxyForIdentifier:) withObject:bid];
            if (proxy) {
                NSString *n = [proxy performSelector:@selector(localizedName)];
                if (n.length) name = n;
            }
        }
    } @catch (__unused id e) {}
    // Web-clip fallback: read its Info.plist Title.
    if (name.length == 0 || [name isEqualToString:bid]) {
        NSString *wc = [NSString stringWithFormat:@"%@/%@.webclip/Info.plist", kWebClipsDir, bid];
        NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:wc];
        if ([info[@"Title"] length]) name = info[@"Title"];
    }
    self.nameCache[bid] = name ?: @"";
    return name ?: @"";
}

// isInstalled returns a primitive BOOL. Calling it through performSelector:
// under ARC makes ARC treat the raw BOOL as an id and objc_retain address 0x1
// -> SIGSEGV. Use a typed objc_msgSend. Cross-check with executable presence.
- (BOOL)isOffloaded:(NSString *)bid {
    if (!bid) return NO;
    NSNumber *cached = self.offloadedCache[bid];
    if (cached) return cached.boolValue;
    BOOL off = NO;
    @try {
        Class cls = NSClassFromString(@"LSApplicationProxy");
        if (cls) {
            id proxy = [cls performSelector:@selector(applicationProxyForIdentifier:) withObject:bid];
            if (proxy) {
                if ([proxy respondsToSelector:@selector(isInstalled)]) {
                    BOOL (*sendIsInstalled)(id, SEL) = (BOOL (*)(id, SEL))objc_msgSend;
                    if (!sendIsInstalled(proxy, @selector(isInstalled))) off = YES;
                }
                if (!off) {
                    NSURL *bundleURL = nil;
                    @try { bundleURL = [proxy performSelector:@selector(bundleURL)]; } @catch (__unused id e) {}
                    NSString *execName = nil;
                    @try { execName = [proxy performSelector:@selector(bundleExecutable)]; } @catch (__unused id e) {}
                    if (bundleURL.path.length) {
                        NSString *execPath = execName.length
                            ? [bundleURL.path stringByAppendingPathComponent:execName]
                            : bundleURL.path;
                        if (![[NSFileManager defaultManager] fileExistsAtPath:execPath]) off = YES;
                    }
                }
            }
        }
    } @catch (__unused id e) {}
    self.offloadedCache[bid] = @(off);
    return off;
}

// A bookmark is a web clip: a 32-hex-UUID bundle id that has a .webclip
// directory (confirmed at init time). Home-screen Shortcut icons share the
// hex-UUID shape but have no .webclip dir, so they are NOT bookmarks; they get
// their own tier (after folders) instead.
- (BOOL)isBookmark:(NSString *)bid {
    if (!bid || !ABIsHexUUID(bid)) return NO;
    NSNumber *cached = self.bookmarkCache[bid];
    if (cached) return cached.boolValue;
    BOOL bkmk = [self.webClipSet containsObject:bid];
    self.bookmarkCache[bid] = @(bkmk);
    return bkmk;
}

// A home-screen Shortcut icon: hex-UUID id with NO .webclip directory.
- (BOOL)isShortcutIcon:(NSString *)bid {
    if (!bid || !ABIsHexUUID(bid)) return NO;
    return ![self.webClipSet containsObject:bid];
}

- (ABItem *)itemFromRaw:(id)raw {
    ABItem *it = [ABItem new];
    it.original = raw;
    it.origIndex = NSNotFound;
    it.typeTier = 0;
    it.endRank = 0;
    it.bucket = ABBucketOther;
    if ([raw isKindOfClass:[NSString class]]) {
        it.type = ABItemTypeApp;
        it.typeTier = 0;
        it.bundleID = raw;
        it.title = [self displayNameForBundleID:raw];
        it.offloaded = [self isOffloaded:raw];
        if ([self isShortcutIcon:raw]) {
            it.type = ABItemTypeShortcut;
            it.typeTier = 2;
        }
    } else if ([raw isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = raw;
        NSString *iconType = d[@"iconType"];
        NSString *listType = d[@"listType"];
        if ([iconType isEqualToString:@"custom"]) {
            it.type = ABItemTypeWidget; it.widget = YES;
        } else if ([iconType isEqualToString:@"app"] || [iconType isEqualToString:@"user"] ||
                   [iconType isEqualToString:@"system"]) {
            it.type = ABItemTypeApp;
            it.typeTier = 0;
            it.bundleID = d[@"bundleIdentifier"];
            it.title = [self displayNameForBundleID:it.bundleID];
            it.offloaded = [self isOffloaded:it.bundleID];
            if ([self isShortcutIcon:it.bundleID]) {
                it.type = ABItemTypeShortcut;
                it.typeTier = 2;
            }
        } else if ([listType isEqualToString:@"folder"]) {
            it.type = ABItemTypeFolder;
            it.typeTier = 1;
            it.title = d[@"displayName"] ?: @"";
        } else {
            it.type = ABItemTypeOther; it.widget = YES;
        }
    } else {
        it.type = ABItemTypeOther; it.widget = YES;
    }

    // Compute endRank: bookmark (1) vs offloaded (2) vs normal (0).
    // A web clip (bookmark) has no Mach-O executable, so the offloaded check
    // would otherwise mis-classify it. Bookmarks are checked FIRST so they get
    // their own end rank; only real apps with a missing executable count as
    // offloaded.
    if (it.type != ABItemTypeFolder && it.bundleID &&
        [self isBookmark:it.bundleID]) {
        it.endRank = 1;
    } else if (it.offloaded) {
        it.endRank = 2;
    } else {
        it.endRank = 0;
    }

    NSString *key = PrefIgnoreEmoji() ? ABStripEmoji(it.title) : (it.title ?: @"");
    it.sortKey = key;
    it.bucket = ABBucketForSortKey(key);
    return it;
}

// Comparison: offloaded last, then bookmarks last, then item-kind tier, then
// language bucket, then alpha. Within each "end" group the same
// Latin/Cyrillic/Other/alpha ordering applies so offloaded/bookmarks are still
// alphabetized among themselves.
- (NSComparisonResult)compareItem:(ABItem *)a to:(ABItem *)b {
    // 1. End rank: offloaded (2) > bookmark (1) > normal (0). Higher rank sorts
    //    later. Respect the toggles.
    NSInteger aEnd = a.endRank;
    NSInteger bEnd = b.endRank;
    if (!PrefPlaceOff()) { if (aEnd == 2) aEnd = 0; if (bEnd == 2) bEnd = 0; }
    if (!PrefPlaceBkmk()) { if (aEnd == 1) aEnd = 0; if (bEnd == 1) bEnd = 0; }
    if (aEnd != bEnd) return (aEnd < bEnd) ? NSOrderedAscending : NSOrderedDescending;

    // Same end group (or neither): apply tier + bucket + alpha.
    // 2. Item-kind tier: apps(0) < folders(1) < shortcuts(2).
    if (a.typeTier != b.typeTier) {
        return (a.typeTier < b.typeTier) ? NSOrderedAscending : NSOrderedDescending;
    }
    // 3. Language bucket.
    if (a.bucket != b.bucket) {
        return (a.bucket < b.bucket) ? NSOrderedAscending : NSOrderedDescending;
    }
    // 4. Other scripts: stable by original index.
    if (a.bucket == ABBucketOther) {
        return (a.origIndex < b.origIndex) ? NSOrderedAscending
             : (a.origIndex > b.origIndex) ? NSOrderedDescending : NSOrderedSame;
    }
    // 5. Latin / Cyrillic: case-insensitive, numeric-aware; stable tiebreak.
    NSComparisonResult r = [a.sortKey compare:b.sortKey options:NSCaseInsensitiveSearch | NSNumericSearch];
    if (r == NSOrderedSame) {
        return (a.origIndex < b.origIndex) ? NSOrderedAscending
             : (a.origIndex > b.origIndex) ? NSOrderedDescending : NSOrderedSame;
    }
    return r;
}

- (void)collectMovableFromPages:(NSArray *)pages
                    allowFolders:(BOOL)allowFolders
                       intoItems:(NSMutableArray<ABItem *> *)items
                       intoSlots:(NSMutableArray<NSDictionary *> *)slots {
    NSUInteger pos = 0;
    for (NSUInteger pageIndex = 0; pageIndex < pages.count; pageIndex++) {
        NSArray *page = [pages[pageIndex] isKindOfClass:[NSArray class]] ? pages[pageIndex] : @[];
        for (NSUInteger iconIndex = 0; iconIndex < page.count; iconIndex++) {
            id raw = page[iconIndex];
            ABItem *it = [self itemFromRaw:raw];
            if (it.widget) continue;
            if (it.type == ABItemTypeFolder && !allowFolders) continue;
            it.origIndex = pos++;
            [items addObject:it];
            [slots addObject:@{@"page": @(pageIndex), @"slot": @(iconIndex)}];
        }
    }
}

// Sort one page in place (Dock only).
- (NSArray *)sortedPage:(NSArray *)page allowFolders:(BOOL)allowFolders movedCount:(NSUInteger *)movedCount {
    NSMutableArray *result = [page mutableCopy];
    NSMutableArray<ABItem *> *sortable = [NSMutableArray array];
    NSMutableArray<NSNumber *> *slots = [NSMutableArray array];
    NSUInteger pos = 0;
    for (NSUInteger i = 0; i < page.count; i++) {
        id raw = page[i];
        ABItem *it = [self itemFromRaw:raw];
        if (it.widget) continue;
        if (it.type == ABItemTypeFolder && !allowFolders) continue;
        it.origIndex = pos; pos++;
        [sortable addObject:it];
        [slots addObject:@(i)];
    }
    [sortable sortUsingComparator:^NSComparisonResult(ABItem *a, ABItem *b) {
        return [self compareItem:a to:b];
    }];
    for (NSUInteger k = 0; k < slots.count; k++) {
        result[[slots[k] unsignedIntegerValue]] = [sortable[k] original];
    }
    if (movedCount) *movedCount += sortable.count;
    return [result copy];
}

// Sort all movable slots across all pages of a container, then refill in order.
- (NSArray *)sortedPages:(NSArray *)pages
            allowFolders:(BOOL)allowFolders
                 context:(NSString *)context
              movedCount:(NSUInteger *)movedCount {
    NSMutableArray *resultPages = [NSMutableArray arrayWithCapacity:pages.count];
    NSMutableArray<ABItem *> *sortable = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *slots = [NSMutableArray array];

    for (NSUInteger pageIndex = 0; pageIndex < pages.count; pageIndex++) {
        NSArray *page = [pages[pageIndex] isKindOfClass:[NSArray class]] ? pages[pageIndex] : @[];
        [resultPages addObject:[page mutableCopy]];
    }
    [self collectMovableFromPages:pages
                     allowFolders:allowFolders
                        intoItems:sortable
                        intoSlots:slots];

    NSUInteger offloadedCount = 0, bookmarkCount = 0, folderCount = 0, shortcutCount = 0;
    for (ABItem *it in sortable) {
        if (it.endRank == 2) offloadedCount++;
        else if (it.endRank == 1) bookmarkCount++;
        if (it.type == ABItemTypeFolder) folderCount++;
        if (it.type == ABItemTypeShortcut) shortcutCount++;
    }

    [sortable sortUsingComparator:^NSComparisonResult(ABItem *a, ABItem *b) {
        return [self compareItem:a to:b];
    }];

    for (NSUInteger k = 0; k < slots.count; k++) {
        NSDictionary *slot = slots[k];
        NSUInteger pageIndex = [slot[@"page"] unsignedIntegerValue];
        NSUInteger iconIndex = [slot[@"slot"] unsignedIntegerValue];
        NSMutableArray *page = resultPages[pageIndex];
        page[iconIndex] = [sortable[k] original];
    }

    if (movedCount) *movedCount += sortable.count;
    ABLog(@"SORT %@ slots=%lu pages=%lu off=%lu bkmk=%lu folders=%lu shortcuts=%lu firsts=%@",
          context ?: @"?", (unsigned long)sortable.count,
          (unsigned long)pages.count, (unsigned long)offloadedCount,
          (unsigned long)bookmarkCount, (unsigned long)folderCount,
          (unsigned long)shortcutCount, [self debugHead:sortable limit:4]);

    return [resultPages copy];
}

// Folder pages are fixed 3x3 pages on this device. Sorting into the original
// sparse slots preserves holes like [9, 8, 8, 4], so folder contents get a
// dense refill instead: [9, 9, 9, 2].
- (NSArray *)sortedDenseFolderPages:(NSArray *)pages
                            context:(NSString *)context
                         movedCount:(NSUInteger *)movedCount {
    static const NSUInteger kFolderPageCapacity = 9;
    NSMutableArray<ABItem *> *sortable = [NSMutableArray array];
    BOOL hasLockedItem = NO;

    for (NSArray *page in pages) {
        if (![page isKindOfClass:[NSArray class]]) continue;
        for (id raw in page) {
            ABItem *it = [self itemFromRaw:raw];
            if (it.widget || it.type == ABItemTypeFolder) {
                hasLockedItem = YES;
                break;
            }
            it.origIndex = sortable.count;
            [sortable addObject:it];
        }
        if (hasLockedItem) break;
    }

    if (hasLockedItem) {
        ABLog(@"SORT %@ dense skipped: locked item found", context ?: @"folder");
        return [self sortedPages:pages allowFolders:NO context:context movedCount:movedCount];
    }

    NSUInteger offloadedCount = 0, bookmarkCount = 0, shortcutCount = 0;
    for (ABItem *it in sortable) {
        if (it.endRank == 2) offloadedCount++;
        else if (it.endRank == 1) bookmarkCount++;
        if (it.type == ABItemTypeShortcut) shortcutCount++;
    }

    [sortable sortUsingComparator:^NSComparisonResult(ABItem *a, ABItem *b) {
        return [self compareItem:a to:b];
    }];

    NSUInteger pageCount = (sortable.count + kFolderPageCapacity - 1) / kFolderPageCapacity;
    if (pageCount == 0) pageCount = 1;
    NSMutableArray *resultPages = [NSMutableArray arrayWithCapacity:pageCount];
    for (NSUInteger pageIndex = 0; pageIndex < pageCount; pageIndex++) {
        NSMutableArray *page = [NSMutableArray arrayWithCapacity:kFolderPageCapacity];
        NSUInteger start = pageIndex * kFolderPageCapacity;
        NSUInteger end = MIN(start + kFolderPageCapacity, sortable.count);
        for (NSUInteger i = start; i < end; i++) {
            [page addObject:[sortable[i] original]];
        }
        [resultPages addObject:page];
    }

    if (movedCount) *movedCount += sortable.count;
    ABLog(@"SORT %@ dense slots=%lu pages=%lu->%lu off=%lu bkmk=%lu shortcuts=%lu firsts=%@",
          context ?: @"folder", (unsigned long)sortable.count,
          (unsigned long)pages.count, (unsigned long)resultPages.count,
          (unsigned long)offloadedCount, (unsigned long)bookmarkCount,
          (unsigned long)shortcutCount, [self debugHead:sortable limit:4]);
    return [resultPages copy];
}

- (NSArray *)folderListIDs:(NSArray *)oldIDs count:(NSUInteger)count {
    NSMutableArray *ids = [NSMutableArray array];
    if ([oldIDs isKindOfClass:[NSArray class]]) [ids addObjectsFromArray:oldIDs];
    while (ids.count < count) {
        [ids addObject:[[NSUUID UUID] UUIDString]];
    }
    if (ids.count > count) {
        [ids removeObjectsInRange:NSMakeRange(count, ids.count - count)];
    }
    return [ids copy];
}

- (NSArray<NSString *> *)debugHead:(NSArray<ABItem *> *)items limit:(NSUInteger)limit {
    NSMutableArray *titles = [NSMutableArray array];
    NSUInteger n = MIN(limit, items.count);
    for (NSUInteger i = 0; i < n; i++) {
        ABItem *it = items[i];
        NSString *prefix = (it.type == ABItemTypeFolder) ? @"F:" : (it.type == ABItemTypeShortcut) ? @"S:" : @"";
        [titles addObject:[NSString stringWithFormat:@"%@%@|b%ld|e%ld|t%ld",
                           prefix, it.sortKey ?: @"",
                           (long)it.bucket, (long)it.endRank, (long)it.typeTier]];
    }
    return titles;
}

- (NSArray *)processFoldersInPages:(NSArray *)pages movedCount:(NSUInteger *)movedCount {
    if (!PrefSortInside()) return pages;
    NSMutableArray *outPages = [NSMutableArray arrayWithCapacity:pages.count];
    for (NSArray *page in pages) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:page.count];
        for (id raw in page) {
            if ([raw isKindOfClass:[NSDictionary class]] && [(NSString *)raw[@"listType"] isEqualToString:@"folder"]) {
                NSDictionary *d = raw;
                NSArray *fpages = [d[@"iconLists"] isKindOfClass:[NSArray class]] ? d[@"iconLists"] : @[];
                NSString *name = d[@"displayName"] ?: @"folder";
                NSArray *newf = [self sortedDenseFolderPages:fpages
                                                     context:[NSString stringWithFormat:@"folder:%@", name]
                                                  movedCount:movedCount];
                newf = [self processFoldersInPages:newf movedCount:movedCount];
                NSMutableDictionary *fd = [d mutableCopy];
                fd[@"iconLists"] = newf;
                fd[@"listUniqueIdentifiers"] = [self folderListIDs:d[@"listUniqueIdentifiers"] count:newf.count];
                [out addObject:fd];
            } else {
                [out addObject:raw];
            }
        }
        [outPages addObject:out];
    }
    return [outPages copy];
}

- (NSArray *)sortedContainerPages:(NSArray *)pages
                     allowFolders:(BOOL)allowFolders
                          context:(NSString *)context
                       movedCount:(NSUInteger *)movedCount {
    NSArray *sorted = [self sortedPages:pages
                           allowFolders:allowFolders
                                context:context
                             movedCount:movedCount];
    return [self processFoldersInPages:sorted movedCount:movedCount];
}

- (BOOL)sortIntoState:(NSMutableDictionary *)state movedCount:(NSUInteger *)movedCount {
    NSArray *iconLists = [state[@"iconLists"] isKindOfClass:[NSArray class]]
                                  ? state[@"iconLists"]
                                  : @[];
    state[@"iconLists"] = [self sortedContainerPages:iconLists
                                        allowFolders:PrefSortFolders()
                                             context:@"desktop"
                                          movedCount:movedCount];

    if (PrefDock()) {
        id dock = state[@"buttonBar"];
        if ([dock isKindOfClass:[NSArray class]]) {
            state[@"buttonBar"] = [self sortedPage:dock allowFolders:NO movedCount:movedCount];
        }
    }
    return YES;
}

// -----------------------------------------------------------------------------
// Validation: the sorted state must contain exactly the same items as the
// original (no item lost, added or mangled).
// -----------------------------------------------------------------------------
- (NSString *)signatureForRaw:(id)raw {
    if ([raw isKindOfClass:[NSString class]]) {
        return [NSString stringWithFormat:@"a:%@", raw];
    }
    if (![raw isKindOfClass:[NSDictionary class]]) return [NSString stringWithFormat:@"o:%lu", (unsigned long)[raw hash]];
    NSDictionary *d = raw;
    if ([d[@"listType"] isEqualToString:@"folder"]) {
        return [NSString stringWithFormat:@"f:%@", d[@"uniqueIdentifier"] ?: d[@"displayName"] ?: @""];
    }
    if ([d[@"iconType"] isEqualToString:@"app"] || [d[@"iconType"] isEqualToString:@"user"] ||
        [d[@"iconType"] isEqualToString:@"system"]) {
        return [NSString stringWithFormat:@"a:%@", d[@"bundleIdentifier"] ?: @""];
    }
    return [NSString stringWithFormat:@"w:%@", d[@"uniqueIdentifier"] ?: d[@"displayIdentifier"] ?: [NSString stringWithFormat:@"%lu", (unsigned long)[d hash]]];
}

- (void)collectFromPage:(NSArray *)page into:(NSMutableDictionary *)counts {
    if (![page isKindOfClass:[NSArray class]]) return;
    for (id raw in page) {
        if ([raw isKindOfClass:[NSDictionary class]] && [(NSString *)raw[@"listType"] isEqualToString:@"folder"]) {
            NSString *sig = [self signatureForRaw:raw];
            counts[sig] = @([counts[sig] integerValue] + 1);
            NSArray *fpages = raw[@"iconLists"];
            if ([fpages isKindOfClass:[NSArray class]]) {
                for (id fp in fpages) [self collectFromPage:fp into:counts];
            }
        } else {
            NSString *sig = [self signatureForRaw:raw];
            counts[sig] = @([counts[sig] integerValue] + 1);
        }
    }
}

- (void)collectFromState:(NSDictionary *)state into:(NSMutableDictionary *)counts {
    id dock = state[@"buttonBar"];
    if ([dock isKindOfClass:[NSArray class]]) [self collectFromPage:dock into:counts];
    id il = state[@"iconLists"];
    if ([il isKindOfClass:[NSArray class]]) {
        for (id p in il) [self collectFromPage:p into:counts];
    }
}

// -----------------------------------------------------------------------------
// Write helper: validate + atomic write + respring. Shared by sort & preset
// restore. Returns YES if a respring was triggered.
// -----------------------------------------------------------------------------
- (BOOL)applyState:(NSMutableDictionary *)state originalState:(NSDictionary *)old movedCount:(NSUInteger)movedCount {
    NSMutableDictionary *oldCounts = [NSMutableDictionary dictionary];
    NSMutableDictionary *newCounts = [NSMutableDictionary dictionary];
    [self collectFromState:old into:oldCounts];
    [self collectFromState:state into:newCounts];
    if (![oldCounts isEqualToDictionary:newCounts]) {
        ABLog(@"ABORT: validation failed, item counts differ");
        ABPostSortDone();
        return NO;
    }
    if (!state[@"iconLists"] || !state[@"buttonBar"] || !state[@"listUniqueIdentifiers"]) {
        ABLog(@"ABORT: top-level keys missing after sort");
        ABPostSortDone();
        return NO;
    }

    @try { [[NSFileManager defaultManager] copyItemAtPath:kIconStatePath toPath:kIconStateBkp error:nil]; } @catch (__unused id e) {}

    NSError *plErr = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:state
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&plErr];
    if (!data) { ABLog(@"ERROR serializing plist: %@", plErr); ABPostSortDone(); return NO; }
    if (![data writeToFile:kIconStateNew atomically:YES]) {
        ABLog(@"ERROR: cannot write %@", kIconStateNew);
        ABPostSortDone();
        return NO;
    }
    NSError *err = nil;
    if (![[NSFileManager defaultManager] replaceItemAtURL:[NSURL fileURLWithPath:kIconStatePath]
                                            withItemAtURL:[NSURL fileURLWithPath:kIconStateNew]
                                           backupItemName:nil
                                                  options:0
                                        resultingItemURL:NULL
                                                   error:&err]) {
        ABLog(@"ERROR replacing IconState: %@", err);
        ABPostSortDone();
        return NO;
    }
    ABLog(@"applied OK; scanned %lu movable slots; respringing", (unsigned long)movedCount);
    ABPostSortDone();
    Respring();
    return YES;
}

// -----------------------------------------------------------------------------
// Respring (from inside SpringBoard).
// -----------------------------------------------------------------------------
static void Respring(void) {
    @try {
        Class cls = NSClassFromString(@"FBSystemService");
        if (cls) {
            id svc = [cls performSelector:@selector(sharedService)];
            if (svc && [svc respondsToSelector:@selector(exitAndRelaunch:)]) {
                ((void (*)(id, SEL, id))objc_msgSend)(svc, @selector(exitAndRelaunch:), nil);
                return;
            }
        }
    } @catch (__unused id e) {}
    ABLog(@"Respring: FBSystemService path unavailable; exiting SpringBoard fallback");
    _exit(0);
}

// -----------------------------------------------------------------------------
// Main entry: read -> sort -> validate -> write atomically -> respring.
// -----------------------------------------------------------------------------
- (void)performSort {
    LoadPrefs();
    ABLog(@"performSort toggles: enabled=%d placeOff=%d placeBkmk=%d ignoreEmoji=%d sortFolders=%d sortInside=%d dock=%d auto=%d",
          PrefEnabled(), PrefPlaceOff(), PrefPlaceBkmk(), PrefIgnoreEmoji(),
          PrefSortFolders(), PrefSortInside(), PrefDock(), PrefAutoSort());
    if (!PrefEnabled()) { ABLog(@"sort skipped: disabled"); ABPostSortDone(); return; }

    NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:kIconStatePath];
    if (!old) { ABLog(@"ERROR: cannot read %@", kIconStatePath); ABPostSortDone(); return; }

    NSMutableDictionary *state = [old mutableCopy];
    NSArray *origIL = old[@"iconLists"];
    NSArray *origDock = old[@"buttonBar"];

    NSUInteger movedCount = 0;
    @try {
        [self sortIntoState:state movedCount:&movedCount];
    } @catch (NSException *ex) {
        ABLog(@"ABORT: sort threw exception: %@ -- %@", ex.name, ex.reason);
        ABPostSortDone();
        return;
    }

    NSArray *newIL = state[@"iconLists"];
    NSArray *newDock = state[@"buttonBar"];

    BOOL changed = NO;
    if (![origIL isEqual:newIL]) changed = YES;
    if (PrefDock() && ![origDock isEqual:newDock]) changed = YES;
    if (!changed) { ABLog(@"nothing to sort; scanned %lu movable slots; skipping respring", (unsigned long)movedCount); ABPostSortDone(); return; }

    [self applyState:state originalState:old movedCount:movedCount];
}

// -----------------------------------------------------------------------------
// Layout presets (inspired by OwnGoalStudio/IconRestore).
// The presets file is a dict keyed by name. Legacy (v1) presets are a bare
// IconState dict copy; v2 presets are an envelope:
//   {
//     "@appab_format": 2,
//     "iconState":  <IconState dict>,
//     "ccSupport":  <dict>?,   // present only if Preserve CC was ON at save
//     "ccConfig":   <dict>?,   // ditto
//   }
// Save/apply/delete are requested from the prefs bundle via Darwin
// notifications carrying the preset name in a real-side sentinel file.
// -----------------------------------------------------------------------------

// Returns YES if `entry` is a v2 envelope dict.
static BOOL ABIsEnvelope(NSDictionary *entry) {
    if (![entry isKindOfClass:[NSDictionary class]]) return NO;
    id fmt = entry[@"@appab_format"];
    if (![fmt isKindOfClass:[NSNumber class]]) return NO;
    return [fmt integerValue] >= 2;
}

// Pull the IconState dict out of either a v2 envelope or a legacy v1 dict.
static NSDictionary *ABIconStateFromEntry(NSDictionary *entry) {
    if (ABIsEnvelope(entry)) {
        NSDictionary *is = entry[@"iconState"];
        return [is isKindOfClass:[NSDictionary class]] ? is : nil;
    }
    return [entry isKindOfClass:[NSDictionary class]] ? entry : nil;
}

- (NSMutableDictionary *)loadPresets {
    NSMutableDictionary *p = [NSMutableDictionary dictionaryWithContentsOfFile:kPresetsPath];
    return p ? [p mutableCopy] : [NSMutableDictionary dictionary];
}

// Embed the current CC layout into the envelope if Preserve CC is ON and the
// CC plists are readable. Returns YES if CC state was embedded.
- (BOOL)embedCCLayoutIntoEnvelope:(NSMutableDictionary *)envelope {
    if (!PrefPreserveCC()) return NO;
    NSString *ccsPath = ABCCSupportPath();
    NSString *cccPath = ABCCConfigPath();
    NSDictionary *ccs = ccsPath.length ? [NSDictionary dictionaryWithContentsOfFile:ccsPath] : nil;
    NSDictionary *ccc = cccPath.length ? [NSDictionary dictionaryWithContentsOfFile:cccPath] : nil;
    BOOL any = NO;
    if (ccs.count) { envelope[@"ccSupport"] = ccs; any = YES; }
    if (ccc.count) { envelope[@"ccConfig"]  = ccc; any = YES; }
    if (!any) ABLog(@"CC embed: nothing readable (ccs=%@ ccc=%@)", ccsPath, cccPath);
    return any;
}

// Write the CC layout from a v2 envelope back to disk, atomically, into the
// live (jbroot-view) CC files. Returns YES if any CC file was rewritten. Skips
// silently when the envelope has no CC data or when Preserve CC is OFF.
- (BOOL)writeCCLayoutFromEnvelope:(NSDictionary *)envelope {
    if (!PrefPreserveCC()) return NO;
    NSDictionary *ccs = [envelope[@"ccSupport"] isKindOfClass:[NSDictionary class]] ? envelope[@"ccSupport"] : nil;
    NSDictionary *ccc = [envelope[@"ccConfig"]  isKindOfClass:[NSDictionary class]] ? envelope[@"ccConfig"]  : nil;
    if (!ccs.count && !ccc.count) return NO;

    NSString *ccsPath = ABCCSupportPath();
    NSString *cccPath = ABCCConfigPath();
    if (!ccsPath.length && ccs.count) { ABLog(@"CC write: no jbroot, cannot restore ccSupport"); return NO; }
    if (!cccPath.length && ccc.count) { ABLog(@"CC write: no jbroot, cannot restore ccConfig");  return NO; }

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL wrote = NO;

    // Atomic write: serialize plist, write to <path>.appaccnew, replace.
    NSArray *pairs = @[
        @[ccsPath, ccs],
        @[cccPath, ccc],
    ];
    for (NSArray *pair in pairs) {
        NSString *path = pair[0];
        NSDictionary *data = pair[1];
        if (![data isKindOfClass:[NSDictionary class]] || !data.count || !path.length) continue;
        NSError *plErr = nil;
        NSData *blob = [NSPropertyListSerialization dataWithPropertyList:data
                                                                  format:NSPropertyListBinaryFormat_v1_0
                                                                 options:0
                                                                   error:&plErr];
        if (!blob) { ABLog(@"CC write: serialize failed for %@: %@", path, plErr); continue; }
        NSString *tmp = [path stringByAppendingString:@".appaccnew"];
        if (![blob writeToFile:tmp atomically:YES]) {
            ABLog(@"CC write: cannot write %@", tmp);
            continue;
        }
        NSError *err = nil;
        if (![fm replaceItemAtURL:[NSURL fileURLWithPath:path]
                    withItemAtURL:[NSURL fileURLWithPath:tmp]
                   backupItemName:nil
                          options:0
                    resultingItemURL:NULL
                             error:&err]) {
            ABLog(@"CC write: replace failed for %@: %@", path, err);
            continue;
        }
        wrote = YES;
    }
    ABLog(@"CC write %@ (ccSupport=%lu ccConfig=%lu)", wrote ? @"OK" : @"SKIP",
          (unsigned long)(ccs.count), (unsigned long)(ccc.count));
    return wrote;
}

- (BOOL)savePreset:(NSString *)name {
    if (!name.length) { ABLog(@"preset save: empty name"); return NO; }
    NSDictionary *cur = [NSDictionary dictionaryWithContentsOfFile:kIconStatePath];
    if (!cur) { ABLog(@"preset save: cannot read IconState"); return NO; }
    NSMutableDictionary *envelope = [NSMutableDictionary dictionary];
    envelope[@"@appab_format"] = @2;
    envelope[@"iconState"] = cur;
    BOOL ccEmbedded = [self embedCCLayoutIntoEnvelope:envelope];
    NSMutableDictionary *presets = [self loadPresets];
    presets[name] = envelope;
    BOOL ok = [presets writeToFile:kPresetsPath atomically:YES];
    ABLog(@"preset save '%@' -> %@ (%d presets total, cc=%d)", name, ok ? @"OK" : @"FAIL",
          (int)presets.count, ccEmbedded);
    return ok;
}

- (BOOL)applyPreset:(NSString *)name {
    // Every early-out posts sortDone so the prefs-side "Restoring…" alert is
    // dismissed promptly instead of hanging until its timeout. The success
    // path posts sortDone inside applyState just before the respring.
    if (!name.length) { ABLog(@"preset apply: empty name"); ABPostSortDone(); return NO; }
    NSMutableDictionary *presets = [self loadPresets];
    NSDictionary *entry = presets[name];
    if (!entry) { ABLog(@"preset apply: '%@' not found", name); ABPostSortDone(); return NO; }
    NSDictionary *saved = ABIconStateFromEntry(entry);
    if (!saved) { ABLog(@"preset apply: '%@' has no IconState", name); ABPostSortDone(); return NO; }
    NSDictionary *old = [NSDictionary dictionaryWithContentsOfFile:kIconStatePath];
    if (!old) { ABLog(@"preset apply: cannot read current IconState"); ABPostSortDone(); return NO; }
    // Validate: the preset and current state must have the same item multiset
    // so we never drop apps the user added after saving.
    NSMutableDictionary *oldCounts = [NSMutableDictionary dictionary];
    NSMutableDictionary *savedCounts = [NSMutableDictionary dictionary];
    [self collectFromState:old into:oldCounts];
    [self collectFromState:saved into:savedCounts];
    if (![oldCounts isEqualToDictionary:savedCounts]) {
        ABLog(@"preset apply ABORT: '%@' item multiset differs from current (apps added/removed since save)", name);
        ABPostSortDone();
        return NO;
    }

    // If Preserve CC is ON and the preset carries CC layout, restore it BEFORE
    // the respring triggered by applyState. ControlCenterUIKit reloads its
    // layout from these files on next launch, which the respring guarantees.
    BOOL ccApplied = NO;
    if (ABIsEnvelope(entry)) {
        ccApplied = [self writeCCLayoutFromEnvelope:entry];
    }

    NSMutableDictionary *state = [saved mutableCopy];
    ABLog(@"preset apply '%@' -> restoring IconState (cc=%d)", name, ccApplied);
    return [self applyState:state originalState:old movedCount:0];
}

- (BOOL)deletePreset:(NSString *)name {
    if (!name.length) return NO;
    NSMutableDictionary *presets = [self loadPresets];
    if (!presets[name]) return NO;
    [presets removeObjectForKey:name];
    BOOL ok = [presets writeToFile:kPresetsPath atomically:YES];
    ABLog(@"preset delete '%@' -> %@ (%d presets remain)", name, ok ? @"OK" : @"FAIL", (int)presets.count);
    return ok;
}

// Returns the current preset names for the prefs bundle to list.
- (NSArray *)presetNames {
    NSMutableDictionary *presets = [self loadPresets];
    return [presets.allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

@end

// -----------------------------------------------------------------------------
// Constructor: register Darwin-notification triggers.
// -----------------------------------------------------------------------------
static int sTokenSort = 0;
static int sTokenReload = 0;
static int sTokenPresetSave = 0;
static int sTokenPresetApply = 0;
static int sTokenPresetDelete = 0;

static NSString *PresetNameFromPrefs(void) {
    // The prefs bundle writes the requested preset name to a real-side
    // sentinel file before posting the Darwin notification. cfprefsd-backed
    // prefs live in the jbroot namespace and are NOT visible to SpringBoard
    // (real process), so we use a plain file on the real view instead.
    NSString *sentinel = @"/var/mobile/Library/SpringBoard/.appab_preset_name";
    NSError *err = nil;
    NSString *s = [NSString stringWithContentsOfFile:sentinel
                                            encoding:NSUTF8StringEncoding
                                               error:&err];
    if (s.length) {
        s = [s stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        // Best-effort clear after reading so stale names do not replay.
        @try { [@"" writeToFile:sentinel atomically:YES encoding:NSUTF8StringEncoding error:nil]; } @catch (__unused id e) {}
        return s;
    }
    return @"";
}

%ctor {
    @autoreleasepool {
        ABLog(@"Appabetical ctor step1: entered pid=%d bid=%@", getpid(),
              NSBundle.mainBundle.bundleIdentifier ?: @"?");

        LoadPrefs();
        ABLog(@"Appabetical ctor step2: prefs loaded enabled=%d placeOff=%d placeBkmk=%d ignoreEmoji=%d sortFolders=%d sortInside=%d dock=%d auto=%d",
              PrefEnabled(), PrefPlaceOff(), PrefPlaceBkmk(), PrefIgnoreEmoji(),
              PrefSortFolders(), PrefSortInside(), PrefDock(), PrefAutoSort());
        // Pre-resolve jbroot (also logs it) so CC save/restore paths are ready.

        notify_register_dispatch([kNotifSortNow UTF8String], &sTokenSort, dispatch_get_main_queue(), ^(int token) {
            ABLog(@"received sortnow");
            @autoreleasepool { [[[ABSorter alloc] init] performSort]; }
        });

        notify_register_dispatch([kNotifReload UTF8String], &sTokenReload, dispatch_get_main_queue(), ^(int token) {
            LoadPrefs();
            ABLog(@"reloaded prefs: enabled=%d placeOff=%d placeBkmk=%d ignoreEmoji=%d",
                  PrefEnabled(), PrefPlaceOff(), PrefPlaceBkmk(), PrefIgnoreEmoji());
        });

        notify_register_dispatch([kNotifPresetSave UTF8String], &sTokenPresetSave, dispatch_get_main_queue(), ^(int token) {
            NSString *name = PresetNameFromPrefs();
            ABLog(@"received preset.save name=%@", name);
            @autoreleasepool { [[[ABSorter alloc] init] savePreset:name]; }
        });

        notify_register_dispatch([kNotifPresetApply UTF8String], &sTokenPresetApply, dispatch_get_main_queue(), ^(int token) {
            NSString *name = PresetNameFromPrefs();
            ABLog(@"received preset.apply name=%@", name);
            @autoreleasepool { [[[ABSorter alloc] init] applyPreset:name]; }
        });

        notify_register_dispatch([kNotifPresetDelete UTF8String], &sTokenPresetDelete, dispatch_get_main_queue(), ^(int token) {
            NSString *name = PresetNameFromPrefs();
            ABLog(@"received preset.delete name=%@", name);
            @autoreleasepool { [[[ABSorter alloc] init] deletePreset:name]; }
        });

        if (PrefEnabled() && PrefAutoSort()) {
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                ABLog(@"autosort trigger");
                @autoreleasepool { [[[ABSorter alloc] init] performSort]; }
            });
            ABLog(@"Appabetical ctor step3: registered, autosort armed");
        } else {
            ABLog(@"Appabetical ctor step3: registered, autosort not armed");
        }
    }
}
