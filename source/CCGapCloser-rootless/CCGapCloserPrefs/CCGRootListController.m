#import "CCGRootListController.h"
#import <Preferences/PSSpecifier.h>
#import <Preferences/PSTableCell.h>
#import <CoreFoundation/CFPreferences.h>
#import <objc/runtime.h>
#import <notify.h>

static NSString *const kDomain = @"com.ratush.ccgapcloser";
static NSString *const kReloadNotification = @"com.ratush.ccgapcloser.reload";
static NSString *const kApplyNotification = @"com.ratush.ccgapcloser.apply";
static NSString *const kRespringNotification = @"com.ratush.ccgapcloser.respring";

// Associated-object key for linking a PSSpecifier to its slider value label.
static char kCCGSpecifierKey;
static NSInteger const kCCGValueEditorButtonTag = 74031;

@implementation CCGRootListController

- (NSString *)title {
    return @"CCGapCloser";
}

- (PSSpecifier *)switchWithKey:(NSString *)key title:(NSString *)title defaultValue:(BOOL)defaultValue {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSwitchCell
                                                              edit:nil];
    [specifier setProperty:kDomain forKey:@"defaults"];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(defaultValue) forKey:@"default"];
    return specifier;
}

- (PSSpecifier *)sliderWithKey:(NSString *)key title:(NSString *)title min:(CGFloat)min max:(CGFloat)max defaultValue:(CGFloat)defaultValue {
    PSSpecifier *specifier = [PSSpecifier preferenceSpecifierNamed:title
                                                            target:self
                                                               set:@selector(setPreferenceValue:specifier:)
                                                               get:@selector(readPreferenceValue:)
                                                            detail:nil
                                                              cell:PSSliderCell
                                                              edit:nil];
    [specifier setProperty:kDomain forKey:@"defaults"];
    [specifier setProperty:key forKey:@"key"];
    [specifier setProperty:@(min) forKey:@"min"];
    [specifier setProperty:@(max) forKey:@"max"];
    [specifier setProperty:@(defaultValue) forKey:@"default"];
    [specifier setProperty:@YES forKey:@"showValue"];
    return specifier;
}

- (NSArray *)specifiers {
    if (_specifiers) return _specifiers;

    NSMutableArray *specs = [NSMutableArray array];

    PSSpecifier *mainGroup = [PSSpecifier emptyGroupSpecifier];
    [mainGroup setProperty:@"Lower values move Control Center modules closer to the top edge. Tap a value to enter it manually." forKey:@"footerText"];
    [specs addObject:mainGroup];

    [specs addObject:[self switchWithKey:@"enabled" title:@"Enabled" defaultValue:YES]];
    [specs addObject:[self sliderWithKey:@"portraitTopOffset" title:@"Vertical top offset" min:0.0 max:240.0 defaultValue:80.0]];
    [specs addObject:[self sliderWithKey:@"landscapeTopOffset" title:@"Horizontal top offset" min:0.0 max:140.0 defaultValue:0.0]];

    PSSpecifier *advancedGroup = [PSSpecifier emptyGroupSpecifier];
    [advancedGroup setProperty:@"The Control Center top header is always removed. By default the real status bar (operator, Wi‑Fi, battery) stays visible at the very top edge. Turn this on to hide it inside Control Center." forKey:@"footerText"];
    [specs addObject:advancedGroup];

    [specs addObject:[self switchWithKey:@"hideStatusBar" title:@"Hide status bar in CC" defaultValue:NO]];

    PSSpecifier *apply = [PSSpecifier preferenceSpecifierNamed:@"Apply Layout"
                                                        target:self
                                                           set:NULL
                                                           get:NULL
                                                        detail:nil
                                                          cell:PSButtonCell
                                                          edit:nil];
    [apply setButtonAction:@selector(applyLayout)];
    [apply setProperty:@1 forKey:@"alignment"];
    [specs addObject:apply];

    PSSpecifier *respring = [PSSpecifier preferenceSpecifierNamed:@"Respring"
                                                          target:self
                                                             set:NULL
                                                             get:NULL
                                                          detail:nil
                                                            cell:PSButtonCell
                                                            edit:nil];
    [respring setButtonAction:@selector(respring)];
    [respring setProperty:@1 forKey:@"alignment"];
    [specs addObject:respring];

    _specifiers = specs;
    return _specifiers;
}

#pragma mark - Value tap-to-edit on slider cells

// The stock PSSliderCell shows a right-aligned numeric value label. Preference
// cells still route many taps to the slider, so place a transparent button over
// the numeric label instead of relying on the label's own gesture recognizer.
- (void)tableView:(UITableView *)tableView willDisplayCell:(PSTableCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *specifier = cell.specifier;
    if (!specifier || specifier.cellType != PSSliderCell) return;

    [self ccg_installValueEditorButtonOnCell:cell specifier:specifier];

    dispatch_async(dispatch_get_main_queue(), ^{
        [self ccg_installValueEditorButtonOnCell:cell specifier:specifier];
    });
}

