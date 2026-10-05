#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <notify.h>
#import <unistd.h>

static NSString *const OFDomain = @"com.level3tjg.offloaderprefs";
static NSString *const OFAntiDomain = @"com.level3tjg.offloader.anti";
static const char *OFChanged = "com.level3tjg.offloader/settings.changed";
static const char *OFCommand = "com.ratush.offloader.command";
static const char *OFResponse = "com.ratush.offloader.response";
#ifndef OF_PROTECTION_PATH
#define OF_PROTECTION_PATH @"/var/mobile/Library/Preferences/com.ratush.offloader.protection-snapshot.plist"
#endif

// Private calls and hooks must match the actual ABI before an IMP is used.
// Arguments exclude self/_cmd. b = bool, q = 64 bit integer, k = block.
static BOOL OFTypeMatches(const char *type, char expected) {
    if (!type) return NO;
    while (strchr("rnNoORV", *type) && *type) ++type;
    if (expected == 'b') return *type == 'B' || *type == 'c';
    if (expected == 'q') return *type == 'Q' || *type == 'q';
    if (expected == 'k') return type[0] == '@' && type[1] == '?';
    return *type == expected;
}
static BOOL OFMethodMatches(Method method, char result, const char *arguments) {
    if (!method || method_getNumberOfArguments(method) != strlen(arguments) + 2) return NO;
    char *type = method_copyReturnType(method);
    BOOL matches = OFTypeMatches(type, result); free(type);
    for (unsigned i = 0; matches && arguments[i]; ++i) {
        type = method_copyArgumentType(method, i + 2);
        matches = OFTypeMatches(type, arguments[i]); free(type);
    }
    return matches;
}
static BOOL OFCanCall(id object, SEL selector, char result, const char *arguments) {
    return object && OFMethodMatches(class_getInstanceMethod(object_getClass(object), selector), result, arguments);
}
static id OFObject(id object, SEL selector) {
    return OFCanCall(object, selector, '@', "") ? ((id(*)(id,SEL))[object methodForSelector:selector])(object,selector) : nil;
}
static NSString *OFString(id object, SEL selector) {
    id result = OFObject(object, selector);
    return [result isKindOfClass:NSString.class] ? result : nil;
}
static BOOL OFBool(id object, SEL selector) {
    return OFCanCall(object,selector,'b',"") && ((BOOL(*)(id,SEL))[object methodForSelector:selector])(object,selector);
}
static BOOL OFValidID(id identifier) {
    if (![identifier isKindOfClass:NSString.class] || [identifier length] == 0 || [identifier length] > 255) return NO;
    return [(NSString *)identifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"] invertedSet]].location == NSNotFound;
}
static BOOL OFValueBool(id value, BOOL fallback) {
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
static BOOL OFRequestValid(id request, NSDate *now) {
    if (![request isKindOfClass:NSDictionary.class]) return NO;
    NSDate *date = request[@"date"];
    return OFValidID(request[@"id"]) && OFValidID(request[@"bundle"]) && [date isKindOfClass:NSDate.class] &&
        [now timeIntervalSinceDate:date] <= 45 && [now timeIntervalSinceDate:date] >= -5;
}
static BOOL OFResponseMatches(id response, NSString *identifier) {
    return [response isKindOfClass:NSDictionary.class] && OFValidID(identifier) && [response[@"id"] isEqual:identifier] &&
        [response[@"ok"] isKindOfClass:NSNumber.class] && [response[@"message"] isKindOfClass:NSString.class];
}
static NSDictionary *OFPreferences(NSString *domain) {
    CFPreferencesSynchronize((__bridge CFStringRef)domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    id value = CFBridgingRelease(CFPreferencesCopyMultiple(NULL,(__bridge CFStringRef)domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
    return [value isKindOfClass:NSDictionary.class] ? value : @{};
}
static BOOL OFWrite(NSString *domain, NSString *key, id value) {
    CFPreferencesSetValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,(__bridge CFStringRef)domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
    return CFPreferencesSynchronize((__bridge CFStringRef)domain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost);
}
static NSDictionary *OFSanitizedProtection(NSDictionary *input) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (![input isKindOfClass:NSDictionary.class]) return result;
    for (id key in input) if (OFValidID(key) && OFValueBool(input[key],NO)) result[key] = @YES;
    return result;
}
static BOOL OFWriteProtectionSnapshot(NSDictionary *protection, NSError **error) {
    NSString *directory = [OF_PROTECTION_PATH stringByDeletingLastPathComponent];
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:error]) return NO;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:OFSanitizedProtection(protection) format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    if (!data || ![data writeToFile:OF_PROTECTION_PATH options:NSDataWritingAtomic error:error]) return NO;
    return [NSFileManager.defaultManager setAttributes:@{NSFilePosixPermissions:@0644} ofItemAtPath:OF_PROTECTION_PATH error:error];
}
static NSDictionary *OFProtection(void) {
    // A root daemon must read mobile's selection, never root's defaults suite.
    NSDictionary *snapshot = [NSDictionary dictionaryWithContentsOfFile:OF_PROTECTION_PATH];
    if ([snapshot isKindOfClass:NSDictionary.class]) return OFSanitizedProtection(snapshot);
    CFStringRef user = geteuid() == 501 ? kCFPreferencesCurrentUser : CFSTR("mobile");
    CFPreferencesSynchronize((__bridge CFStringRef)OFAntiDomain,user,kCFPreferencesAnyHost);
    NSDictionary *fallback = CFBridgingRelease(CFPreferencesCopyMultiple(NULL,(__bridge CFStringRef)OFAntiDomain,user,kCFPreferencesAnyHost));
    return OFSanitizedProtection(fallback);
}
static BOOL OFProtected(NSString *identifier) { return OFValidID(identifier) && [OFProtection()[identifier] boolValue]; }
static NSError *OFError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"com.ratush.offloader" code:code userInfo:@{NSLocalizedDescriptionKey:message ?: @"Offload failed"}];
}
static NSString *OFText(NSString *english, NSString *russian) {
    return [NSLocale.preferredLanguages.firstObject hasPrefix:@"ru"] ? russian : english;
}
typedef NS_ENUM(NSInteger, OFActionKind) { OFActionOther, OFActionOffload, OFActionDelete, OFActionEdit };
static OFActionKind OFKind(NSString *identifier, NSString *title, BOOL nativeDelete) {
    if ([identifier isEqual:@"com.level3tjg.offloader/offload"]) return OFActionOffload;
    NSString *type = identifier.lowercaseString ?: @"";
    // Match system identifiers, not arbitrary application actions containing "delete".
    if (nativeDelete || [@[@"delete-app",@"remove-app",@"com.level3tjg.offloader/delete"] containsObject:type] ||
        ([type hasPrefix:@"com.apple."] && ([type hasSuffix:@"delete-app"] || [type hasSuffix:@"remove-app"] || [type hasSuffix:@"deleteapp"] || [type hasSuffix:@"removeapp"] || [type hasSuffix:@".delete"] || [type hasSuffix:@".remove"]))) return OFActionDelete;
    if ([@[@"rearrange-icons",@"edit-home-screen",@"com.level3tjg.offloader/edit"] containsObject:type] ||
        ([type hasPrefix:@"com.apple."] && ([type hasSuffix:@"rearrange-icons"] || [type hasSuffix:@"edit-home-screen"] || [type hasSuffix:@"edithomescreen"] || [type hasSuffix:@"rearrangeicons"] || [type hasSuffix:@".edit"]))) return OFActionEdit;
    if ([type hasPrefix:@"com.apple."] || type.length == 0 || [[NSUUID alloc] initWithUUIDString:type]) {
        if ([@[@"Delete App",@"Remove App",@"Удалить приложение"] containsObject:title]) return OFActionDelete;
        if ([@[@"Edit Home Screen",@"Изменить экран «Домой»",@"Изменить экран Домой"] containsObject:title]) return OFActionEdit;
    }
    return OFActionOther;
}
static BOOL OFShowKind(OFActionKind kind, NSDictionary *settings) {
    NSString *key = kind == OFActionOffload ? @"3doffload" : kind == OFActionDelete ? @"3ddelete" : kind == OFActionEdit ? @"3dedit" : nil;
    return !key || OFValueBool(settings[key],YES);
}
