#import "ASVSupervisor.h"
#import "Shared.h"
#import "ASVProfiles.h"
#import "RecoveryCore.h"
#import "MediaCore.h"
#import <Network/Network.h>
#import <arpa/inet.h>
#import <dlfcn.h>
#import <ifaddrs.h>
#import <net/if.h>
#import <netdb.h>
#import <netinet/in.h>
#import <netinet/icmp6.h>
#import <netinet/ip_icmp.h>
#import <notify.h>
#import <objc/message.h>
#import <poll.h>
#import <sys/stat.h>
#import <unistd.h>
#import <uuid/uuid.h>
#import <stdatomic.h>

typedef void *ASVNESession;
static ASVNESession (*neCreate)(const unsigned char *,int);
static void (*neStart)(ASVNESession);
static void (*neStop)(ASVNESession);
static void (*neGetStatus)(ASVNESession,dispatch_queue_t,void (^)(int));
static void (*neRelease)(ASVNESession);
static int (*neAnyActive)(void);
enum { ASVStatusDisconnected=1, ASVStatusConnecting=2, ASVStatusConnected=3, ASVStatusReasserting=4, ASVStatusDisconnecting=5 };

static NSUUID *sessionUUID;
static ASVNESession session;
static NSUUID *configUUID;
static NSString *configName;
static NSString *configApp;
static NSTimeInterval lastConfigLoad;
static BOOL configLoading;
static int lockToken=-1;
static int uiLockToken=-1;
static BOOL locked;
static NSTimeInterval lockedAt;
static void (*mediaIsPlaying)(dispatch_queue_t,void (^)(BOOL));
static BOOL mediaKnown, mediaPlaying, mediaPending, mediaHeld;
static NSTimeInterval mediaPollAt, mediaUpdatedAt;
static NSUInteger mediaGeneration;
static NSUUID *lsStoppedUUID;
static BOOL wasActive;
static NSTimeInterval activeSince, downSince, nextStartAllowed, nextHealth, statusRequestedAt;
static NSInteger startFailures, healthFails;
static BOOL probing, statusPending, dirty=YES, logDirty;
static NSString *healthText;
static NSMutableArray<NSDictionary *> *events;
static int vpnStatus;
static NSTimeInterval lastStatusPoll;
static BOOL statusPolling;
static int clearToken=-1;
static NSDictionary *prefsCache;
static ASVRecovery recovery;
static NSMutableSet *failedReserves;
static NSString *pendingReserve,*pinnedProfile;
static BOOL profileStarting, circuitLatched;
static NSTimeInterval connectDeadline;
static BOOL lastAutomation;
static BOOL lastRedundancy;
static NSString *lastPrimary,*reserveCycleProfile;
static unsigned reserveCycles;
static struct timespec prefsStamp;
static BOOL transactionPaused;
static BOOL masterEnabled, masterKnown;
static NSTimeInterval Now(void);
static NSUInteger automationGeneration;
static _Atomic unsigned long probeGeneration;
static dispatch_block_t cancelProbe;
void ASVSupervisorSetTransactionPaused(BOOL paused){transactionPaused=paused;}
void ASVSupervisorSetEnabled(BOOL enabled){
    if(masterKnown && masterEnabled==enabled)return;
    masterEnabled=enabled;masterKnown=YES;
    if(enabled){lockedAt=[NSDate date].timeIntervalSince1970;dirty=YES;return;}
    ++automationGeneration;atomic_fetch_add(&probeGeneration,1);
    if(cancelProbe){cancelProbe();cancelProbe=nil;}
    probing=NO;statusPending=NO;profileStarting=NO;pendingReserve=nil;pinnedProfile=nil;
    connectDeadline=0;lsStoppedUUID=nil;mediaHeld=NO;mediaKnown=NO;mediaPending=NO;++mediaGeneration;lastConfigLoad=0;
    recovery=(ASVRecovery){0};[failedReserves removeAllObjects];lastAutomation=NO;
    lastRedundancy=NO;reserveCycles=0;reserveCycleProfile=nil;
    healthFails=0;startFailures=0;healthText=nil;nextHealth=Now()+30;nextStartAllowed=Now()+3;
    dirty=YES;
}

static NSTimeInterval Now(void) { return [NSDate date].timeIntervalSince1970; }
static id Send(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return object && [object respondsToSelector:selector] ? ((id(*)(id,SEL))objc_msgSend)(object,selector) : nil;
}
static BOOL SendBool(id object,NSString *name) {
    SEL selector=NSSelectorFromString(name);
    return object && [object respondsToSelector:selector] ? ((BOOL(*)(id,SEL))objc_msgSend)(object,selector) : NO;
}
static BOOL VPNActive(void) { return neAnyActive && neAnyActive()!=0; }

static NSDictionary *Prefs(void) {
    struct stat st;
    if (stat(ASV_PREFS.fileSystemRepresentation,&st)!=0) { prefsCache=@{};memset(&prefsStamp,0,sizeof prefsStamp);return prefsCache; }
    if (!prefsCache || st.st_mtimespec.tv_sec!=prefsStamp.tv_sec || st.st_mtimespec.tv_nsec!=prefsStamp.tv_nsec) {
        prefsCache=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{};
        prefsStamp=st.st_mtimespec;
    }
    return prefsCache;
}
static BOOL MediaProtected(NSDictionary *prefs) {
    // Never disconnect on an unavailable or stale observation of playback.
    return ASVMediaShouldHold(locked,ASVExtraOptionActive(prefs,ASV_LS_DISCONNECT),[prefs[ASV_LS_MEDIA] boolValue],mediaKnown,mediaPlaying,Now()-mediaUpdatedAt);
}
static BOOL Suspended(NSDictionary *prefs) { return locked && ASVExtraOptionActive(prefs,ASV_LS_DISCONNECT) && !MediaProtected(prefs); }

