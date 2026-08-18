#import "CronTweakListController.h"
#import <Preferences/PSSpecifier.h>
#import <sys/socket.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <unistd.h>
#import <string.h>

#define kPrefsPath @"/var/mobile/Library/Preferences/com.ratush.crontweak.plist"
#define kControlPort 53536

@interface CronTweakListController ()
- (NSAttributedString *)highlightedCronText:(NSString *)text;
- (NSArray<NSValue *> *)tokenRangesInLine:(NSString *)line;
- (UIFont *)cronFontRegular;
- (UIFont *)cronFontBold;
- (UIFont *)cronFontItalic;
@end

@implementation CronTweakListController

- (NSArray *)specifiers {
	if (!_specifiers) {
		NSMutableArray *specs = [NSMutableArray array];
		PSSpecifier *statusGroup = [PSSpecifier preferenceSpecifierNamed:@""
			target:self set:NULL get:NULL detail:Nil cell:PSGroupCell edit:Nil];
		[statusGroup setProperty:[self statusFooterText] forKey:@"footerText"];
		[specs addObject:statusGroup];
		_specifiers = specs;
	}
	return _specifiers;
}

- (NSString *)statusFooterText {
	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
	NSString *at = prefs[@"LastAppliedAt"];
	if (!at) {
		return @"One job per line: minute hour day month weekday command\n"
		        "Example: */15 * * * * echo hi >> /var/mobile/hi.log\n"
		        "Jobs run as `mobile` (same user as SSH) via native launchd -- "
		        "not a background loop, real LaunchDaemons.";
	}
	NSNumber *ok = prefs[@"LastAppliedOK"];
	NSNumber *count = prefs[@"LastAppliedCount"];
	NSArray *errors = prefs[@"LastAppliedErrors"];
	NSMutableString *s = [NSMutableString string];
	if ([ok boolValue]) {
		[s appendFormat:@"Last applied %@: %@ job(s) scheduled OK.", at, count];
	} else {
		[s appendFormat:@"Last applied %@: FAILED.\n%@", at, [errors componentsJoinedByString:@"\n"]];
	}
	return s;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"Cron Scheduler";
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	if (!self.editorView) {
		[self setupEditorHeader];
	}
}

- (void)viewDidLayoutSubviews {
	[super viewDidLayoutSubviews];
	if (!self.editorView) {
		// The table view is not always reachable from viewWillAppear on this
		// runtime; retry once real layout has happened.
		[self setupEditorHeader];
	}
}

