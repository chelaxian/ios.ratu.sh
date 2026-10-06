// Green CRT terminal theme shared by the ratush DNS tweaks.
// Each bundle defines CRTScanlineView to a unique class name before including
// this header, so two bundles loaded into Settings never register the same
// Objective-C class.
#pragma once
#import <UIKit/UIKit.h>

#ifndef CRTScanlineView
#error "define CRTScanlineView to a bundle-unique class name before importing CRTTheme.h"
#endif

static inline UIColor *CRTGreen(void) { return [UIColor colorWithRed:0.25 green:1.00 blue:0.45 alpha:1.0]; }
static inline UIColor *CRTMidGreen(void) { return [UIColor colorWithRed:0.16 green:0.82 blue:0.35 alpha:1.0]; }
static inline UIColor *CRTDimGreen(void) { return [UIColor colorWithRed:0.34 green:0.60 blue:0.40 alpha:1.0]; }
static inline UIColor *CRTCommentGreen(void) { return [UIColor colorWithRed:0.24 green:0.44 blue:0.30 alpha:1.0]; }
static inline UIColor *CRTAmber(void) { return [UIColor colorWithRed:1.00 green:0.78 blue:0.25 alpha:1.0]; }
static inline UIColor *CRTRed(void) { return [UIColor colorWithRed:1.00 green:0.38 blue:0.32 alpha:1.0]; }
static inline UIColor *CRTBackground(void) { return [UIColor colorWithRed:0.008 green:0.030 blue:0.015 alpha:1.0]; }
static inline UIColor *CRTPanel(void) { return [UIColor colorWithRed:0.020 green:0.075 blue:0.038 alpha:1.0]; }
static inline UIColor *CRTBorder(void) { return [UIColor colorWithRed:0.10 green:0.55 blue:0.25 alpha:1.0]; }
static inline UIColor *CRTFieldBG(void) { return [UIColor colorWithRed:0.004 green:0.020 blue:0.010 alpha:1.0]; }

static inline UIFont *CRTFont(CGFloat size, BOOL bold) {
	UIFont *font = [UIFont fontWithName:(bold ? @"CourierNewPS-BoldMT" : @"CourierNewPSMT") size:size];
	if (!font) font = [UIFont fontWithName:(bold ? @"Menlo-Bold" : @"Menlo-Regular") size:size];
	if (!font) font = [UIFont monospacedSystemFontOfSize:size weight:(bold ? UIFontWeightBold : UIFontWeightRegular)];
	return font;
}
static inline UIFont *CRTEditorFont(void) { return CRTFont(13.5, YES); }

// Tiled scanline pattern for single-line inputs.
static inline UIColor *CRTScanlineBG(void) {
	static UIColor *color = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 3), YES, 0);
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		[CRTFieldBG() setFill]; CGContextFillRect(ctx, CGRectMake(0, 0, 4, 3));
		[[UIColor colorWithRed:0 green:0 blue:0 alpha:0.18] setFill];
		CGContextFillRect(ctx, CGRectMake(0, 0, 4, 1));
		UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
		color = [UIColor colorWithPatternImage:img];
	});
	return color;
}

static inline UIImage *CRTDividerImage(void) {
	static UIImage *img = nil;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		UIGraphicsBeginImageContextWithOptions(CGSizeMake(2, 30), NO, 0);
		CGContextRef ctx = UIGraphicsGetCurrentContext();
		[[CRTBorder() colorWithAlphaComponent:0.6] setFill];
		CGContextFillRect(ctx, CGRectMake(0, 0, 1, 30));
		img = UIGraphicsGetImageFromCurrentImageContext();
		UIGraphicsEndImageContext();
	});
	return [img resizableImageWithCapInsets:UIEdgeInsetsMake(14, 0, 14, 0)];
}

static inline void CRTThemeSegment(UISegmentedControl *seg, NSArray<NSString *> *titles) {
	for (NSUInteger i = 0; i < titles.count && i < seg.numberOfSegments; i++) [seg setTitle:titles[i] forSegmentAtIndex:i];
	[seg setTitleTextAttributes:@{NSForegroundColorAttributeName: CRTDimGreen(), NSFontAttributeName: CRTFont(12, NO)} forState:UIControlStateNormal];
	[seg setTitleTextAttributes:@{NSForegroundColorAttributeName: CRTGreen(), NSFontAttributeName: CRTFont(12, YES)} forState:UIControlStateSelected];
	[seg setBackgroundImage:[UIImage new] forState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	UIGraphicsBeginImageContextWithOptions(CGSizeMake(4, 4), YES, 0);
	[[CRTBorder() colorWithAlphaComponent:0.35] setFill]; UIRectFill(CGRectMake(0, 0, 4, 4));
	UIImage *sel = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	[seg setBackgroundImage:sel forState:UIControlStateSelected barMetrics:UIBarMetricsDefault];
	[seg setDividerImage:CRTDividerImage() forLeftSegmentState:UIControlStateNormal rightSegmentState:UIControlStateNormal barMetrics:UIBarMetricsDefault];
	seg.tintColor = UIColor.clearColor;
	seg.backgroundColor = CRTPanel();
	seg.layer.cornerRadius = 7;
	seg.layer.borderWidth = 1.0;
	seg.layer.borderColor = [CRTBorder() colorWithAlphaComponent:0.7].CGColor;
	seg.layer.masksToBounds = YES;
}

static inline UITextField *CRTMakeField(id<UITextFieldDelegate> delegate) {
	UITextField *field = [[UITextField alloc] init];
	field.font = CRTEditorFont();
	field.textColor = CRTGreen();
	field.tintColor = CRTGreen();
	field.backgroundColor = CRTScanlineBG();
	field.layer.cornerRadius = 8;
	field.layer.borderWidth = 1.0;
	field.layer.borderColor = [CRTBorder() colorWithAlphaComponent:0.8].CGColor;
	field.keyboardAppearance = UIKeyboardAppearanceDark;
	field.autocapitalizationType = UITextAutocapitalizationTypeNone;
	field.autocorrectionType = UITextAutocorrectionTypeNo;
	field.spellCheckingType = UITextSpellCheckingTypeNo;
	field.smartDashesType = UITextSmartDashesTypeNo;
	field.smartQuotesType = UITextSmartQuotesTypeNo;
	field.returnKeyType = UIReturnKeyDone;
	field.clearButtonMode = UITextFieldViewModeWhileEditing;
	field.delegate = delegate;
	field.leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 9, 1)];
	field.leftViewMode = UITextFieldViewModeAlways;
	return field;
}

