#import <UIKit/UIKit.h>
#import <objc/runtime.h>

static NSString *const IGGFLogPath = @"/var/mobile/Library/Preferences/com.ratush.iggridfeed.log";

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

static NSString *IGGFClassChain(id obj, NSUInteger limit) {
    NSMutableArray *parts = [NSMutableArray array];
    id cur = obj;
    NSUInteger n = 0;
    while (cur && n < limit) {
        [parts addObject:NSStringFromClass([cur class]) ?: @"?"];
        cur = [cur respondsToSelector:@selector(superview)] ? [cur superview] : nil;
        n++;
    }
    return [parts componentsJoinedByString:@" < "];
}

static BOOL IGGFStringLooksHomeFeed(NSString *s) {
    NSString *lower = s.lowercaseString ?: @"";
    return ([lower containsString:@"feed"] ||
            [lower containsString:@"home"] ||
            [lower containsString:@"timeline"]) &&
           ![lower containsString:@"profile"];
}

static BOOL IGGFStringLooksProfile(NSString *s) {
    NSString *lower = s.lowercaseString ?: @"";
    return [lower containsString:@"profile"] || [lower containsString:@"usergrid"];
}

static BOOL IGGFCollectionLooksHomeFeed(UICollectionView *cv) {
    if (![cv isKindOfClass:UICollectionView.class]) return NO;

    NSString *chain = IGGFClassChain(cv, 12);
    if (IGGFStringLooksProfile(chain)) return NO;
    if (IGGFStringLooksHomeFeed(chain)) return YES;

    UIResponder *r = cv;
    for (NSUInteger i = 0; r && i < 16; i++) {
        NSString *cls = NSStringFromClass([r class]) ?: @"";
        if (IGGFStringLooksProfile(cls)) return NO;
        if (IGGFStringLooksHomeFeed(cls)) return YES;
        r = [r nextResponder];
    }

    return NO;
}

static CGSize IGGFGridItemSize(UICollectionView *cv, CGSize original) {
    CGFloat width = cv.bounds.size.width;
    if (width < 120.0) return original;

    UIEdgeInsets inset = cv.adjustedContentInset;
    CGFloat usable = width - inset.left - inset.right;
    if (usable < 120.0) usable = width;

    CGFloat spacing = 1.0;
    CGFloat side = floor((usable - (spacing * 2.0)) / 3.0);
    if (side < 40.0) return original;
    return CGSizeMake(side, side);
}

static void IGGFInvalidate(UICollectionView *cv) {
    UICollectionViewLayout *layout = cv.collectionViewLayout;
    if ([layout respondsToSelector:@selector(invalidateLayout)]) {
        [layout invalidateLayout];
    }
}

%group InstagramGridFeedHooks

%hook UICollectionView

- (void)didMoveToWindow {
    %orig;
    if (self.window && IGGFCollectionLooksHomeFeed(self)) {
        IGGFLog(@"home-cv didMove %@ frame=%@ layout=%@ chain=%@",
                self,
                NSStringFromCGRect(self.frame),
                NSStringFromClass([self.collectionViewLayout class]),
                IGGFClassChain(self, 10));
        IGGFInvalidate(self);
    }
}

- (void)layoutSubviews {
    %orig;
    if (self.window && IGGFCollectionLooksHomeFeed(self)) {
        IGGFInvalidate(self);
    }
}

%end

%hook UICollectionViewFlowLayout

- (CGSize)itemSize {
    CGSize original = %orig;
    UICollectionView *cv = self.collectionView;
    if (cv && IGGFCollectionLooksHomeFeed(cv)) {
        CGSize grid = IGGFGridItemSize(cv, original);
        if (!CGSizeEqualToSize(original, grid)) {
            IGGFLog(@"flow itemSize %@ -> %@ layout=%@ chain=%@",
                    NSStringFromCGSize(original),
                    NSStringFromCGSize(grid),
                    NSStringFromClass([self class]),
                    IGGFClassChain(cv, 10));
        }
        return grid;
    }
    return original;
}

- (CGFloat)minimumInteritemSpacing {
    UICollectionView *cv = self.collectionView;
    if (cv && IGGFCollectionLooksHomeFeed(cv)) return 1.0;
    return %orig;
}

- (CGFloat)minimumLineSpacing {
    UICollectionView *cv = self.collectionView;
    if (cv && IGGFCollectionLooksHomeFeed(cv)) return 1.0;
    return %orig;
}

%end

%end

%ctor {
    @autoreleasepool {
        if (!IGGFIsInstagram()) return;
        IGGFLog(@"ctor bundle=%@ exe=%@", NSBundle.mainBundle.bundleIdentifier, NSProcessInfo.processInfo.arguments.firstObject.lastPathComponent);
        %init(InstagramGridFeedHooks);
    }
}
