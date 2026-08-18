#import <Preferences/PSListController.h>
#import <UIKit/UIKit.h>
#import <WebKit/WebKit.h>

@interface CronTweakListController : PSListController <UITextViewDelegate, WKNavigationDelegate>
@property (nonatomic, strong) UITextView *editorView;
@property (nonatomic, strong) UIButton *saveButton;
@property (nonatomic, strong) UISegmentedControl *pageControl;
@property (nonatomic, strong) UIView *editorContainer;
@property (nonatomic, strong) UIView *webContainer;
@property (nonatomic, strong) WKWebView *webView;
@property (nonatomic, strong) UIActivityIndicatorView *webSpinner;
@property (nonatomic, assign) BOOL webViewLoaded;
@end