static inline void CRTSetPlaceholder(UITextField *field, NSString *text) {
	field.attributedPlaceholder = [[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
		NSForegroundColorAttributeName: [CRTDimGreen() colorWithAlphaComponent:0.75],
		NSFontAttributeName: CRTFont(12.5, NO)}];
}

static inline UITextView *CRTMakeEditor(id<UITextViewDelegate> delegate) {
	UITextView *tv = [[UITextView alloc] initWithFrame:CGRectZero];
	tv.font = CRTEditorFont();
	tv.textColor = CRTGreen();
	tv.tintColor = [CRTDimGreen() colorWithAlphaComponent:0.35];
	tv.layer.cornerRadius = 8;
	tv.clipsToBounds = YES;
	tv.layer.borderWidth = 1.0;
	tv.layer.borderColor = [CRTBorder() colorWithAlphaComponent:0.8].CGColor;
	tv.backgroundColor = CRTFieldBG();
	tv.textContainerInset = UIEdgeInsetsMake(10, 9, 10, 9);
	tv.textContainer.lineFragmentPadding = 0;
	tv.alwaysBounceVertical = YES;
	tv.showsHorizontalScrollIndicator = NO;
	tv.indicatorStyle = UIScrollViewIndicatorStyleWhite;
	tv.keyboardAppearance = UIKeyboardAppearanceDark;
	tv.autocorrectionType = UITextAutocorrectionTypeNo;
	tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
	tv.spellCheckingType = UITextSpellCheckingTypeNo;
	tv.smartDashesType = UITextSmartDashesTypeNo;
	tv.smartQuotesType = UITextSmartQuotesTypeNo;
	tv.delegate = delegate;
	return tv;
}

static inline UIButton *CRTMakePanelButton(id target, SEL action) {
	UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
	b.backgroundColor = CRTPanel();
	b.layer.cornerRadius = 7;
	b.layer.borderWidth = 1.0;
	b.layer.borderColor = [CRTBorder() colorWithAlphaComponent:0.7].CGColor;
	b.titleLabel.font = CRTFont(13, YES);
	b.titleLabel.adjustsFontSizeToFitWidth = YES;
	b.titleLabel.minimumScaleFactor = 0.7;
	[b setTitleColor:CRTGreen() forState:UIControlStateNormal];
	[b addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
	return b;
}

static inline UISwitch *CRTMakeSwitch(id target, SEL action) {
	UISwitch *sw = [[UISwitch alloc] initWithFrame:CGRectZero];
	sw.onTintColor = CRTMidGreen();
	sw.thumbTintColor = [UIColor colorWithWhite:0.92 alpha:1.0];
	sw.backgroundColor = CRTPanel();
	sw.layer.cornerRadius = 16;
	sw.clipsToBounds = YES;
	sw.transform = CGAffineTransformMakeScale(0.82, 0.82);
	[sw addTarget:target action:action forControlEvents:UIControlEventValueChanged];
	return sw;
}

static inline UILabel *CRTMakeLabel(CGFloat size, BOOL bold, UIColor *color) {
	UILabel *l = [[UILabel alloc] init];
	l.font = CRTFont(size, bold);
	l.textColor = color;
	l.adjustsFontSizeToFitWidth = YES;
	l.minimumScaleFactor = 0.65;
	return l;
}

// Scanline overlay drawn above editors (does not scroll, no touches).
@interface CRTScanlineView : UIView
@end
@implementation CRTScanlineView
- (instancetype)initWithFrame:(CGRect)frame {
	if ((self = [super initWithFrame:frame])) {
		self.userInteractionEnabled = NO;
		self.backgroundColor = UIColor.clearColor;
		self.contentMode = UIViewContentModeRedraw;
	}
	return self;
}
- (void)drawRect:(CGRect)rect {
	CGContextRef ctx = UIGraphicsGetCurrentContext();
	CGContextSetRGBFillColor(ctx, 0.0, 0.0, 0.0, 0.16);
	for (CGFloat y = 0; y < rect.size.height; y += 3.0) CGContextFillRect(ctx, CGRectMake(0, y, rect.size.width, 1.0));
	CGContextSetRGBFillColor(ctx, 0.15, 1.0, 0.4, 0.05);
	CGContextFillRect(ctx, CGRectMake(0, 0, rect.size.width, 2.0));
}
@end

