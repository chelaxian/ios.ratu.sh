#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <notify.h>
static NSString *const ABDomain=@"com.ratush.appabetical";
static NSString *const ABCommandNotification=@"com.ratush.appabetical.command";
static NSString *const ABResponseNotification=@"com.ratush.appabetical.response";
static NSString *const ABReloadNotification=@"com.ratush.appabetical.reload";
static id ABReadPreference(NSString *key) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)ABDomain);
    return CFBridgingRelease(CFPreferencesCopyAppValue((__bridge CFStringRef)key,(__bridge CFStringRef)ABDomain));
}
static BOOL ABWritePreference(NSString *key,id value) {
    CFPreferencesSetAppValue((__bridge CFStringRef)key,(__bridge CFPropertyListRef)value,(__bridge CFStringRef)ABDomain);
    return CFPreferencesAppSynchronize((__bridge CFStringRef)ABDomain);
}
static NSDictionary *ABSettings(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)ABDomain);
    id values=CFBridgingRelease(CFPreferencesCopyMultiple(NULL,(__bridge CFStringRef)ABDomain,kCFPreferencesCurrentUser,kCFPreferencesAnyHost));
    return [values isKindOfClass:NSDictionary.class] ? values : @{};
}
static BOOL ABBool(NSDictionary *settings,NSString *key,BOOL fallback) {
    id value=settings[key]; return [value isKindOfClass:NSNumber.class] ? [value boolValue] : fallback;
}