- (void)setupEditorHeader {
	CGFloat width = self.view.bounds.size.width > 0 ? self.view.bounds.size.width : 375.0;
	CGFloat segHeight = 32.0;
	CGFloat contentHeight = 460.0; // tall enough for the editor AND a usable crontab.guru viewport
	CGFloat pad = 12.0;
	CGFloat totalHeight = pad + segHeight + pad + contentHeight + pad;

	UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, totalHeight)];

	UISegmentedControl *seg = [[UISegmentedControl alloc] initWithItems:@[@"Editor", @"crontab.guru"]];
	seg.frame = CGRectMake(pad, pad, width - pad * 2, segHeight);
	seg.selectedSegmentIndex = 0;
	[seg addTarget:self action:@selector(pageChanged:) forControlEvents:UIControlEventValueChanged];
	[header addSubview:seg];
	self.pageControl = seg;

	CGRect contentFrame = CGRectMake(pad, pad + segHeight + pad, width - pad * 2, contentHeight);

	// ---- page 1: the crontab-syntax editor ----
	UIView *editorContainer = [[UIView alloc] initWithFrame:contentFrame];

	CGFloat editorHeight = contentHeight - 56;
	UITextView *tv = [[UITextView alloc] initWithFrame:CGRectMake(0, 0, contentFrame.size.width, editorHeight)];
	tv.font = [UIFont fontWithName:@"Menlo" size:13] ?: [UIFont systemFontOfSize:13];
	tv.layer.borderColor = [UIColor separatorColor].CGColor;
	tv.layer.borderWidth = 1.0;
	tv.layer.cornerRadius = 6.0;
	tv.autocapitalizationType = UITextAutocapitalizationTypeNone;
	tv.autocorrectionType = UITextAutocorrectionTypeNo;
	tv.smartQuotesType = UITextSmartQuotesTypeNo;
	tv.smartDashesType = UITextSmartDashesTypeNo;
	tv.spellCheckingType = UITextSpellCheckingTypeNo;
	tv.attributedText = [self highlightedCronText:[self currentCronText]];
	tv.typingAttributes = @{NSFontAttributeName: [self cronFontRegular], NSForegroundColorAttributeName: [UIColor labelColor]};
	tv.delegate = self;
	[editorContainer addSubview:tv];
	self.editorView = tv;

	UIButton *save = [UIButton buttonWithType:UIButtonTypeSystem];
	save.frame = CGRectMake(0, editorHeight + pad, contentFrame.size.width, 44);
	[save setTitle:@"Save" forState:UIControlStateNormal];
	save.titleLabel.font = [UIFont boldSystemFontOfSize:17];
	save.backgroundColor = [UIColor systemBlueColor];
	[save setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
	save.layer.cornerRadius = 10.0;
	[save addTarget:self action:@selector(saveTapped:) forControlEvents:UIControlEventTouchUpInside];
	[editorContainer addSubview:save];
	self.saveButton = save;

	[header addSubview:editorContainer];
	self.editorContainer = editorContainer;

	// ---- page 2: plain crontab.guru passthrough (build a cron line there, copy it into the editor) ----
	UIView *webContainer = [[UIView alloc] initWithFrame:contentFrame];
	webContainer.hidden = YES;
	webContainer.clipsToBounds = YES;
	webContainer.layer.cornerRadius = 6.0;
	webContainer.layer.borderColor = [UIColor separatorColor].CGColor;
	webContainer.layer.borderWidth = 1.0;

	WKWebView *web = [[WKWebView alloc] initWithFrame:webContainer.bounds];
	web.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
	web.navigationDelegate = self;
	[webContainer addSubview:web];
	self.webView = web;

	UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
	spinner.center = CGPointMake(webContainer.bounds.size.width / 2, webContainer.bounds.size.height / 2);
	spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
	[webContainer addSubview:spinner];
	self.webSpinner = spinner;

	[header addSubview:webContainer];
	self.webContainer = webContainer;

	UITableView *table = [self findTableView];
	if (table) {
		table.tableHeaderView = header;
	} else {
		// Last-resort fallback: pin the editor above the table manually so the
		// feature is still usable even if the table couldn't be located.
		header.frame = CGRectMake(0, 0, width, totalHeight);
		[self.view addSubview:header];
	}
}

- (void)pageChanged:(UISegmentedControl *)sender {
	BOOL showWeb = (sender.selectedSegmentIndex == 1);
	self.editorContainer.hidden = showWeb;
	self.webContainer.hidden = !showWeb;
	if (showWeb) {
		[self.editorView resignFirstResponder];
		if (!self.webViewLoaded) {
			self.webViewLoaded = YES;
			[self.webSpinner startAnimating];
			NSURL *url = [NSURL URLWithString:@"https://crontab.guru/"];
			[self.webView loadRequest:[NSURLRequest requestWithURL:url]];
		}
	}
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
	[self.webSpinner stopAnimating];
}

- (void)webView:(WKWebView *)webView didFailNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self.webSpinner stopAnimating];
}

- (void)webView:(WKWebView *)webView didFailProvisionalNavigation:(WKNavigation *)navigation withError:(NSError *)error {
	[self.webSpinner stopAnimating];
}

- (UITableView *)findTableView {
	return (UITableView *)[self findTableViewIn:self.view depth:0];
}

- (UIView *)findTableViewIn:(UIView *)root depth:(NSInteger)depth {
	if (depth > 6 || !root) return nil;
	if ([root isKindOfClass:[UITableView class]]) {
		return root;
	}
	for (UIView *sub in root.subviews) {
		UIView *found = [self findTableViewIn:sub depth:depth + 1];
		if (found) return found;
	}
	return nil;
}

- (NSString *)currentCronText {
	NSDictionary *prefs = [NSDictionary dictionaryWithContentsOfFile:kPrefsPath];
	NSString *text = prefs[@"CronText"];
	return text ?: @"";
}

