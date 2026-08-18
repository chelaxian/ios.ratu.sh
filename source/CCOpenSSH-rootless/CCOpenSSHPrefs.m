#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <spawn.h>
#import <sys/wait.h>
#import <Preferences/PSListController.h>
#import <Preferences/PSSpecifier.h>

extern char **environ;

@interface CCOpenSSHPrefs : PSListController
@end

@implementation CCOpenSSHPrefs

static NSString *Domain = @"com.ratush.ccopenssh";
static NSString *Path(void) { return @"/var/mobile/Library/Preferences/com.ratush.ccopenssh.plist"; }

- (UITextField *)firstTextFieldInView:(UIView *)view {
    if ([view isKindOfClass:UITextField.class]) return (UITextField *)view;
    for (UIView *subview in view.subviews) {
        UITextField *field = [self firstTextFieldInView:subview];
        if (field) return field;
    }
    return nil;
}

- (void)collectLabelsInView:(UIView *)view labels:(NSMutableArray *)labels {
    if ([view isKindOfClass:UILabel.class]) {
        NSString *text = ((UILabel *)view).text;
        if (text.length) [labels addObject:text];
    }
    for (UIView *subview in view.subviews) [self collectLabelsInView:subview labels:labels];
}

- (NSString *)visibleValueForCell:(UITableViewCell *)cell specifier:(PSSpecifier *)specifier {
    UITextField *field = [self firstTextFieldInView:cell];
    if (field) return field.text ?: @"";
    NSMutableArray *labels = [NSMutableArray array];
    [self collectLabelsInView:cell labels:labels];
    for (NSString *label in [labels reverseObjectEnumerator]) {
        if (![label isEqualToString:specifier.name ?: @""]) return label;
    }
    return nil;
}

- (NSMutableDictionary *)prefs {
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithContentsOfFile:Path()];
    if (!d) d = [NSMutableDictionary dictionary];
    if (!d[@"port"]) d[@"port"] = @2222;
    if (!d[@"username"]) d[@"username"] = @"mobile";
    if (!d[@"acl"]) d[@"acl"] = [NSMutableArray arrayWithObject:@"0.0.0.0/0"];
    if (!d[@"publicKeys"]) {
        NSString *legacyKey = [d[@"publicKey"] isKindOfClass:NSString.class] ? d[@"publicKey"] : @"";
        d[@"publicKeys"] = legacyKey.length ? [NSMutableArray arrayWithObject:legacyKey] : [NSMutableArray array];
    }
    if (!d[@"allowPassword"]) d[@"allowPassword"] = @YES;
    if (!d[@"allowKey"]) d[@"allowKey"] = @YES;
    if (!d[@"enabled"]) d[@"enabled"] = @YES;
    return d;
}

- (void)save:(NSDictionary *)d {
    [d writeToFile:Path() atomically:YES];
    CFPreferencesAppSynchronize((__bridge CFStringRef)Domain);
}

- (id)getValue:(PSSpecifier *)s {
    NSString *key = [s propertyForKey:@"key"];
    NSDictionary *prefs = [self prefs];
    id v = nil;
    if ([key hasPrefix:@"acl."]) {
        NSInteger idx = [[key substringFromIndex:4] integerValue];
        NSArray *a = prefs[@"acl"];
        if (idx >= 0 && idx < (NSInteger)a.count) v = a[idx];
    } else if ([key hasPrefix:@"publicKeys."]) {
        NSInteger idx = [[key substringFromIndex:11] integerValue];
        NSArray *a = prefs[@"publicKeys"];
        if (idx >= 0 && idx < (NSInteger)a.count) v = a[idx];
    } else {
        v = prefs[key];
    }
    return v ?: @"";
}

- (void)setValue:(id)v specifier:(PSSpecifier *)s {
    NSString *key = [s propertyForKey:@"key"];
    NSMutableDictionary *d = [self prefs];
    if ([key isEqualToString:@"port"]) {
        NSInteger p = [v integerValue];
        if (p < 1 || p > 65535) p = 2222;
        d[key] = @(p);
    } else if ([key hasPrefix:@"acl."]) {
        NSInteger idx = [[key substringFromIndex:4] integerValue];
        NSMutableArray *a = [d[@"acl"] mutableCopy] ?: [NSMutableArray array];
        if (idx >= 0 && idx < (NSInteger)a.count) a[idx] = [self validCIDR:v] ? v : @"0.0.0.0/0";
        d[@"acl"] = a;
    } else if ([key hasPrefix:@"publicKeys."]) {
        NSInteger idx = [[key substringFromIndex:11] integerValue];
        NSMutableArray *a = [d[@"publicKeys"] mutableCopy] ?: [NSMutableArray array];
        if (idx >= 0 && idx < (NSInteger)a.count) a[idx] = v ?: @"";
        d[@"publicKeys"] = a;
    } else if ([v isKindOfClass:NSNumber.class]) {
        d[key] = v;
    } else {
        d[key] = v ?: @"";
    }
    [self save:d];
    if ([key isEqualToString:@"enabled"]) [self apply:nil];
}

