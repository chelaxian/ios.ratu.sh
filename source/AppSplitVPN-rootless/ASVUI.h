#import <UIKit/UIKit.h>
#import "Shared.h"
// Helpers shared by the settings pages.
static inline NSString *L(NSString *en,NSString *ru) {
    NSString *chosen=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS][@"language"];
    BOOL russian=[chosen isEqual:@"ru"] || (![chosen isEqual:@"en"] && [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"]);
    return russian ? ru : en;
}
static inline UIFont *ASVMono(CGFloat size) { return [UIFont fontWithName:@"CourierNewPSMT" size:size] ?: [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightRegular]; }
static inline UIFont *ASVMonoBold(CGFloat size) { return [UIFont fontWithName:@"CourierNewPS-BoldMT" size:size] ?: [UIFont monospacedSystemFontOfSize:size weight:UIFontWeightBold]; }
// Large bold section title followed by an (i) button that shows the hint.
static inline UIView *ASVHeaderView(NSString *title,NSInteger tag,id target,SEL action) {
    UIView *view=[UIView new];
    UILabel *label=[UILabel new];label.text=title;
    label.font=[UIFont systemFontOfSize:20 weight:UIFontWeightBold];label.textColor=UIColor.labelColor;
    UIButton *info=[UIButton buttonWithType:UIButtonTypeInfoLight];info.tag=tag;
    [info addTarget:target action:action forControlEvents:UIControlEventTouchUpInside];
    label.translatesAutoresizingMaskIntoConstraints=NO;info.translatesAutoresizingMaskIntoConstraints=NO;
    [view addSubview:label];[view addSubview:info];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:view.layoutMarginsGuide.leadingAnchor],
        [label.bottomAnchor constraintEqualToAnchor:view.bottomAnchor constant:-6],
        [info.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [info.centerYAnchor constraintEqualToAnchor:label.centerYAnchor]]];
    return view;
}
// Black rounded box with a monospaced text, used for status read-outs.
static inline void ASVFillTerminal(UITableViewCell *cell,NSAttributedString *text,NSInteger tag) {
    cell.textLabel.text=nil;cell.selectionStyle=UITableViewCellSelectionStyleNone;
    UIView *frame=[UIView new];frame.tag=tag;frame.backgroundColor=UIColor.blackColor;
    frame.layer.cornerRadius=10;frame.layer.borderWidth=1.5;frame.layer.borderColor=UIColor.systemGray2Color.CGColor;
    frame.translatesAutoresizingMaskIntoConstraints=NO;[cell.contentView addSubview:frame];
    [NSLayoutConstraint activateConstraints:@[[frame.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor constant:8],[frame.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],[frame.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:8],[frame.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-8]]];
    UILabel *label=[UILabel new];label.tag=tag;label.numberOfLines=0;label.attributedText=text;
    label.translatesAutoresizingMaskIntoConstraints=NO;[frame addSubview:label];
    [NSLayoutConstraint activateConstraints:@[[label.topAnchor constraintEqualToAnchor:frame.topAnchor constant:12],[label.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor constant:12],[label.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-12]]];
}
static inline CGFloat ASVTerminalHeight(NSAttributedString *text,CGFloat tableWidth) {
    CGFloat width=MAX(200,tableWidth-40-24);
    CGRect box=[text boundingRectWithSize:CGSizeMake(width,CGFLOAT_MAX) options:NSStringDrawingUsesLineFragmentOrigin context:nil];
    return ceil(box.size.height)+40;
}
// Appends "label  value" with a padded gray label and a bold colored value.
static inline void ASVTerminalLine(NSMutableAttributedString *text,NSString *label,NSString *value,UIColor *color,NSUInteger pad) {
    if (text.length) [text appendAttributedString:[[NSAttributedString alloc] initWithString:@"\n"]];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:[label stringByPaddingToLength:pad withString:@" " startingAtIndex:0] attributes:@{NSFontAttributeName:ASVMono(14),NSForegroundColorAttributeName:UIColor.systemGrayColor}]];
    [text appendAttributedString:[[NSAttributedString alloc] initWithString:value attributes:@{NSFontAttributeName:ASVMonoBold(14),NSForegroundColorAttributeName:color}]];
}

