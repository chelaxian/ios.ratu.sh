#import "ASVSystemDNS.h"
#import <Network/Network.h>
#import <Network/resolver_config.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <arpa/inet.h>

@interface NSObject (ASVDNSRuntime)
+ (void)loadAllFromPreferencesWithCompletionHandler:(void (^)(NSArray *))handler;
@end
static id Get(id obj, NSString *name) {
    SEL sel=NSSelectorFromString(name);
    return [obj respondsToSelector:sel]?((id(*)(id,SEL))objc_msgSend)(obj,sel):nil;
}
static NSInteger Number(id obj, NSString *name) {
    SEL sel=NSSelectorFromString(name);
    return [obj respondsToSelector:sel]?((NSInteger(*)(id,SEL))objc_msgSend)(obj,sel):0;
}
static void (*setIdentifier)(nw_resolver_config_t,const uuid_t);
static void (*setClass)(nw_resolver_config_t,unsigned);
static void (*addDomain)(nw_resolver_config_t,const char *);
static bool (*publishConfig)(nw_resolver_config_t);
static void (*unpublishConfig)(nw_resolver_config_t);
@interface ASVDNSPublished : NSObject
@property(strong) nw_resolver_config_t resolver;
@property BOOL published;
@end
@implementation ASVDNSPublished
- (void)dealloc { if (_published && _resolver && unpublishConfig) unpublishConfig(_resolver); }
@end