- (void)textViewDidEndEditing:(UITextView *)textView {
	[self persistTextOnly:textView.text];
}

- (void)textViewDidChange:(UITextView *)textView {
	if (textView != self.editorView) return;
	NSRange selected = textView.selectedRange;
	textView.attributedText = [self highlightedCronText:textView.text];
	NSUInteger len = textView.attributedText.length;
	NSUInteger loc = MIN(selected.location, len);
	NSUInteger safeLen = MIN(selected.length, len - loc);
	textView.selectedRange = NSMakeRange(loc, safeLen);
	textView.typingAttributes = @{NSFontAttributeName: [self cronFontRegular], NSForegroundColorAttributeName: [UIColor labelColor]};
}

- (UIFont *)cronFontRegular {
	return [UIFont fontWithName:@"Menlo" size:13] ?: [UIFont systemFontOfSize:13];
}

- (UIFont *)cronFontBold {
	return [UIFont fontWithName:@"Menlo-Bold" size:13] ?: [UIFont boldSystemFontOfSize:13];
}

- (UIFont *)cronFontItalic {
	return [UIFont fontWithName:@"Menlo-Italic" size:13] ?: [UIFont italicSystemFontOfSize:13];
}

// Whitespace-separated token ranges within a single line, in the line's own
// coordinate space (caller offsets them into the full text).
- (NSArray<NSValue *> *)tokenRangesInLine:(NSString *)line {
	NSMutableArray<NSValue *> *ranges = [NSMutableArray array];
	NSCharacterSet *ws = [NSCharacterSet whitespaceCharacterSet];
	NSUInteger len = line.length;
	NSUInteger i = 0;
	while (i < len) {
		while (i < len && [ws characterIsMember:[line characterAtIndex:i]]) i++;
		if (i >= len) break;
		NSUInteger start = i;
		while (i < len && ![ws characterIsMember:[line characterAtIndex:i]]) i++;
		[ranges addObject:[NSValue valueWithRange:NSMakeRange(start, i - start)]];
	}
	return ranges;
}

// Comment/blank lines -> dimmed italic. Otherwise the first 5 whitespace
// tokens (the schedule fields) get one color+weight, and everything from the
// 6th token to end of line (the command) gets another -- same idea as
// keyword/string highlighting in a normal code editor.
- (NSAttributedString *)highlightedCronText:(NSString *)text {
	text = text ?: @"";
	UIFont *regular = [self cronFontRegular];
	UIFont *bold = [self cronFontBold];
	UIFont *italic = [self cronFontItalic];
	UIColor *baseColor = [UIColor labelColor];
	UIColor *commentColor = [UIColor secondaryLabelColor];
	UIColor *fieldColor = [UIColor systemOrangeColor];
	UIColor *commandColor = [UIColor systemGreenColor];

	NSMutableAttributedString *result = [[NSMutableAttributedString alloc] initWithString:text];
	[result addAttributes:@{NSFontAttributeName: regular, NSForegroundColorAttributeName: baseColor}
	                 range:NSMakeRange(0, result.length)];

	NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
	NSUInteger offset = 0;
	for (NSString *line in lines) {
		NSUInteger lineLen = line.length;
		NSString *trimmed = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (trimmed.length > 0) {
			if ([trimmed hasPrefix:@"#"]) {
				NSRange lineRange = NSMakeRange(offset, lineLen);
				[result addAttribute:NSForegroundColorAttributeName value:commentColor range:lineRange];
				[result addAttribute:NSFontAttributeName value:italic range:lineRange];
			} else {
				NSArray<NSValue *> *tokens = [self tokenRangesInLine:line];
				NSUInteger fieldCount = MIN(tokens.count, (NSUInteger)5);
				for (NSUInteger i = 0; i < fieldCount; i++) {
					NSRange r = [tokens[i] rangeValue];
					NSRange abs = NSMakeRange(offset + r.location, r.length);
					[result addAttribute:NSForegroundColorAttributeName value:fieldColor range:abs];
					[result addAttribute:NSFontAttributeName value:bold range:abs];
				}
				if (tokens.count > 5) {
					NSRange sixth = [tokens[5] rangeValue];
					NSRange abs = NSMakeRange(offset + sixth.location, lineLen - sixth.location);
					[result addAttribute:NSForegroundColorAttributeName value:commandColor range:abs];
				}
			}
		}
		offset += lineLen + 1; // account for the '\n' consumed by the split
	}
	return result;
}