static void PollMedia(NSDictionary *prefs,NSTimeInterval now) {
    if(!locked || !ASVExtraOptionActive(prefs,ASV_LS_DISCONNECT) || ![prefs[ASV_LS_MEDIA] boolValue])return;
    if(!mediaIsPlaying || (mediaPending && now-mediaPollAt<6) || now-mediaPollAt<2)return;
    mediaPending=YES;mediaPollAt=now;
    NSUInteger generation=++mediaGeneration;
    mediaIsPlaying(dispatch_get_main_queue(),^(BOOL playing){
        if(generation!=mediaGeneration)return;
        mediaPending=NO;mediaKnown=YES;mediaPlaying=playing;mediaUpdatedAt=Now();dirty=YES;
    });
}

static void Event(NSString *code,NSString *detail) {
    [events addObject:@{@"time":@(Now()),@"code":code,@"detail":detail ?: @""}];
    if (events.count>ASV_EXTRA_LOG_LIMIT) [events removeObjectsInRange:NSMakeRange(0,events.count-ASV_EXTRA_LOG_LIMIT)];
    logDirty=YES;
    fprintf(stderr,"AppSplitVPN extra %s %s\n",code.UTF8String,(detail ?: @"").UTF8String);
}
static void WriteState(void) {
    if (logDirty) {
        logDirty=NO;
        [events writeToFile:ASV_EXTRA_LOG atomically:YES];
        chmod(ASV_EXTRA_LOG.fileSystemRepresentation,0644);
    }
    if (!dirty) return;
    dirty=NO;
    NSDictionary *state=@{@"health":healthText ?: @"",@"healthFails":@(healthFails),
        @"locked":@(locked),@"mediaHeld":@(mediaHeld),@"lsStopped":lsStoppedUUID.UUIDString ?: @"",@"vpnName":configName ?: @"",
        @"vpnApp":configApp ?: @"",@"vpnStatus":@(vpnStatus),@"vpnActive":@(wasActive),@"updated":@(Now()),
        @"failedCycles":@(recovery.cycles),@"cycleHealthy":@(recovery.healthy),@"reserveCycles":@(reserveCycles),@"reserveCycleProfile":reserveCycleProfile ?: @"",@"failedReserves":failedReserves.allObjects ?: @[],@"pinnedProfile":pinnedProfile ?: @"",@"circuitLatched":@(circuitLatched)};
    [state writeToFile:ASV_EXTRA_STATE atomically:YES];
    chmod(ASV_EXTRA_STATE.fileSystemRepresentation,0644);
    notify_post(ASV_EXTRA_NOTIFY);
}

#pragma mark - Sessions

static ASVNESession SessionFor(NSUUID *uuid) {
    if (!uuid || !neCreate) return NULL;
    if (session && [sessionUUID isEqual:uuid]) return session;
    if (session && neRelease) neRelease(session);
    uuid_t bytes;
    [uuid getUUIDBytes:bytes];
    session=neCreate(bytes,1);
    sessionUUID=session ? uuid : nil;
    return session;
}
static BOOL Control(NSUUID *uuid,BOOL start) {
    NSDictionary *prefs=Prefs();
    if(!masterEnabled || transactionPaused || ![prefs[@"enabled"] boolValue] || ASVIsMultiMode(prefs))return NO;
    ASVNESession target=SessionFor(uuid);
    void (*action)(ASVNESession)=start ? neStart : neStop;
    if (!target || !action) return NO;
    action(target);
    return YES;
}
// iOS keeps exactly one VPN configuration selected: the last one the user
// connected. That selection is the "last active VPN" for every VPN client.
static void LoadConfiguration(void) {
    if (configLoading) return;
    Class cls=NSClassFromString(@"NEConfigurationManager");
    id manager=Send(cls,@"sharedManager") ?: Send(cls,@"defaultManager");
    SEL selector=NSSelectorFromString(@"loadConfigurationsWithCompletionQueue:handler:");
    if (!manager || ![manager respondsToSelector:selector]) return;
    configLoading=YES;
    lastConfigLoad=Now();
    ((void(*)(id,SEL,dispatch_queue_t,id))objc_msgSend)(manager,selector,dispatch_get_main_queue(),^(NSArray *configs,__unused NSError *error){
        configLoading=NO;
        NSMutableArray *found=[NSMutableArray array];
        for (id cfg in configs) {
            if (!SendBool(cfg,@"isEnabled") || !Send(cfg,@"VPN")) continue;
            NSUUID *uuid=Send(cfg,@"identifier");
            NSString *name=Send(cfg,@"name");
            if (![uuid isKindOfClass:NSUUID.class]) continue;
            NSString *lower=[name isKindOfClass:NSString.class] ? name.lowercaseString : @"";
            if ([lower containsString:@"com.apple"] || [lower containsString:@"privaterelay"] || [lower containsString:@"networkprivacy"]) continue;
            // Owning app: the configuration's application, else the tunnel provider extension.
            NSString *app=Send(cfg,@"application");
            if (![app isKindOfClass:NSString.class] || !app.length) app=Send(Send(Send(cfg,@"VPN"),@"protocol"),@"providerBundleIdentifier");
            [found addObject:@[uuid,[name isKindOfClass:NSString.class] ? name : @"",[app isKindOfClass:NSString.class] ? app : @""]];
        }
        NSArray *chosen=found.firstObject;
        for (NSArray *item in found) if ([item[0] isEqual:configUUID]) chosen=item;
        if(pinnedProfile.length)for(NSArray *item in found)if([[item[0] UUIDString] isEqual:pinnedProfile])chosen=item;
        NSUUID *uuid=chosen[0];
        if (![uuid isEqual:configUUID] || ![chosen[1] isEqual:configName] || ![chosen[2] isEqual:configApp]) dirty=YES;
        configUUID=uuid;
        configName=chosen[1];
        configApp=chosen[2];
    });
}