- (BOOL)validCIDR:(NSString *)s {
    NSRegularExpression *re = [NSRegularExpression regularExpressionWithPattern:@"^(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])(\\.(25[0-5]|2[0-4][0-9]|1?[0-9]?[0-9])){3}(/([0-9]|[12][0-9]|3[0-2]))?$" options:0 error:nil];
    NSString *value = s ?: @"";
    return [re numberOfMatchesInString:value options:0 range:NSMakeRange(0, value.length)] == 1;
}

- (PSSpecifier *)spec:(NSString *)name cell:(PSCellType)cell key:(NSString *)key {
    PSSpecifier *s = [PSSpecifier preferenceSpecifierNamed:name target:self set:key ? @selector(setValue:specifier:) : NULL get:key ? @selector(getValue:) : NULL detail:nil cell:cell edit:nil];
    if (key) [s setProperty:key forKey:@"key"];
    if ([key isEqualToString:@"port"]) [s setProperty:@YES forKey:@"isNumeric"];
    if (key) [s setProperty:@YES forKey:@"noAutoCorrect"];
    return s;
}

- (NSMutableArray *)buildSpecifiers {
    NSMutableArray *a = [NSMutableArray array];
    [a addObject:[self spec:@"Service" cell:PSGroupCell key:nil]];
    [a addObject:[self spec:@"Enable" cell:PSSwitchCell key:@"enabled"]];
    [a addObject:[self spec:@"Port" cell:PSEditTextCell key:@"port"]];
    [a addObject:[self spec:@"Username" cell:PSEditTextCell key:@"username"]];
    [a addObject:[self spec:@"Password" cell:PSSecureEditTextCell key:@"password"]];
    [a addObject:[self spec:@"Password Auth" cell:PSSwitchCell key:@"allowPassword"]];
    [a addObject:[self spec:@"Key Auth" cell:PSSwitchCell key:@"allowKey"]];
    [a addObject:[self spec:@"Public Keys" cell:PSGroupCell key:nil]];
    NSArray *keys = [self prefs][@"publicKeys"];
    for (NSUInteger i = 0; i < keys.count; i++) {
        PSSpecifier *s = [self spec:[NSString stringWithFormat:@"Key %lu", (unsigned long)i + 1] cell:PSEditTextCell key:[NSString stringWithFormat:@"publicKeys.%lu", (unsigned long)i]];
        [s setProperty:@"publicKeys" forKey:@"deleteList"];
        [s setProperty:@(i) forKey:@"deleteIndex"];
        [a addObject:s];
    }
    PSSpecifier *plusKey = [self spec:@"+" cell:PSButtonCell key:nil]; [plusKey setProperty:@"addKey" forKey:@"action"]; [a addObject:plusKey];
    [a addObject:[self spec:@"Source ACL" cell:PSGroupCell key:nil]];
    NSArray *acl = [self prefs][@"acl"];
    for (NSUInteger i = 0; i < acl.count; i++) {
        PSSpecifier *s = [self spec:[NSString stringWithFormat:@"ACL %lu", (unsigned long)i + 1] cell:PSEditTextCell key:[NSString stringWithFormat:@"acl.%lu", (unsigned long)i]];
        [s setProperty:@"acl" forKey:@"deleteList"];
        [s setProperty:@(i) forKey:@"deleteIndex"];
        [a addObject:s];
    }
    PSSpecifier *plus = [self spec:@"+" cell:PSButtonCell key:nil]; [plus setProperty:@"addACL" forKey:@"action"]; [a addObject:plus];
    [a addObject:[self spec:@"Actions" cell:PSGroupCell key:nil]];
    PSSpecifier *apply = [self spec:@"Apply" cell:PSButtonCell key:nil]; [apply setProperty:@"apply" forKey:@"action"]; [a addObject:apply];
    [apply setButtonAction:@selector(apply:)];
    PSSpecifier *respring = [self spec:@"Respring" cell:PSButtonCell key:nil]; [respring setProperty:@"respring" forKey:@"action"]; [a addObject:respring];
    [respring setButtonAction:@selector(respring:)];
    return a;
}

