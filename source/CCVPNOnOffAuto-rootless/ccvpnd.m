#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/message.h>
#import <notify.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>
#import <errno.h>
extern int proc_listallpids(void *,int);
extern int proc_pidpath(int,void *,uint32_t);
extern int memorystatus_control(uint32_t,int32_t,uint32_t,void *,size_t);
typedef struct {int32_t pid,priority;uint64_t data;int32_t limit;uint32_t state;} PriorityEntry;
typedef struct {int32_t priority;uint64_t data;} PriorityProperties;
typedef struct {int32_t active;uint32_t activeAttr;int32_t inactive;uint32_t inactiveAttr;} MemoryProperties;
static NSString *const StatePath=@"/var/jb/var/lib/ratu-cc/vpn-state.plist";
static NSArray<NEVPNManager *> *gManagers;
static NEVPNManager *gTarget;
static BOOL gAuto,gBusy;
static NSUInteger gRequest;
static NSDate *gNextAttempt;
static NSString *gLastID;
static NSMutableArray<NSString *> *gCommands;
static NSMutableDictionary<NSNumber *,NSDictionary *> *gProtected;
static NSTimer *gTimer;
static dispatch_source_t gQuit;
static NSMutableDictionary *gOriginalDemand;
static void RestorePriorities(void);
static BOOL Up(NEVPNManager *m){return m.connection.status==NEVPNStatusConnected || m.connection.status==NEVPNStatusConnecting || m.connection.status==NEVPNStatusReasserting;}
static NSString *ManagerID(NEVPNManager *manager){
    for(id object in @[manager,manager.connection]) { SEL selector=NSSelectorFromString(@"identifier");if([object respondsToSelector:selector]){id value=((id(*)(id,SEL))objc_msgSend)(object,selector);if([value respondsToSelector:@selector(UUIDString)])return [value UUIDString];if([value isKindOfClass:NSString.class])return value;}}
    // Names are never used to choose between two different provider profiles.
    NETunnelProviderProtocol *p=(id)manager.protocolConfiguration;
    return [NSString stringWithFormat:@"%@|%@|%@",[p isKindOfClass:NETunnelProviderProtocol.class]?p.providerBundleIdentifier:@"personal",manager.localizedDescription?:@"",p.serverAddress?:@""];
}
static void Publish(void){
    int mode=gAuto?2:(gTarget.connection.status==NEVPNStatusConnected?1:0);
    const char *names[]={"com.ratush.ccvpnonoffauto.state.off","com.ratush.ccvpnonoffauto.state.vpn","com.ratush.ccvpnonoffauto.state.auto"};
    notify_post(names[mode]);
    NSDictionary *state=@{@"auto":@(gAuto),@"lastID":gLastID?:@"",@"connected":@(gTarget.connection.status==NEVPNStatusConnected),@"status":@(gTarget.connection.status),@"busy":@(gBusy),@"originalDemand":gOriginalDemand?:@{}};
    [state writeToFile:StatePath atomically:YES];
}
static NEVPNManager *Pick(void){
    for(NEVPNManager *manager in gManagers)if(Up(manager))return manager;
    for(NEVPNManager *manager in gManagers)if([ManagerID(manager) isEqual:gLastID])return manager;
    for(NEVPNManager *manager in gManagers)if(manager.enabled)return manager;
    return gManagers.count==1?gManagers.firstObject:nil;
}
static BOOL SameProcess(pid_t pid,NSString *path){char buffer[4096]={0};return proc_pidpath(pid,buffer,sizeof(buffer))>0 && [@(buffer) isEqual:path];}
static void RestorePriorities(void){
    for(NSNumber *key in gProtected){NSDictionary *v=gProtected[key];if(!SameProcess(key.intValue,v[@"path"]))continue;
        MemoryProperties memory;[v[@"memory"] getBytes:&memory length:sizeof(memory)];
        PriorityProperties priority={.priority=[v[@"priority"] intValue],.data=[v[@"data"] unsignedLongLongValue]};
        int mr=memorystatus_control(7,key.intValue,0,&memory,sizeof(memory));int pr=memorystatus_control(2,key.intValue,0,&priority,sizeof(priority));
        fprintf(stderr,"restore pid=%d memory=%d priority=%d\n",key.intValue,mr,pr);
    }[gProtected removeAllObjects];
}
static void ProtectProvider(void){
    if(!gAuto || !gTarget)return;
    NETunnelProviderProtocol *protocol=(id)gTarget.protocolConfiguration;
    if(![protocol isKindOfClass:NETunnelProviderProtocol.class] || !protocol.providerBundleIdentifier.length)return;
    int count=proc_listallpids(NULL,0);if(count<=0)return;
    size_t bytes=(size_t)(count+64)*sizeof(pid_t);pid_t *pids=calloc(1,bytes);if(!pids)return;
    int got=proc_listallpids(pids,(int)bytes);
    int size=memorystatus_control(1,0,0,NULL,0);PriorityEntry *entries=size>0?calloc(1,size):NULL;
    if(entries){int used=memorystatus_control(1,0,0,entries,size);if(used<0){free(entries);entries=NULL;}else size=used;}
    for(int i=0;i<got && i<(int)(bytes/sizeof(pid_t));i++){
        char path[4096]={0};if(proc_pidpath(pids[i],path,sizeof(path))<=0)continue;
        NSString *exe=@(path);NSRange range=[exe rangeOfString:@".appex/"];if(range.location==NSNotFound)continue;
        NSString *bundle=[exe substringToIndex:range.location+6];
        if(![[NSBundle bundleWithPath:bundle].bundleIdentifier isEqual:protocol.providerBundleIdentifier])continue;
        NSNumber *key=@(pids[i]);if(gProtected[key] && [gProtected[key][@"path"] isEqual:exe])continue;
        MemoryProperties original={0};if(memorystatus_control(8,pids[i],0,&original,sizeof(original))<0)continue;
        PriorityEntry *found=NULL;for(int j=0;entries && j<size/(int)sizeof(PriorityEntry);j++)if(entries[j].pid==pids[i]){found=&entries[j];break;}
        if(!found)continue;
        gProtected[key]=@{@"path":exe,@"memory":[NSData dataWithBytes:&original length:sizeof(original)],@"priority":@(found->priority),@"data":@(found->data)};
        MemoryProperties raised={MAX(original.active,1024),0,MAX(original.inactive,1024),0};
        PriorityProperties priority={.priority=MAX(found->priority,90),.data=found->data};
        int mr=memorystatus_control(7,pids[i],0,&raised,sizeof(raised));int me=errno;
        int pr=memorystatus_control(2,pids[i],0,&priority,sizeof(priority));int pe=errno;
        fprintf(stderr,"protect provider pid=%d memory=%d errno=%d priority=%d errno=%d\n",pids[i],mr,me,pr,pe);
    }free(entries);free(pids);
}
static void Reload(void(^done)(NSError *)){
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers,NSError *error){
        dispatch_async(dispatch_get_main_queue(),^{
            if(error){done(error);return;}
            NEVPNManager *personal=NEVPNManager.sharedManager;
            [personal loadFromPreferencesWithCompletionHandler:^(NSError *personalError){dispatch_async(dispatch_get_main_queue(),^{
                NSMutableArray *all=[managers mutableCopy]?:[NSMutableArray array];if(!personalError && personal.protocolConfiguration)[all addObject:personal];
                gManagers=all;gTarget=Pick();if(gTarget){NSString *newID=ManagerID(gTarget);if(gLastID.length && ![newID isEqual:gLastID])RestorePriorities();gLastID=newID;}done(nil);
            });}];
        });
    }];
}
static void ProcessNext(void);
static void Finish(void){gBusy=NO;Publish();ProcessNext();}
static void Execute(NSString *command){
    if(gBusy)return;gBusy=YES;NSUInteger request=++gRequest;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(gBusy && request==gRequest){++gRequest;fprintf(stderr,"VPN operation timed out\n");Finish();}});
    Reload(^(NSError *error){
        if(request!=gRequest)return;
        if(error || !gTarget){fprintf(stderr,"no usable VPN profile: %s\n",error.description.UTF8String?:"none");Finish();return;}
        BOOL start=NO;
        if([command isEqual:@"long"]){gAuto=!gAuto;if(!gAuto){RestorePriorities();NSNumber *previous=gOriginalDemand[ManagerID(gTarget)];if(previous){gTarget.onDemandEnabled=previous.boolValue;[gTarget saveToPreferencesWithCompletionHandler:^(NSError *e){dispatch_async(dispatch_get_main_queue(),^{if(request==gRequest)Finish();});}];}else Finish();return;}gOriginalDemand[ManagerID(gTarget)]=@(gTarget.onDemandEnabled);start=YES;}
        else if([command isEqual:@"tap"]){start=!Up(gTarget) && !gAuto;gAuto=NO;RestorePriorities();}
        else if([command isEqual:@"reconnect"]){if(!gAuto || Up(gTarget)){Finish();return;}start=YES;}
        else{Finish();return;}
        NEVPNManager *target=gTarget;
        if(!start)target.onDemandEnabled=NO;
        else if(gAuto && target.onDemandRules.count)target.onDemandEnabled=YES;
        target.enabled=YES;
        [target saveToPreferencesWithCompletionHandler:^(NSError *saveError){dispatch_async(dispatch_get_main_queue(),^{
            if(request!=gRequest)return;
            if(saveError){fprintf(stderr,"save VPN failed: %s\n",saveError.description.UTF8String);Finish();return;}
            [target loadFromPreferencesWithCompletionHandler:^(NSError *loadError){dispatch_async(dispatch_get_main_queue(),^{
                if(request!=gRequest)return;
                if(!loadError){if(start && !Up(target)){NSError *startError=nil;BOOL ok=[target.connection startVPNTunnelAndReturnError:&startError];fprintf(stderr,"start VPN ok=%d error=%s\n",ok,startError.description.UTF8String?:"none");}else if(!start) [target.connection stopVPNTunnel];}
                gNextAttempt=[NSDate dateWithTimeIntervalSinceNow:15];ProtectProvider();Finish();
            });}];
        });}];
    });
}
static void ProcessNext(void){if(gBusy || !gCommands.count)return;NSString *command=gCommands.firstObject;[gCommands removeObjectAtIndex:0];Execute(command);}
static void OnCommand(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef userInfo){
    NSString *n=(__bridge NSString *)name;dispatch_async(dispatch_get_main_queue(),^{
        if([n hasSuffix:@"query"]){Publish();return;}
        if(gCommands.count<8)[gCommands addObject:[n hasSuffix:@"longpress"]?@"long":@"tap"];ProcessNext();
    });
}
int main(void){@autoreleasepool{
    if(geteuid()!=0)return 77;
    [[NSFileManager defaultManager] createDirectoryAtPath:StatePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:NULL];
    NSDictionary *saved=[NSDictionary dictionaryWithContentsOfFile:StatePath];gAuto=[saved[@"auto"] boolValue];gLastID=saved[@"lastID"];
    gCommands=[NSMutableArray array];gProtected=[NSMutableDictionary dictionary];gOriginalDemand=[saved[@"originalDemand"] mutableCopy]?:[NSMutableDictionary dictionary];
    signal(SIGTERM,SIG_IGN);gQuit=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());dispatch_source_set_event_handler(gQuit,^{RestorePriorities();exit(0);});dispatch_resume(gQuit);
    CFNotificationCenterRef center=CFNotificationCenterGetDarwinNotifyCenter();
    for(NSString *suffix in @[@"tap",@"longpress",@"query"])CFNotificationCenterAddObserver(center,NULL,OnCommand,(__bridge CFStringRef)[@"com.ratush.ccvpnonoffauto.cmd." stringByAppendingString:suffix],NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    Reload(^(NSError *error){fprintf(stderr,"loaded VPN profiles=%lu error=%s\n",(unsigned long)gManagers.count,error.description.UTF8String?:"none");Publish();});
    gTimer=[NSTimer scheduledTimerWithTimeInterval:5 repeats:YES block:^(__unused NSTimer *timer){
        if(gBusy)return;
        static int ticks=0;if(++ticks%4==0){Execute(@"refresh");return;}
        if(gAuto){ProtectProvider();if(!Up(gTarget) && (!gNextAttempt || [gNextAttempt timeIntervalSinceNow]<=0)){gNextAttempt=[NSDate dateWithTimeIntervalSinceNow:15];Execute(@"reconnect");return;}}
        Publish();
    }];
    [[NSRunLoop mainRunLoop] run];return 0;
}}