#pragma mark - Interfaces

typedef struct { BOOL found; int family; unsigned index; char address[INET6_ADDRSTRLEN]; } ASVTunnel;
static BOOL GlobalIPv6(const struct in6_addr *a) { return (a->s6_addr[0]&0xE0)==0x20; }
// Resolve the selected protocol's service, not the newest utun. Otherwise an
// unrelated live VPN could make a broken reserve falsely pass its health check.
static ASVTunnel FindTunnel(void) {
    ASVTunnel best={0};
    NSString *expected=configUUID?ASVProfileInterface(configUUID.UUIDString):nil;
    if(!expected.length)return best;
    int bestScore=0;
    struct ifaddrs *list=NULL;
    if (getifaddrs(&list)!=0) return best;
    for (struct ifaddrs *item=list;item;item=item->ifa_next) {
        if (!item->ifa_addr || !(item->ifa_flags&IFF_UP)) continue;
        const char *name=item->ifa_name;
        if(strcmp(name,expected.UTF8String))continue;
        BOOL utun=!strncmp(name,"utun",4), other=!strncmp(name,"ipsec",5) || !strncmp(name,"ppp",3);
        if (!utun && !other) continue;
        int score=0;
        char text[INET6_ADDRSTRLEN]={0};
        if (item->ifa_addr->sa_family==AF_INET) {
            struct in_addr addr=((struct sockaddr_in *)item->ifa_addr)->sin_addr;
            uint32_t host=ntohl(addr.s_addr);
            if ((host&0xFFFFFF00)==0xC0000000 || (host&0xFFFF0000)==0xA9FE0000) continue;
            inet_ntop(AF_INET,&addr,text,sizeof text);
            score=utun?4:3;
        } else if (item->ifa_addr->sa_family==AF_INET6 && utun) {
            struct in6_addr addr=((struct sockaddr_in6 *)item->ifa_addr)->sin6_addr;
            if (!GlobalIPv6(&addr)) continue;
            inet_ntop(AF_INET6,&addr,text,sizeof text);
            score=2;
        } else continue;
        unsigned index=if_nametoindex(name);
        if (score>bestScore || (score==bestScore && index>best.index)) {
            bestScore=score;
            best.found=YES;best.family=item->ifa_addr->sa_family;best.index=index;
            strlcpy(best.address,text,sizeof best.address);
        }
    }
    freeifaddrs(list);
    return best;
}
static BOOL HasPhysicalNetwork(void) {
    BOOL found=NO;
    struct ifaddrs *list=NULL;
    if (getifaddrs(&list)!=0) return YES;
    for (struct ifaddrs *item=list;item && !found;item=item->ifa_next) {
        if (!item->ifa_addr || (item->ifa_flags&(IFF_UP|IFF_RUNNING))!=(IFF_UP|IFF_RUNNING)) continue;
        if (strncmp(item->ifa_name,"en",2) && strncmp(item->ifa_name,"pdp_ip",6)) continue;
        if (item->ifa_addr->sa_family==AF_INET) {
            uint32_t host=ntohl(((struct sockaddr_in *)item->ifa_addr)->sin_addr.s_addr);
            found=(host&0xFFFF0000)!=0xA9FE0000;
        } else if (item->ifa_addr->sa_family==AF_INET6) found=GlobalIPv6(&((struct sockaddr_in6 *)item->ifa_addr)->sin6_addr);
    }
    freeifaddrs(list);
    return found;
}

#pragma mark - Probes