- (void)persistTextOnly:(NSString *)text {
	NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:kPrefsPath] ?: [NSMutableDictionary dictionary];
	d[@"CronText"] = text ?: @"";
	NSString *dir = [kPrefsPath stringByDeletingLastPathComponent];
	[[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
	[d writeToFile:kPrefsPath atomically:YES];
}

- (void)saveTapped:(id)sender {
	[self.editorView resignFirstResponder];
	NSString *text = self.editorView.text ?: @"";

	NSMutableArray *quickErrors = [NSMutableArray array];
	NSArray *lines = [text componentsSeparatedByString:@"\n"];
	for (NSUInteger i = 0; i < lines.count; i++) {
		NSString *line = [lines[i] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (line.length == 0 || [line hasPrefix:@"#"]) continue;
		NSArray *rawTokens = [line componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		NSMutableArray *tokens = [NSMutableArray array];
		for (NSString *t in rawTokens) if (t.length) [tokens addObject:t];
		if (tokens.count < 6) {
			[quickErrors addObject:[NSString stringWithFormat:@"Line %lu: expected 5 time fields + command", (unsigned long)(i + 1)]];
		}
	}
	if (quickErrors.count) {
		[self showAlertTitle:@"Fix these lines first" message:[quickErrors componentsJoinedByString:@"\n"]];
		return;
	}

	[self persistTextOnly:text];

	self.saveButton.enabled = NO;
	[self.saveButton setTitle:@"Saving..." forState:UIControlStateNormal];

	__weak typeof(self) weakSelf = self;
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		NSString *reply = [weakSelf sendApplyToDaemon:text];
		dispatch_async(dispatch_get_main_queue(), ^{
			__strong typeof(weakSelf) strongSelf = weakSelf;
			if (!strongSelf) return;
			strongSelf.saveButton.enabled = YES;
			[strongSelf.saveButton setTitle:@"Save" forState:UIControlStateNormal];
			if (!reply) {
				[strongSelf showAlertTitle:@"No response"
					message:@"Could not reach the crontweakd daemon on 127.0.0.1:53536. Is it running?"];
				return;
			}
			if ([reply hasPrefix:@"OK"]) {
				[strongSelf showAlertTitle:@"Applied" message:reply];
			} else {
				[strongSelf showAlertTitle:@"Daemon rejected the schedule" message:reply];
			}
			[strongSelf reloadSpecifiers];
		});
	});
}

- (NSString *)sendApplyToDaemon:(NSString *)text {
	int sock = socket(AF_INET, SOCK_STREAM, 0);
	if (sock < 0) return nil;

	struct timeval tv;
	tv.tv_sec = 8; tv.tv_usec = 0;
	setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
	setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));

	struct sockaddr_in addr;
	memset(&addr, 0, sizeof(addr));
	addr.sin_family = AF_INET;
	addr.sin_port = htons(kControlPort);
	inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);

	if (connect(sock, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
		close(sock);
		return nil;
	}

	NSData *payload = [text dataUsingEncoding:NSUTF8StringEncoding];
	write(sock, payload.bytes, payload.length);
	shutdown(sock, SHUT_WR);

	NSMutableData *response = [NSMutableData data];
	uint8_t buf[4096];
	ssize_t n;
	while ((n = read(sock, buf, sizeof(buf))) > 0) {
		[response appendBytes:buf length:(NSUInteger)n];
	}
	close(sock);

	if (response.length == 0) return nil;
	return [[NSString alloc] initWithData:response encoding:NSUTF8StringEncoding];
}

- (void)showAlertTitle:(NSString *)title message:(NSString *)message {
	UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
		message:message preferredStyle:UIAlertControllerStyleAlert];
	[ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:ac animated:YES completion:nil];
}

@end