- (void)ccg_installValueEditorButtonOnCell:(PSTableCell *)cell specifier:(PSSpecifier *)specifier {
    [[cell.contentView viewWithTag:kCCGValueEditorButtonTag] removeFromSuperview];

    UILabel *valueLabel = [self ccg_valueLabelInView:cell];
    if (!valueLabel) return;

    CGRect frame = [valueLabel.superview convertRect:valueLabel.frame toView:cell.contentView];
    frame = CGRectInset(frame, -14.0, -10.0);
    if (CGRectGetWidth(frame) < 56.0) {
        frame.origin.x = CGRectGetMaxX(frame) - 56.0;
        frame.size.width = 56.0;
    }
    frame = CGRectIntersection(frame, cell.contentView.bounds);
    if (CGRectIsEmpty(frame)) return;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.tag = kCCGValueEditorButtonTag;
    button.frame = frame;
    button.backgroundColor = UIColor.clearColor;
    button.accessibilityLabel = [NSString stringWithFormat:@"%@ value", specifier.name ?: @"Slider"];
    objc_setAssociatedObject(button, &kCCGSpecifierKey, specifier, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [button addTarget:self action:@selector(ccg_valueButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [cell.contentView addSubview:button];
    [cell.contentView bringSubviewToFront:button];
}

- (UILabel *)ccg_valueLabelInView:(UIView *)view {
    NSMutableArray<UILabel *> *labels = [NSMutableArray array];
    [self ccg_collectLabelsInView:view labels:labels];

    UILabel *best = nil;
    CGFloat bestX = -CGFLOAT_MAX;
    for (UILabel *label in labels) {
        NSString *text = label.text ?: @"";
        if (label.hidden || label.alpha < 0.01 || text.length == 0) continue;
        BOOL numeric = [self ccg_stringLooksNumeric:text];
        CGRect frame = [label.superview convertRect:label.frame toView:view];
        if ((numeric || label.textAlignment == NSTextAlignmentRight) && CGRectGetMidX(frame) > bestX) {
            best = label;
            bestX = CGRectGetMidX(frame);
        }
    }
    return best;
}

- (void)ccg_collectLabelsInView:(UIView *)view labels:(NSMutableArray<UILabel *> *)labels {
    if ([view isKindOfClass:[UILabel class]]) [labels addObject:(UILabel *)view];
    for (UIView *subview in view.subviews) [self ccg_collectLabelsInView:subview labels:labels];
}

- (BOOL)ccg_stringLooksNumeric:(NSString *)string {
    NSString *trimmed = [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!trimmed.length) return NO;
    NSCharacterSet *allowed = [NSCharacterSet characterSetWithCharactersInString:@"0123456789.,"];
    return [[trimmed stringByTrimmingCharactersInSet:allowed] length] == 0;
}

- (void)ccg_valueButtonTapped:(UIButton *)button {
    PSSpecifier *specifier = objc_getAssociatedObject(button, &kCCGSpecifierKey);
    if (!specifier) return;

    NSString *key  = specifier.properties[@"key"];
    NSString *name = specifier.name;
    CGFloat minV   = [specifier.properties[@"min"] doubleValue];
    CGFloat maxV   = [specifier.properties[@"max"] doubleValue];
    NSNumber *def  = specifier.properties[@"default"];
    if (!key) return;

    CFPropertyListRef raw = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)kDomain);
    NSNumber *current = raw ? CFBridgingRelease(raw) : def;

    UIViewController *presenter = self;
    while (presenter.presentedViewController) presenter = presenter.presentedViewController;

    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:name
                         message:[NSString stringWithFormat:@"Enter a value from %.0f to %.0f", minV, maxV]
                  preferredStyle:UIAlertControllerStyleAlert];

    [alert addTextFieldWithConfigurationHandler:^(UITextField *tf) {
        tf.keyboardType = UIKeyboardTypeDecimalPad;
        tf.text = [NSString stringWithFormat:@"%.0f", current.doubleValue];
    }];

    [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];

    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        __strong typeof(weakSelf) strong = weakSelf;
        NSString *entered = alert.textFields.firstObject.text;
        double v = entered.doubleValue;
        if (v < minV) v = minV;
        if (v > maxV) v = maxV;

        NSNumber *number = @(v);
        CFPreferencesSetValue((__bridge CFStringRef)key,
                              (__bridge CFPropertyListRef)number,
                              (__bridge CFStringRef)kDomain,
                              kCFPreferencesCurrentUser,
                              kCFPreferencesAnyHost);
        CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
        notify_post([kReloadNotification UTF8String]);
        notify_post([kApplyNotification UTF8String]);

        // Refresh the affected cell so the value label updates immediately.
        PSSpecifier *sp = [strong specifierForKey:key inSpecifiers:strong.specifiers];
        if (sp) {
            [strong reloadSpecifier:sp animated:NO];
        } else {
            [strong reloadSpecifiers];
        }
    }]];

    [presenter presentViewController:alert animated:YES completion:nil];
}

// PSSpecifier does not expose a key lookup, so find it by the prefs key we set.
- (PSSpecifier *)specifierForKey:(NSString *)key inSpecifiers:(NSArray *)specifiers {
    for (PSSpecifier *sp in specifiers) {
        if ([sp.properties[@"key"] isEqualToString:key]) return sp;
    }
    return nil;
}

#pragma mark - Standard prefs plumbing

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    [super setPreferenceValue:value specifier:specifier];
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    notify_post([kReloadNotification UTF8String]);
    notify_post([kApplyNotification UTF8String]);
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    return [super readPreferenceValue:specifier];
}

- (void)applyLayout {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    notify_post([kReloadNotification UTF8String]);
    notify_post([kApplyNotification UTF8String]);
}

- (void)respring {
    CFPreferencesAppSynchronize((__bridge CFStringRef)kDomain);
    notify_post([kRespringNotification UTF8String]);
}

@end