typedef void (^ASVProbeDone)(BOOL ok,NSInteger ms,NSString *reason);
static dispatch_queue_t ProbeQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t once;
    dispatch_once(&once,^{ queue=dispatch_queue_create("com.ratush.appsplitvpn.health",DISPATCH_QUEUE_SERIAL); });
    return queue;
}
static uint16_t Checksum(const void *data,size_t length) {
    const uint16_t *words=data;
    uint32_t sum=0;
    for (;length>1;length-=2) sum+=*words++;
    if (length) sum+=*(const uint8_t *)words;
    while (sum>>16) sum=(sum&0xFFFF)+(sum>>16);
    return (uint16_t)~sum;
}
static NSString *Ping(NSString *host,ASVTunnel tunnel,NSInteger timeout,unsigned long generation) {
    struct addrinfo hints={0},*result=NULL;
    hints.ai_family=tunnel.family;hints.ai_socktype=SOCK_DGRAM;
    if (getaddrinfo(host.UTF8String,NULL,&hints,&result)!=0 || !result) return @"dns";
    if(generation!=atomic_load(&probeGeneration)){freeaddrinfo(result);return @"Cancelled";}
    BOOL v4=tunnel.family==AF_INET;
    int fd=socket(tunnel.family,SOCK_DGRAM,v4?IPPROTO_ICMP:IPPROTO_ICMPV6);
    if (fd<0) { freeaddrinfo(result);return @"socket"; }
    unsigned index=tunnel.index;
    setsockopt(fd,v4?IPPROTO_IP:IPPROTO_IPV6,v4?IP_BOUND_IF:IPV6_BOUND_IF,&index,sizeof index);
    uint16_t ident=(uint16_t)arc4random();
    NSString *reason=@"timeout";
    // Tunnels often answer ICMP slowly and drop some echoes: four tries, 2.5 s each.
    NSTimeInterval totalDeadline=Now()+timeout;
    for (uint16_t seq=1;seq<=4 && Now()<totalDeadline && generation==atomic_load(&probeGeneration);seq++) {
        uint8_t packet[24]={0};
        packet[0]=v4?ICMP_ECHO:ICMP6_ECHO_REQUEST;
        memcpy(packet+4,&ident,2);
        uint16_t netSeq=htons(seq);
        memcpy(packet+6,&netSeq,2);
        if (v4) { uint16_t sum=Checksum(packet,sizeof packet);memcpy(packet+2,&sum,2); }
        if (sendto(fd,packet,sizeof packet,0,result->ai_addr,result->ai_addrlen)<0) { reason=@"send";continue; }
        NSTimeInterval deadline=MIN(totalDeadline,Now()+MAX(0.25,timeout/4.0));
        while (Now()<deadline && generation==atomic_load(&probeGeneration)) {
            struct pollfd poller={fd,POLLIN,0};
            int ready=poll(&poller,1,(int)MIN(100,MAX(1,(deadline-Now())*1000)));
            if(ready<0)break;if(ready==0)continue;
            uint8_t reply[512];
            ssize_t length=recv(fd,reply,sizeof reply,0);
            if (length<8) continue;
            const uint8_t *icmp=reply;
            if (v4 && (reply[0]>>4)==4) { size_t header=(reply[0]&0x0F)*4;if ((size_t)length<header+8) continue;icmp=reply+header; }
            if (icmp[0]==(v4?ICMP_ECHOREPLY:ICMP6_ECHO_REPLY)) { close(fd);freeaddrinfo(result);return nil; }
        }
    }
    close(fd);
    freeaddrinfo(result);
    return reason;
}
static void Probe(NSString *method,NSString *host,NSInteger port,NSInteger timeout,ASVTunnel tunnel,ASVProbeDone done) {
    unsigned long generation=atomic_load(&probeGeneration);
    dispatch_queue_t queue=ProbeQueue();
    CFAbsoluteTime start=CFAbsoluteTimeGetCurrent();
    __block BOOL finished=NO;
    __block nw_connection_t connection=nil;
    void (^finish)(NSString *)=^(NSString *reason){
        if (finished) return;
        finished=YES;
        if (connection) nw_connection_cancel(connection);
        connection=nil;
        NSInteger ms=(NSInteger)((CFAbsoluteTimeGetCurrent()-start)*1000);
        dispatch_async(dispatch_get_main_queue(),^{ done(reason==nil,ms,reason); });
    };
    if ([method isEqual:@"ping"]) {
        dispatch_async(queue,^{ finish(Ping(host,tunnel,timeout,generation)); });
        return;
    }
    BOOL tls=[method isEqual:@"https"], http=tls || [method isEqual:@"http"];
    nw_parameters_t parameters=nw_parameters_create_secure_tcp(tls?NW_PARAMETERS_DEFAULT_CONFIGURATION:NW_PARAMETERS_DISABLE_PROTOCOL,NW_PARAMETERS_DEFAULT_CONFIGURATION);
    // A source address on the tunnel scopes the connection to it, whatever the routing table says.
    nw_parameters_set_local_endpoint(parameters,nw_endpoint_create_host(tunnel.address,"0"));
    nw_protocol_stack_t stack=nw_parameters_copy_default_protocol_stack(parameters);
    nw_protocol_options_t ip=nw_protocol_stack_copy_internet_protocol(stack);
    if (ip) nw_ip_options_set_version(ip,tunnel.family==AF_INET6?nw_ip_version_6:nw_ip_version_4);
    connection=nw_connection_create(nw_endpoint_create_host(host.UTF8String,[NSString stringWithFormat:@"%ld",(long)port].UTF8String),parameters);
    nw_connection_t current=connection;
    cancelProbe=^{dispatch_async(queue,^{finish(@"Cancelled");});};
    nw_connection_set_queue(current,queue);
    nw_connection_set_state_changed_handler(current,^(nw_connection_state_t state,nw_error_t error){
        if(generation!=atomic_load(&probeGeneration)){finish(@"Cancelled");return;}
        if (state==nw_connection_state_failed) finish(error?[NSString stringWithFormat:@"error %d",nw_error_get_error_code(error)]:@"failed");
        else if (state==nw_connection_state_waiting) finish(@"no route");
        else if (state==nw_connection_state_ready) {
            if (!http) { finish(nil);return; }
            NSString *request=[NSString stringWithFormat:@"HEAD / HTTP/1.1\r\nHost: %@\r\nUser-Agent: AppSplitVPN\r\nConnection: close\r\n\r\n",host];
            NSData *bytes=[request dataUsingEncoding:NSUTF8StringEncoding];
            nw_connection_send(current,dispatch_data_create(bytes.bytes,bytes.length,queue,DISPATCH_DATA_DESTRUCTOR_DEFAULT),NW_CONNECTION_DEFAULT_MESSAGE_CONTEXT,true,^(__unused nw_error_t sendError){});
            nw_connection_receive(current,5,1024,^(dispatch_data_t content,__unused nw_content_context_t context,__unused bool complete,__unused nw_error_t receiveError){
                __block BOOL valid=NO;
                if (content) dispatch_data_apply(content,^bool(__unused dispatch_data_t region,size_t offset,const void *buffer,size_t size){
                    if (offset==0 && size>=5) valid=!memcmp(buffer,"HTTP/",5);
                    return false;
                });
                finish(valid?nil:@"no HTTP reply");
            });
        }
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,timeout*NSEC_PER_SEC),queue,^{ finish(@"timeout"); });
    nw_connection_start(current);
}

