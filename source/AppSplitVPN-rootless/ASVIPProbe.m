#import "ASVIPProbe.h"
#import <objc/message.h>
#import <net/if.h>
#import <arpa/inet.h>
#import <ifaddrs.h>

static NSArray *Parse(NSData *data) {
    NSString *body=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if(!body.length)return nil;
    NSString *ip=nil,*country=nil;
    if([body containsString:@"ip="]){for(NSString *line in [body componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){
        if([line hasPrefix:@"ip="])ip=[line substringFromIndex:3];
        else if([line hasPrefix:@"loc="])country=[line substringFromIndex:4];
    }}else{
        id json=[NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:nil];
        if([json isKindOfClass:NSString.class])ip=json;
        else if([json isKindOfClass:NSDictionary.class]){
            for(NSString *key in @[@"ip",@"query",@"ip_addr",@"address"])if([json[key] isKindOfClass:NSString.class]){ip=json[key];break;}
            for(NSString *key in @[@"country_code",@"countryCode",@"country",@"cc",@"loc"])if([json[key] isKindOfClass:NSString.class] && [json[key] length]==2){country=json[key];break;}
        }else ip=body;
    }
    ip=[ip stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" \t\r\n\""]];unsigned char buffer[16];
    if(!ip.length || (inet_pton(AF_INET,ip.UTF8String,buffer)!=1 && inet_pton(AF_INET6,ip.UTF8String,buffer)!=1))return nil;
    country=country.uppercaseString;BOOL letters=country.length==2;
    for(NSUInteger i=0;letters && i<2;i++)letters=[country characterAtIndex:i]>='A' && [country characterAtIndex:i]<='Z';
    return letters?@[ip,country]:@[ip];
}
static BOOL AddressOnInterface(NSString *address,NSString *interface){
    if(!address.length || !interface.length)return NO;
    unsigned char expected[16]={0};int family=inet_pton(AF_INET,address.UTF8String,expected)==1?AF_INET:AF_INET6;
    if(family==AF_INET6 && inet_pton(AF_INET6,[[address componentsSeparatedByString:@"%"] firstObject].UTF8String,expected)!=1)return NO;
    struct ifaddrs *list=NULL;BOOL matched=NO;
    if(getifaddrs(&list)==0){for(struct ifaddrs *item=list;item;item=item->ifa_next){
        if(!item->ifa_addr || strcmp(item->ifa_name,interface.UTF8String) || item->ifa_addr->sa_family!=family)continue;
        const void *actual=family==AF_INET?(const void *)&((struct sockaddr_in *)item->ifa_addr)->sin_addr:(const void *)&((struct sockaddr_in6 *)item->ifa_addr)->sin6_addr;
        if(!memcmp(expected,actual,family==AF_INET?4:16)){matched=YES;break;}
    }freeifaddrs(list);}return matched;
}
@interface ASVIPRequest : NSObject<NSURLSessionDataDelegate,NSURLSessionTaskDelegate>
@property NSURLSession *session;
@property NSMutableData *data;
@property(copy) void (^done)(NSArray *,NSString *);
@property NSString *interface;
@property unsigned index;
@property NSString *localAddress;
@property BOOL responseOK;
@property BOOL networkLoad;
@property BOOL tooLarge;
@end
@implementation ASVIPRequest
- (void)URLSession:(__unused NSURLSession *)session dataTask:(__unused NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response completionHandler:(void(^)(NSURLSessionResponseDisposition))completion {
    _responseOK=[response isKindOfClass:NSHTTPURLResponse.class] && ((NSHTTPURLResponse *)response).statusCode==200;
    completion(_responseOK?NSURLSessionResponseAllow:NSURLSessionResponseCancel);
}
- (void)URLSession:(__unused NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if(_data.length+data.length>32768){_tooLarge=YES;[task cancel];return;}[_data appendData:data];
}
- (void)URLSession:(__unused NSURLSession *)session task:(__unused NSURLSessionTask *)task willPerformHTTPRedirection:(__unused NSHTTPURLResponse *)response newRequest:(__unused NSURLRequest *)request completionHandler:(void(^)(NSURLRequest *))completion{completion(nil);}
- (void)URLSession:(__unused NSURLSession *)session task:(__unused NSURLSessionTask *)task didFinishCollectingMetrics:(NSURLSessionTaskMetrics *)metrics {
    NSURLSessionTaskTransactionMetrics *last=metrics.transactionMetrics.lastObject;
    _localAddress=last.localAddress;_networkLoad=last.resourceFetchType==NSURLSessionTaskMetricsResourceFetchTypeNetworkLoad;
}
- (void)URLSession:(__unused NSURLSession *)session task:(__unused NSURLSessionTask *)task didCompleteWithError:(NSError *)failure {
    if(!_done)return;
    NSString *error=failure?[NSString stringWithFormat:@"request %ld",(long)failure.code]:nil;
    if(_tooLarge)error=@"response too large";
    if(!_responseOK)error=error ?: @"invalid HTTP response";
    if(!_networkLoad || !AddressOnInterface(_localAddress,_interface) || if_nametoindex(_interface.UTF8String)!=_index)error=error ?: @"unverified tunnel route";
    NSArray *parsed=error?nil:Parse(_data);
    void(^reply)(NSArray *,NSString *)=_done;_done=nil;
    [_session finishTasksAndInvalidate];_session=nil;_data=nil;
    dispatch_async(dispatch_get_main_queue(),^{reply(parsed,parsed?nil:(error ?: @"invalid IP response"));});
}
@end
void ASVIPProbe(NSString *interface,NSString *application,NSString *service,void(^completion)(NSArray *,NSString *)) {
    NSURL *url=[NSURL URLWithString:service];unsigned index=interface.length?if_nametoindex(interface.UTF8String):0;
    BOOL tls=[url.scheme.lowercaseString isEqual:@"https"];
    NSURLSessionConfiguration *config=[NSURLSessionConfiguration ephemeralSessionConfiguration];
    SEL source=NSSelectorFromString(@"set_sourceApplicationBundleIdentifier:"),virtual=NSSelectorFromString(@"set_allowsVirtualInterfaces:");
    if(!index || !application.length || ![config respondsToSelector:source] || ![config respondsToSelector:virtual] || !url.host.length || (!tls && ![url.scheme.lowercaseString isEqual:@"http"]) || url.user.length || url.password.length){completion(nil,@"unavailable attributed probe");return;}
    // Use the selected app's native per-app routing policy; do not create new NECP rules.
    // Accept a result only when NSURLSession metrics confirm the target utun's source IP.
    ((void(*)(id,SEL,id))objc_msgSend)(config,source,application);
    ((void(*)(id,SEL,BOOL))objc_msgSend)(config,virtual,YES);
    config.timeoutIntervalForRequest=8;config.timeoutIntervalForResource=10;
    config.requestCachePolicy=NSURLRequestReloadIgnoringLocalCacheData;config.URLCache=nil;
    ASVIPRequest *probe=[ASVIPRequest new];probe.interface=interface;probe.index=index;probe.done=completion;probe.data=[NSMutableData new];
    NSOperationQueue *queue=[NSOperationQueue new];queue.maxConcurrentOperationCount=1;
    probe.session=[NSURLSession sessionWithConfiguration:config delegate:probe delegateQueue:queue];
    [[probe.session dataTaskWithURL:url] resume];
}