- (NSArray *)specifiers {
    if (!_specifiers) _specifiers = [[self buildSpecifiers] mutableCopy];
    return _specifiers;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    PSSpecifier *s = [self specifierAtIndexPath:indexPath];
    NSString *act = [s propertyForKey:@"action"];
    if (!act) {
        [super tableView:tableView didSelectRowAtIndexPath:indexPath];
        return;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ([act isEqualToString:@"addACL"]) {
        [self addACLRow];
    } else if ([act isEqualToString:@"addKey"]) {
        [self addKeyRow];
    } else if ([act isEqualToString:@"apply"]) [self apply:nil];
    else if ([act isEqualToString:@"respring"]) [self respring:nil];
}

- (void)addACLRow {
    [self saveVisibleEditors];
    NSMutableDictionary *d = [self prefs]; NSMutableArray *acl = [d[@"acl"] mutableCopy] ?: [NSMutableArray array];
    [acl addObject:@"0.0.0.0/0"]; d[@"acl"] = acl; [self save:d]; _specifiers = nil; [self reloadSpecifiers];
}

- (void)addKeyRow {
    [self saveVisibleEditors];
    NSMutableDictionary *d = [self prefs]; NSMutableArray *keys = [d[@"publicKeys"] mutableCopy] ?: [NSMutableArray array];
    [keys addObject:@""]; d[@"publicKeys"] = keys; [self save:d]; _specifiers = nil; [self reloadSpecifiers];
}

- (void)saveVisibleEditors {
    UITableView *table = [self.view isKindOfClass:UITableView.class] ? (UITableView *)self.view : nil;
    if (!table && [self respondsToSelector:@selector(table)]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id maybeTable = [self performSelector:@selector(table)];
#pragma clang diagnostic pop
        if ([maybeTable isKindOfClass:UITableView.class]) table = (UITableView *)maybeTable;
    }
    if (!table) return;
    for (UITableViewCell *cell in table.visibleCells) {
        NSIndexPath *indexPath = [table indexPathForCell:cell];
        if (!indexPath) continue;
        PSSpecifier *specifier = [self specifierAtIndexPath:indexPath];
        NSString *key = [specifier propertyForKey:@"key"];
        if (!key.length) continue;
        NSString *value = [self visibleValueForCell:cell specifier:specifier];
        if (value) [self setValue:value specifier:specifier];
    }
    [table endEditing:YES];
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    PSSpecifier *s = [self specifierAtIndexPath:indexPath];
    return [s propertyForKey:@"deleteList"] != nil;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    (void)tableView;
    if (editingStyle != UITableViewCellEditingStyleDelete) return;
    PSSpecifier *s = [self specifierAtIndexPath:indexPath];
    NSString *list = [s propertyForKey:@"deleteList"];
    NSNumber *indexNumber = [s propertyForKey:@"deleteIndex"];
    if (!list || !indexNumber) return;
    NSMutableDictionary *d = [self prefs];
    NSMutableArray *items = [d[list] mutableCopy] ?: [NSMutableArray array];
    NSInteger idx = indexNumber.integerValue;
    if (idx >= 0 && idx < (NSInteger)items.count) {
        [items removeObjectAtIndex:(NSUInteger)idx];
        d[list] = items;
        [self save:d];
        _specifiers = nil;
        [self reloadSpecifiers];
    }
}

- (void)run:(NSString *)arg {
    NSString *helper = [self helperPath];
    if (!helper) return;
    const char *p = helper.UTF8String;
    char *argv[] = { (char *)p, (char *)arg.UTF8String, NULL };
    pid_t pid = 0;
    posix_spawn(&pid, p, NULL, NULL, argv, environ);
}

- (NSString *)helperPath {
    NSString *helper = @"/var/jb/usr/bin/ccopenssh";
    return [NSFileManager.defaultManager isExecutableFileAtPath:helper] ? helper : nil;
}

- (int)runSync:(NSString *)arg {
    NSString *helper = [self helperPath];
    if (!helper) return 127;
    const char *p = helper.UTF8String;
    char *argv[] = { (char *)p, (char *)arg.UTF8String, NULL };
    pid_t pid = 0;
    int rc = posix_spawn(&pid, p, NULL, NULL, argv, environ);
    if (rc != 0) return 127;
    int status = 0;
    while (waitpid(pid, &status, 0) < 0) {}
    if (WIFEXITED(status)) return WEXITSTATUS(status);
    if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
    return 126;
}

- (void)showMessage:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)apply:(id)sender {
    (void)sender;
    [self saveVisibleEditors];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        int rc = [self runSync:@"apply"];
        NSString *message = rc == 0 ? @"Settings were saved and applied to OpenSSH." : [NSString stringWithFormat:@"ccopenssh apply failed with code %d.", rc];
        [self showMessage:rc == 0 ? @"CCOPENSSH Applied" : @"CCOPENSSH Error" message:message];
    });
}

- (void)respring:(id)sender {
    (void)sender;
    [self saveVisibleEditors];
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"CCOPENSSH" message:@"Respringing..." preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [self runSync:@"respring"];
        });
    }];
}

@end