#pragma mark - Supervisor

static void CircuitOpen(BOOL reserves,NSString *reason) {
    if(!masterEnabled || ![Prefs()[@"enabled"] boolValue])return;
    NSMutableDictionary *prefs=[Prefs() mutableCopy];prefs[ASV_ALWAYS_ON]=@NO;prefs[ASV_REDUNDANCY]=@NO;
    if(!reserves)prefs[ASV_HEALTH]=@NO;
    if([prefs writeToFile:ASV_PREFS atomically:YES]) { chown(ASV_PREFS.UTF8String,501,501);chmod(ASV_PREFS.UTF8String,0644);prefsCache=nil;notify_post(ASV_NOTIFY); }
    circuitLatched=YES;pendingReserve=nil;connectDeadline=0;profileStarting=NO;
    if(configUUID)Control(configUUID,NO);Event(@"circuitOpen",reason);dirty=YES;
}
static void FailedCycle(NSString *reason) {
    NSDictionary *prefs=Prefs();unsigned limit=(unsigned)ASVIntSetting(prefs,ASV_HC_FAILURES,3,1,10);
    BOOL exhausted=ASVRecoveryCycleFailed(&recovery,limit);
    Event(@"badCycle",[NSString stringWithFormat:@"%u/%u",recovery.cycles,limit]);dirty=YES;
    if(ASVExtraOptionActive(prefs,ASV_REDUNDANCY)) {
        if(![reserveCycleProfile isEqual:configUUID.UUIDString]){reserveCycleProfile=configUUID.UUIDString;reserveCycles=0;}
        unsigned switchLimit=(unsigned)ASVIntSetting(prefs,ASV_RED_CYCLES,1,1,10);
        BOOL rotate=ASVReserveCycleFailed(&reserveCycles,switchLimit);
        Event(@"reserveCycle",[NSString stringWithFormat:@"%u/%u %@",reserveCycles,switchLimit,configName ?: @""]);
        if(!rotate){nextStartAllowed=Now()+5;connectDeadline=0;return;}
        reserveCycles=0;reserveCycleProfile=nil;
        if(!failedReserves)failedReserves=[NSMutableSet set];if(configUUID)[failedReserves addObject:configUUID.UUIDString];
        NSArray *raw=[prefs[ASV_RESERVES] isKindOfClass:NSArray.class]?prefs[ASV_RESERVES]:@[];
        NSMutableOrderedSet *unique=[NSMutableOrderedSet orderedSet];for(id v in raw)if([v isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:v])[unique addObject:v];
        NSArray *candidates=unique.array;NSUInteger count=MIN((NSUInteger)64,candidates.count);uint64_t tried=0;unsigned after=count?(unsigned)count-1:0;
        for(unsigned i=0;i<count;i++){if([failedReserves containsObject:candidates[i]])tried|=UINT64_C(1)<<i;if([candidates[i] isEqual:configUUID.UUIDString])after=i;}
        int next=ASVReserveNext(tried,(unsigned)count,after,[prefs[ASV_RED_ALGORITHM] isEqual:@"random"],arc4random());
        if(next<0){CircuitOpen(YES,@"All reserve profiles failed; manual intervention required");return;}
        pendingReserve=candidates[next];nextStartAllowed=Now()+3;connectDeadline=0;
        Event(@"reserveSwitch",ASVProfileRecord(pendingReserve)[@"name"] ?: pendingReserve);
    } else if(exhausted && [prefs[ASV_ALWAYS_ON] boolValue]) CircuitOpen(NO,reason ?: @"No successful health check in consecutive recovery cycles");
}
static void StartReservedProfile(void) {
    NSUInteger generation=automationGeneration;
    NSString *uuid=pendingReserve;pendingReserve=nil;profileStarting=YES;pinnedProfile=uuid;
    NSDictionary *snapshot=Prefs();
    NSString *mode=[snapshot[@"mode"] copy];
    NSArray *reserves=[snapshot[ASV_RESERVES] copy];
    NSString *primary=[snapshot[ASV_PRIMARY] copy];
    BOOL (^valid)(void)=^BOOL{
        NSDictionary *current=Prefs();
        return generation==automationGeneration && masterEnabled && !transactionPaused && !circuitLatched && !ASVIsMultiMode(current) &&
            [current[@"mode"] isEqual:mode] &&
            [current[ASV_RESERVES] isEqual:reserves] &&
            ((current[ASV_PRIMARY]==nil && primary==nil) || [current[ASV_PRIMARY] isEqual:primary]) &&
            ASVExtraOptionActive(current,ASV_REDUNDANCY) &&
            ASVExtraOptionActive(current,ASV_ALWAYS_ON) &&
            ASVExtraOptionActive(current,ASV_HEALTH) && !Suspended(current);
    };
    ASVProfileConnect(uuid,valid,^(BOOL ok,NSString *error){
        if(generation!=automationGeneration)return;
        if(!valid() || [error isEqual:@"Cancelled"]){profileStarting=NO;pinnedProfile=nil;dirty=YES;return;}
        profileStarting=NO;configUUID=[[NSUUID alloc] initWithUUIDString:uuid];configName=ASVProfileRecord(uuid)[@"name"];configApp=ASVProfileRecord(uuid)[@"owner"];
        vpnStatus=ok?2:1;wasActive=NO;activeSince=0;downSince=Now();healthText=nil;lastStatusPoll=0;dirty=YES;
        if(ok)connectDeadline=Now()+MAX(30,ASVIntSetting(Prefs(),ASV_HC_TIMEOUT,15,1,120)*2);
        else { Event(@"reserveStartError",error);FailedCycle(error); }
    });
}