static NSArray *rules, *descriptors;
static NSString *warning;
static BOOL active, loading;
static NSUInteger generation;
static NSTimeInterval lastLoad;
NSArray *ASVSystemDNSRules(void) { return rules ?: @[]; }
NSString *ASVSystemDNSWarning(void) { return warning ?: @""; }
static BOOL Host(NSString *name) {
    if (![name isKindOfClass:NSString.class] || !name.length || name.length>253) return NO;
    NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-:"];
    return [name rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound;
}
static NSString *Domain(id value) {
    if (![value isKindOfClass:NSString.class]) return nil;
    NSString *domain=[value lowercaseString];
    if([domain hasPrefix:@"*."])domain=[domain substringFromIndex:2];
    while([domain hasPrefix:@"."])domain=[domain substringFromIndex:1];
    return (!domain.length || Host(domain))?domain:nil;
}
static NSArray *Exclusions(id manager) {
    NSArray *onDemand=Get(manager,@"onDemandRules");
    if (![onDemand isKindOfClass:NSArray.class] || !onDemand.count) return @[];
    // Do not silently override SSID/interface/probe/domain on-demand restrictions.
    NSMutableOrderedSet *excluded=[NSMutableOrderedSet new];BOOL connect=NO;
    for(id r in onDemand){
        if(Number(r,@"interfaceTypeMatch")!=0 || [Get(r,@"SSIDMatch") count] || [Get(r,@"DNSSearchDomainMatch") count] || [Get(r,@"DNSServerAddressMatch") count] || Get(r,@"probeURL"))return nil;
        NSInteger action=Number(r,@"action");
        if(action==1){if(r!=onDemand.lastObject)return nil;connect=YES;continue;}
        if(action!=3)return nil;
        NSArray *connections=Get(r,@"connectionRules");if(![connections isKindOfClass:NSArray.class])return nil;
        for(id c in connections){
            if(Number(c,@"action")!=2 || [Get(c,@"useDNSServers") count] || Get(c,@"probeURL"))return nil;
            NSArray *domains=Get(c,@"matchDomains");if(![domains isKindOfClass:NSArray.class])return nil;
            for(id value in domains){NSString *domain=Domain(value);if(!domain || !domain.length || excluded.count>=512)return nil;[excluded addObject:domain];}
        }
    }
    return connect?excluded.array:nil;
}
static NSArray *Describe(NSArray *managers, NSUInteger *skipped) {
    NSMutableArray *out=[NSMutableArray new];
    for (id m in managers) { @try {
        if (!Number(m,@"isEnabled")) continue;
        id dns=Get(m,@"dnsSettings");NSInteger protocol=Number(dns,@"dnsProtocol");
        if (protocol!=2 && protocol!=3) continue;
        if (Get(dns,@"identityReference") || Get(dns,@"proxyAgentUUID")) { (*skipped)++;continue; }
        NSArray *excluded=Exclusions(m);
        if (out.count>=32 || !excluded) { (*skipped)++;continue; }
        NSArray *raw=Get(dns,@"matchDomains");
        if (raw && ![raw isKindOfClass:NSArray.class]) { (*skipped)++;continue; }
        NSMutableOrderedSet *domains=[NSMutableOrderedSet new];BOOL valid=YES;
        for (id value in raw) {
            NSString *domain=Domain(value);
            if (!domain) { valid=NO;break; }
            [domains addObject:domain];
        }
        if (!valid || domains.count>512) { (*skipped)++;continue; }
        if (!domains.count) [domains addObject:@""];
        NSArray *servers=Get(dns,@"servers") ?: @[]; // A DoH profile may specify only its URL.
        if (![servers isKindOfClass:NSArray.class] || servers.count>32) { (*skipped)++;continue; }
        NSMutableArray *addresses=[NSMutableArray new];
        for (id s in servers) { unsigned char bytes[16];
            if (![s isKindOfClass:NSString.class] || (inet_pton(AF_INET,[s UTF8String],bytes)!=1 && inet_pton(AF_INET6,[s UTF8String],bytes)!=1)) {valid=NO;break;}
            [addresses addObject:s];
        }
        NSURL *url=protocol==3?Get(dns,@"serverURL"):nil;
        NSString *name=protocol==2?Get(dns,@"serverName"):@"";
        if (protocol==3 && (![url isKindOfClass:NSURL.class] || ![url.scheme.lowercaseString isEqual:@"https"] || !url.host.length)) valid=NO;
        if (protocol==2 && !Host(name)) valid=NO;
        if (!valid) { (*skipped)++;continue; }
        [out addObject:@{@"protocol":@(protocol),@"url":url.absoluteString ?: @"",@"name":name ?: @"",@"servers":addresses,@"domains":domains.array,@"excluded":excluded}];
    } @catch (__unused NSException *e) { (*skipped)++; } }
    return out;
}
static NSArray *Build(NSArray *source) {
    NSMutableArray *out=[NSMutableArray new];
    for (NSDictionary *d in source) {
        BOOL https=[d[@"protocol"] integerValue]==3;
        nw_endpoint_t ep=https?nw_endpoint_create_url([d[@"url"] UTF8String]):nw_endpoint_create_host([d[@"name"] UTF8String],"853");
        nw_resolver_config_t config=ep?(https?nw_resolver_config_create_https(ep):nw_resolver_config_create_tls(ep)):nil;
        if (!config) return nil;
        for (NSString *s in d[@"servers"]) {
            NSURL *url=https?[NSURL URLWithString:d[@"url"]]:nil;
            NSString *port=https?(url.port.stringValue ?: @"443"):@"853";
            nw_endpoint_t server=nw_endpoint_create_host(s.UTF8String,port.UTF8String);
            if (server) nw_resolver_config_add_server_address(config,server);
        }
        NSUUID *agent=NSUUID.UUID;uuid_t bytes;[agent getUUIDBytes:bytes];
        setIdentifier(config,bytes);setClass(config,2); // native designated-direct resolver
        for (NSString *domain in d[@"domains"]) addDomain(config,domain.UTF8String);
        ASVDNSPublished *owner=[ASVDNSPublished new];owner.resolver=config;
        owner.published=publishConfig(config);if (!owner.published) return nil;
        for (NSString *domain in d[@"domains"]) [out addObject:@{@"agent":agent,@"domain":domain,@"owner":owner,@"excluded":d[@"excluded"]}];
    }
    // Specific DNS domains precede a catch-all profile; no app x domain explosion.
    [out sortUsingComparator:^NSComparisonResult(NSDictionary *a,NSDictionary *b){
        NSUInteger x=[a[@"domain"] length],y=[b[@"domain"] length];
        return x>y?NSOrderedAscending:(x<y?NSOrderedDescending:NSOrderedSame);
    }];
    return out;
}
void ASVSystemDNSTick(BOOL enabled,void (^changed)(void)) {
    if (!enabled) {
        if (active) { active=NO;generation++;loading=NO;rules=nil;descriptors=nil;warning=nil;lastLoad=0; }
        return;
    }
    active=YES;
    NSTimeInterval now=NSDate.date.timeIntervalSince1970;
    if (loading || now-lastLoad<30) return;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        setIdentifier=dlsym(RTLD_DEFAULT,"nw_resolver_config_set_identifier");setClass=dlsym(RTLD_DEFAULT,"nw_resolver_config_set_class");
        addDomain=dlsym(RTLD_DEFAULT,"nw_resolver_config_add_match_domain");publishConfig=dlsym(RTLD_DEFAULT,"nw_resolver_config_publish");unpublishConfig=dlsym(RTLD_DEFAULT,"nw_resolver_config_unpublish");
    });
    Class manager=NSClassFromString(@"NEDNSSettingsManager");
    if (!setIdentifier || !setClass || !addDomain || !publishConfig || !unpublishConfig || ![manager respondsToSelector:@selector(loadAllFromPreferencesWithCompletionHandler:)]) {
        warning=@"System encrypted DNS API unavailable";lastLoad=now;return;
    }
    loading=YES;lastLoad=now;NSUInteger token=++generation;
    // Native API has ONE NSArray callback argument on iOS 17, not an NSError pair.
    [manager loadAllFromPreferencesWithCompletionHandler:^(NSArray *list){dispatch_async(dispatch_get_main_queue(),^{
        if (!active || token!=generation) return;
        loading=NO;NSUInteger skipped=0;
        NSArray *next=Describe([list isKindOfClass:NSArray.class]?list:@[],&skipped);
        NSString *note=skipped?@"Some DNS profiles have unsupported conditions":(next.count?@"":@"No supported enabled DoH/DoT profile");
        BOOL different=![next isEqual:descriptors] || ![note isEqual:warning];
        if (different) {
            NSArray *candidate=Build(next);
            if (candidate) { rules=candidate;descriptors=next;warning=note; }
            else { rules=nil;descriptors=nil;warning=@"Encrypted DNS resolver registration failed"; }
            if (changed) changed();
        }
    });}];
    // A missing callback must not block refresh forever; late replies are ignored.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_SEC),dispatch_get_main_queue(),^{if (active && loading && token==generation){loading=NO;generation++;warning=@"System DNS profile lookup timed out";if(changed)changed();}});
}
