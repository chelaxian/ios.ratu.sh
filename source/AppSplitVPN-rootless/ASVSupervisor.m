#import "ASVSupervisor.h"
#import "Shared.h"
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
static BOOL locked;
static NSTimeInterval lockedAt;
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
static struct timespec prefsStamp;

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
static BOOL Suspended(NSDictionary *prefs) { return locked && [prefs[ASV_LS_DISCONNECT] boolValue]; }

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
        @"locked":@(locked),@"lsStopped":lsStoppedUUID.UUIDString ?: @"",@"vpnName":configName ?: @"",
        @"vpnApp":configApp ?: @"",@"vpnStatus":@(vpnStatus),@"vpnActive":@(wasActive),@"updated":@(Now())};
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
// The tunnel is the utun/ipsec/ppp interface carrying an address. Carrier
// IMS/VoWiFi tunnels (192.0.0.0/24, ULA) and the empty system utuns are skipped.
static ASVTunnel FindTunnel(void) {
    ASVTunnel best={0};
    int bestScore=0;
    struct ifaddrs *list=NULL;
    if (getifaddrs(&list)!=0) return best;
    for (struct ifaddrs *item=list;item;item=item->ifa_next) {
        if (!item->ifa_addr || !(item->ifa_flags&IFF_UP)) continue;
        const char *name=item->ifa_name;
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
static NSString *Ping(NSString *host,ASVTunnel tunnel) {
    struct addrinfo hints={0},*result=NULL;
    hints.ai_family=tunnel.family;hints.ai_socktype=SOCK_DGRAM;
    if (getaddrinfo(host.UTF8String,NULL,&hints,&result)!=0 || !result) return @"dns";
    BOOL v4=tunnel.family==AF_INET;
    int fd=socket(tunnel.family,SOCK_DGRAM,v4?IPPROTO_ICMP:IPPROTO_ICMPV6);
    if (fd<0) { freeaddrinfo(result);return @"socket"; }
    unsigned index=tunnel.index;
    setsockopt(fd,v4?IPPROTO_IP:IPPROTO_IPV6,v4?IP_BOUND_IF:IPV6_BOUND_IF,&index,sizeof index);
    uint16_t ident=(uint16_t)arc4random();
    NSString *reason=@"timeout";
    // Tunnels often answer ICMP slowly and drop some echoes: four tries, 2.5 s each.
    for (uint16_t seq=1;seq<=4;seq++) {
        uint8_t packet[24]={0};
        packet[0]=v4?ICMP_ECHO:ICMP6_ECHO_REQUEST;
        memcpy(packet+4,&ident,2);
        uint16_t netSeq=htons(seq);
        memcpy(packet+6,&netSeq,2);
        if (v4) { uint16_t sum=Checksum(packet,sizeof packet);memcpy(packet+2,&sum,2); }
        if (sendto(fd,packet,sizeof packet,0,result->ai_addr,result->ai_addrlen)<0) { reason=@"send";continue; }
        NSTimeInterval deadline=Now()+2.5;
        while (Now()<deadline) {
            struct pollfd poller={fd,POLLIN,0};
            if (poll(&poller,1,(int)MAX(1,(deadline-Now())*1000))<=0) break;
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
static void Probe(NSString *method,NSString *host,NSInteger port,ASVTunnel tunnel,ASVProbeDone done) {
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
        dispatch_async(queue,^{ finish(Ping(host,tunnel)); });
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
    nw_connection_set_queue(current,queue);
    nw_connection_set_state_changed_handler(current,^(nw_connection_state_t state,nw_error_t error){
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
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,15*NSEC_PER_SEC),queue,^{ finish(@"timeout"); });
    nw_connection_start(current);
}

#pragma mark - Supervisor

static void RunHealth(NSDictionary *prefs) {
    NSInteger interval=ASVIntSetting(prefs,ASV_HC_INTERVAL,ASV_DEFAULT_HC_INTERVAL,10,3600);
    if (!HasPhysicalNetwork()) { healthText=@"nonet";nextHealth=Now()+interval;dirty=YES;return; }
    ASVTunnel tunnel=FindTunnel();
    if (!tunnel.found) { healthText=@"notunnel";nextHealth=Now()+interval;dirty=YES;return; }
    probing=YES;
    NSInteger threshold=ASVIntSetting(prefs,ASV_HC_FAILURES,ASV_DEFAULT_HC_FAILURES,1,10);
    NSTimeInterval session=activeSince;
    NSUUID *target=configUUID;
    Probe(ASVHealthMethod(prefs),ASVHealthTarget(prefs),ASVHealthPort(prefs),tunnel,^(BOOL ok,NSInteger ms,NSString *reason){
        probing=NO;
        if (!VPNActive() || session!=activeSince) return;
        dirty=YES;
        if (ok) {
            healthFails=0;healthText=[NSString stringWithFormat:@"ok:%ld",(long)ms];nextHealth=Now()+interval;
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
        } else nextHealth=Now()+MIN(10,interval);
    });
}
static void LockChanged(BOOL nowLocked) {
    if (nowLocked==locked) return;
    locked=nowLocked;
    dirty=YES;
    Event(locked?@"lock":@"unlock",nil);
    if (locked) { lockedAt=Now();return; }
    if (lsStoppedUUID) {
        NSUUID *uuid=lsStoppedUUID;
        lsStoppedUUID=nil;
        if (!VPNActive() && Control(uuid,YES)) Event(@"lsStart",nil);
        nextStartAllowed=Now()+15;
    }
    ASVSupervisorTick();
}
// Fine-grained session state (connecting, reasserting, disconnecting) for the State read-out.
static void PollStatus(NSTimeInterval now) {
    if (statusPolling || now-lastStatusPoll<3) return;
    ASVNESession target=configUUID ? SessionFor(configUUID) : NULL;
    if (!target || !neGetStatus) { if (vpnStatus) { vpnStatus=0;dirty=YES; } return; }
    lastStatusPoll=now;
    statusPolling=YES;
    neGetStatus(target,dispatch_get_main_queue(),^(int status){
        statusPolling=NO;
        if (status!=vpnStatus) { vpnStatus=status;dirty=YES; }
    });
}
void ASVSupervisorTick(void) {
    NSTimeInterval now=Now();
    NSDictionary *prefs=Prefs();
    BOOL lsOption=[prefs[ASV_LS_DISCONNECT] boolValue], always=[prefs[ASV_ALWAYS_ON] boolValue], health=[prefs[ASV_HEALTH] boolValue];
    BOOL active=VPNActive();
    if (now-lastConfigLoad>(configUUID?30:5) || (active && !wasActive)) LoadConfiguration();
    if (active && !wasActive) { activeSince=now;startFailures=0;healthFails=0;healthText=nil;nextHealth=now+30;dirty=YES;Event(@"vpnUp",configName); }
    if (!active && (wasActive || downSince==0)) {
        if (wasActive) Event(@"vpnDown",configName);
        downSince=now;healthText=nil;dirty=YES;
    }
    wasActive=active;
    PollStatus(now);
    if (lsOption && locked && active && !lsStoppedUUID && configUUID &&
        now-lockedAt>=ASVIntSetting(prefs,ASV_LS_DELAY,ASV_DEFAULT_LS_DELAY,0,600) && Control(configUUID,NO)) {
        lsStoppedUUID=configUUID;
        Event(@"lsStop",nil);
    }
    if (statusPending && now-statusRequestedAt>10) statusPending=NO;
    if (always && !Suspended(prefs) && !active && configUUID && !statusPending && now>=nextStartAllowed && now-downSince>=3) {
        ASVNESession target=SessionFor(configUUID);
        if (target && neGetStatus) {
            NSUUID *uuid=configUUID;
            statusPending=YES;
            statusRequestedAt=now;
            neGetStatus(target,dispatch_get_main_queue(),^(int status){
                statusPending=NO;
                if (VPNActive() || ![uuid isEqual:configUUID] || Suspended(Prefs()) || ![Prefs()[ASV_ALWAYS_ON] boolValue]) return;
                if (status==ASVStatusConnecting || status==ASVStatusReasserting || status==ASVStatusDisconnecting) { nextStartAllowed=Now()+3;return; }
                if (!Control(uuid,YES)) return;
                startFailures++;
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
    void *library=dlopen("/usr/lib/system/libsystem_networkextension.dylib",RTLD_NOW);
    neCreate=dlsym(library ?: RTLD_DEFAULT,"ne_session_create");
    neStart=dlsym(library ?: RTLD_DEFAULT,"ne_session_start");
    neStop=dlsym(library ?: RTLD_DEFAULT,"ne_session_stop");
    neGetStatus=dlsym(library ?: RTLD_DEFAULT,"ne_session_get_status");
    neRelease=dlsym(library ?: RTLD_DEFAULT,"ne_session_release");
    neAnyActive=dlsym(library ?: RTLD_DEFAULT,"ne_session_manager_has_active_sessions");
    NSDictionary *saved=[NSDictionary dictionaryWithContentsOfFile:ASV_EXTRA_STATE];
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
        notify_get_state(token,&value);
        LockChanged(value!=0);
    });
    uint64_t value=0;
    if (lockToken>=0) notify_get_state(lockToken,&value);
    locked=value!=0;
    // A service restart is not a VPN connection: start from the current state without logging it.
    wasActive=VPNActive();
    if (wasActive) { activeSince=Now();nextHealth=activeSince+30; } else downSince=Now();
    if (locked) lockedAt=Now();
    else if (lsStoppedUUID) { locked=YES;LockChanged(NO); }
}