static void RunHealth(NSDictionary *prefs) {
    NSUInteger generation=automationGeneration;
    NSInteger interval=ASVIntSetting(prefs,ASV_HC_INTERVAL,ASV_DEFAULT_HC_INTERVAL,10,3600);
    if (!HasPhysicalNetwork()) { healthText=@"nonet";nextHealth=Now()+interval;dirty=YES;return; }
    ASVTunnel tunnel=FindTunnel();
    if (!tunnel.found) { healthText=@"notunnel";nextHealth=Now()+interval;dirty=YES;return; }
    probing=YES;
    NSInteger threshold=ASVIntSetting(prefs,ASV_HC_FAILURES,ASV_DEFAULT_HC_FAILURES,1,10);
    NSTimeInterval session=activeSince;
    NSUUID *target=configUUID;
    Probe(ASVHealthMethod(prefs),ASVHealthTarget(prefs),ASVHealthPort(prefs),ASVIntSetting(prefs,ASV_HC_TIMEOUT,15,1,120),tunnel,^(BOOL ok,NSInteger ms,NSString *reason){
        if(generation!=automationGeneration)return;
        probing=NO;cancelProbe=nil;
        if (transactionPaused || !VPNActive() || session!=activeSince || ![target isEqual:configUUID] || Suspended(Prefs()) || !ASVExtraOptionActive(Prefs(),ASV_HEALTH)) return;
        dirty=YES;
        if (ok) {
            healthFails=0;healthText=[NSString stringWithFormat:@"ok:%ld",(long)ms];nextHealth=Now()+interval;
            ASVRecoverySuccess(&recovery);[failedReserves removeAllObjects];connectDeadline=0;
            reserveCycles=0;reserveCycleProfile=nil;
            Event(@"hcOK",[NSString stringWithFormat:@"%ld",(long)ms]);
            return;
        }
        healthFails++;
        healthText=[@"fail:" stringByAppendingString:reason ?: @""];
        Event(@"hcFail",[NSString stringWithFormat:@"%ld/%ld %@",(long)healthFails,(long)threshold,reason ?: @""]);
        if (healthFails>=threshold && target && !Suspended(Prefs()) && Control(target,NO)) {
            Event(@"healthStop",reason);
            healthFails=0;
            nextHealth=Now()+interval;
            nextStartAllowed=Now()+5;
            if(ASVExtraOptionActive(Prefs(),ASV_ALWAYS_ON))FailedCycle(reason);
        } else nextHealth=Now()+MIN(10,interval);
    });
}
static void LockChanged(BOOL nowLocked) {
    if (nowLocked==locked) return;
    locked=nowLocked;
    mediaKnown=NO;mediaPending=NO;mediaPollAt=0;++mediaGeneration;
    dirty=YES;
    NSDictionary *prefs=Prefs();
    ASVSupervisorSetEnabled([prefs[@"enabled"] boolValue]);
    if(!masterEnabled || transactionPaused || ASVIsMultiMode(prefs))return;
    Event(locked?@"lock":@"unlock",nil);
    if (locked) { lockedAt=Now();return; }
    if (lsStoppedUUID) {
        NSUUID *uuid=lsStoppedUUID;
        lsStoppedUUID=nil;
        if (ASVExtraOptionActive(prefs,ASV_LS_DISCONNECT) && !VPNActive() && Control(uuid,YES)) Event(@"lsStart",nil);
        nextStartAllowed=Now()+15;
    }
    ASVSupervisorTick();
}
// Fine-grained session state (connecting, reasserting, disconnecting) for the State read-out.
static void PollStatus(NSTimeInterval now) {
    if(statusPolling && now-lastStatusPoll>10)statusPolling=NO;
    if (statusPolling || now-lastStatusPoll<3) return;
    ASVNESession target=configUUID ? SessionFor(configUUID) : NULL;
    if (!target || !neGetStatus) { if (vpnStatus) { vpnStatus=0;dirty=YES; } return; }
    lastStatusPoll=now;
    statusPolling=YES;
    NSUUID *uuid=configUUID;
    neGetStatus(target,dispatch_get_main_queue(),^(int status){
        statusPolling=NO;
        if(![uuid isEqual:configUUID])return;
        if (status!=vpnStatus) { vpnStatus=status;dirty=YES; }
    });
}
void ASVSupervisorTick(void) {
    NSTimeInterval now=Now();
    NSDictionary *prefs=Prefs();
    ASVSupervisorSetEnabled([prefs[@"enabled"] boolValue]);
    if(!masterEnabled){
        // Read-only status for Settings; no VPN control, probes or event monitoring.
        if(now-lastConfigLoad>30 || !configUUID)LoadConfiguration();
        BOOL active=VPNActive();if(wasActive!=active){wasActive=active;dirty=YES;}
        PollStatus(now);WriteState();return;
    }
    if(transactionPaused)return;
    uint64_t uiLock=0;
    if(uiLockToken>=0 && notify_get_state(uiLockToken,&uiLock)==NOTIFY_STATUS_OK && (uiLock&2) && locked!=((uiLock&1)!=0)){
        LockChanged((uiLock&1)!=0);return;
    }
    static NSTimeInterval lastCatalog; if(now-lastCatalog>10){lastCatalog=now;ASVProfilesRefresh();}
    if(ASVIsMultiMode(prefs)) { WriteState();return; }
    BOOL lsOption=ASVExtraOptionActive(prefs,ASV_LS_DISCONNECT), always=ASVExtraOptionActive(prefs,ASV_ALWAYS_ON), health=ASVExtraOptionActive(prefs,ASV_HEALTH);
    static BOOL lastMediaOption;
    BOOL mediaOption=lsOption && [prefs[ASV_LS_MEDIA] boolValue];
    if(mediaOption!=lastMediaOption){
        lastMediaOption=mediaOption;mediaKnown=NO;mediaPending=NO;mediaPollAt=0;++mediaGeneration;
    }
    PollMedia(prefs,now);
    BOOL hold=MediaProtected(prefs);
    if(hold!=mediaHeld){
        mediaHeld=hold;dirty=YES;
        if(locked){lockedAt=now;Event(hold?@"lsMediaHold":@"lsMediaRelease",nil);}
    }
    BOOL automation=always || ASVExtraOptionActive(prefs,ASV_REDUNDANCY);
    if(automation && !lastAutomation){circuitLatched=NO;recovery=(ASVRecovery){0};[failedReserves removeAllObjects];dirty=YES;}
    lastAutomation=automation;
    BOOL redundancy=ASVExtraOptionActive(prefs,ASV_REDUNDANCY);
    NSString *primary=[prefs[ASV_PRIMARY] isKindOfClass:NSString.class]?prefs[ASV_PRIMARY]:@"";
    if(redundancy && primary.length && (!lastRedundancy || ![primary isEqual:lastPrimary])){
        if(Suspended(prefs) || (VPNActive() && !configUUID)){LoadConfiguration();WriteState();return;}
        if(ASVProfileRecord(primary) && ![configUUID.UUIDString isEqual:primary]){
            if(VPNActive() && configUUID)Control(configUUID,NO);
            pendingReserve=primary;nextStartAllowed=now+3;connectDeadline=0;
            reserveCycles=0;reserveCycleProfile=nil;[failedReserves removeAllObjects];
            Event(@"primaryStart",ASVProfileRecord(primary)[@"name"] ?: primary);
        }
    }
    lastRedundancy=redundancy;lastPrimary=[primary copy];
    BOOL active=pinnedProfile.length?(vpnStatus==3||vpnStatus==4):VPNActive();
    static NSTimeInterval pausedAt;
    BOOL paused=Suspended(prefs) || !HasPhysicalNetwork();
    if(paused && !pausedAt)pausedAt=now;
    else if(!paused && pausedAt){if(connectDeadline)connectDeadline+=now-pausedAt;pausedAt=0;}
    if (now-lastConfigLoad>(configUUID?30:5) || (active && !wasActive)) LoadConfiguration();
    if (active && !wasActive) { activeSince=now;startFailures=0;healthFails=0;healthText=nil;nextHealth=now+30;connectDeadline=0;dirty=YES;Event(@"vpnUp",configName); }
    if (!active && (wasActive || downSince==0)) {
        if (wasActive) Event(@"vpnDown",configName);
        downSince=now;healthText=nil;dirty=YES;
    }
    wasActive=active;
    PollStatus(now);
    if(!automation){pendingReserve=nil;connectDeadline=0;pinnedProfile=nil;}
    if(!Suspended(prefs) && HasPhysicalNetwork() && connectDeadline && now>=connectDeadline && !active){connectDeadline=0;Control(configUUID,NO);FailedCycle(@"VPN connection timed out");}
    if(pendingReserve && !Suspended(prefs) && HasPhysicalNetwork() && !active && vpnStatus!=5 && !profileStarting && now>=nextStartAllowed){StartReservedProfile();WriteState();return;}
    // Do not disconnect while the latest playback query is still in flight.
    // A temporary pending query must not restart the LS delay or flood the log.
    if (mediaHeld && active && [lsStoppedUUID isEqual:configUUID]) { lsStoppedUUID=nil;dirty=YES; }
    if (lsOption && locked && !mediaHeld && (!mediaOption || !mediaPending) && active && !lsStoppedUUID && configUUID &&
        now-lockedAt>=ASVIntSetting(prefs,ASV_LS_DELAY,ASV_DEFAULT_LS_DELAY,0,600) && Control(configUUID,NO)) {
        lsStoppedUUID=configUUID;
        Event(@"lsStop",nil);
    }
    if (statusPending && now-statusRequestedAt>10) statusPending=NO;
    if (always && !circuitLatched && !pendingReserve && !profileStarting && !Suspended(prefs) && HasPhysicalNetwork() && !active && configUUID && !statusPending && now>=nextStartAllowed && now-downSince>=3) {
        ASVNESession target=SessionFor(configUUID);
        if (target && neGetStatus) {
            NSUUID *uuid=configUUID;
            NSUInteger generation=automationGeneration;
            statusPending=YES;
            statusRequestedAt=now;
            neGetStatus(target,dispatch_get_main_queue(),^(int status){
                if(generation!=automationGeneration)return;
                statusPending=NO;
                if (transactionPaused || VPNActive() || circuitLatched || ![uuid isEqual:configUUID] || Suspended(Prefs()) || !ASVExtraOptionActive(Prefs(),ASV_ALWAYS_ON)) return;
                if (status==ASVStatusConnecting || status==ASVStatusReasserting || status==ASVStatusDisconnecting) { nextStartAllowed=Now()+3;return; }
                if (!Control(uuid,YES)) return;
                startFailures++;
                if(!connectDeadline && [Prefs()[ASV_HEALTH] boolValue])connectDeadline=Now()+MAX(30,ASVIntSetting(Prefs(),ASV_HC_TIMEOUT,15,1,120)*2);
                nextStartAllowed=Now()+MIN(15*startFailures,120);
                Event(@"alwaysOn",nil);
            });
        }
    }
    if (health && active && !Suspended(prefs) && !probing && now>=nextHealth && now-activeSince>=30) RunHealth(prefs);
    if (!health && (healthText || healthFails)) { healthText=nil;healthFails=0;dirty=YES; }
    WriteState();
}
NSString *ASVSupervisorVPNName(void) { return configName; }
void ASVSupervisorStart(void) {
    void *media=dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",RTLD_NOW);
    if(media)mediaIsPlaying=dlsym(media,"MRMediaRemoteGetNowPlayingApplicationIsPlaying");
    void *library=dlopen("/usr/lib/system/libsystem_networkextension.dylib",RTLD_NOW);
    neCreate=dlsym(library ?: RTLD_DEFAULT,"ne_session_create");
    neStart=dlsym(library ?: RTLD_DEFAULT,"ne_session_start");
    neStop=dlsym(library ?: RTLD_DEFAULT,"ne_session_stop");
    neGetStatus=dlsym(library ?: RTLD_DEFAULT,"ne_session_get_status");
    neRelease=dlsym(library ?: RTLD_DEFAULT,"ne_session_release");
    neAnyActive=dlsym(library ?: RTLD_DEFAULT,"ne_session_manager_has_active_sessions");
    NSDictionary *saved=[NSDictionary dictionaryWithContentsOfFile:ASV_EXTRA_STATE];
    recovery.cycles=[saved[@"failedCycles"] unsignedIntValue];recovery.healthy=[saved[@"cycleHealthy"] boolValue];
    failedReserves=[NSMutableSet setWithArray:[saved[@"failedReserves"] isKindOfClass:NSArray.class]?saved[@"failedReserves"]:@[]];
    pinnedProfile=[saved[@"pinnedProfile"] length]?saved[@"pinnedProfile"]:nil;circuitLatched=[saved[@"circuitLatched"] boolValue];
    lastAutomation=ASVExtraOptionActive(Prefs(),ASV_ALWAYS_ON);
    lastRedundancy=ASVExtraOptionActive(Prefs(),ASV_REDUNDANCY) && VPNActive();lastPrimary=[Prefs()[ASV_PRIMARY] copy] ?: @"";
    reserveCycles=MIN(10,[saved[@"reserveCycles"] unsignedIntValue]);reserveCycleProfile=[saved[@"reserveCycleProfile"] copy];
    ASVProfilesRefresh();
    events=[NSMutableArray array];
    NSArray *journal=[NSArray arrayWithContentsOfFile:ASV_EXTRA_LOG];
    if (![journal isKindOfClass:NSArray.class]) journal=[saved[@"events"] isKindOfClass:NSArray.class] ? saved[@"events"] : @[];
    for (id item in journal) if ([item isKindOfClass:NSDictionary.class]) [events addObject:item];
    if (events.count>ASV_EXTRA_LOG_LIMIT) [events removeObjectsInRange:NSMakeRange(0,events.count-ASV_EXTRA_LOG_LIMIT)];
    logDirty=YES;
    // The settings page cannot rewrite the service's journal; it asks the service to clear it.
    notify_register_dispatch(ASV_EXTRA_CLEAR,&clearToken,dispatch_get_main_queue(),^(__unused int token){
        [events removeAllObjects];
        logDirty=YES;
        WriteState();
    });
    // A VPN switched off for the lock screen must come back even if the service restarted meanwhile.
    if ([saved[@"lsStopped"] length]) lsStoppedUUID=[[NSUUID alloc] initWithUUIDString:saved[@"lsStopped"]];
    notify_register_dispatch("com.apple.springboard.lockstate",&lockToken,dispatch_get_main_queue(),^(int token){
        uint64_t value=0;
        if(uiLockToken>=0 && notify_get_state(uiLockToken,&value)==NOTIFY_STATUS_OK && (value&2)){LockChanged((value&1)!=0);return;}
        notify_get_state(token,&value);
        LockChanged(value!=0);
    });
    notify_register_dispatch(ASV_UI_LOCK_NOTIFY,&uiLockToken,dispatch_get_main_queue(),^(int token){
        uint64_t value=0;if(notify_get_state(token,&value)==NOTIFY_STATUS_OK && (value&2))LockChanged((value&1)!=0);
    });
    uint64_t value=0;
    if (lockToken>=0) notify_get_state(lockToken,&value);
    locked=value!=0;
    value=0;if(uiLockToken>=0 && notify_get_state(uiLockToken,&value)==NOTIFY_STATUS_OK && (value&2))locked=(value&1)!=0;
    // A service restart is not a VPN connection: start from the current state without logging it.
    wasActive=VPNActive();
    if (wasActive) { activeSince=Now();nextHealth=activeSince+30; } else downSince=Now();
    if (locked) lockedAt=Now();
    else if (lsStoppedUUID) { locked=YES;LockChanged(NO); }
    ASVSupervisorSetEnabled([Prefs()[@"enabled"] boolValue]);
}
