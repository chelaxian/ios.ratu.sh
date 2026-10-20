#import <Foundation/Foundation.h>
#import <NetworkExtension/NetworkExtension.h>
#import <objc/message.h>
#import <notify.h>
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
static const char *StateName="com.ratush.ccvpnonoffauto.state.v2";
static const char *TapName="com.ratush.ccvpnonoffauto.cmd.tap.v2";
static const char *AutoName="com.ratush.ccvpnonoffauto.cmd.auto.v2";
static NSArray<NEVPNManager *> *gManagers;
static NEVPNManager *gTarget,*gRestoreDemandTarget;
static BOOL gAuto,gBusy,gReady,gReloading,gReloadScheduled;
static NSInteger gDesired=-1,gLastError;
static NSUInteger gAttempts,gConfigRequest,gLoadRequest;
static CFTimeInterval gNextAttempt,gStartDeadline,gLastLoad,gLastProtect,gLastStop,gNextLoad;
static NSString *gLastID;
static NSMutableDictionary<NSNumber *,NSDictionary *> *gProtected;
static NSMutableDictionary *gOriginalDemand;
static NSDictionary *gPublished;
static int gStateToken,gTapToken,gAutoToken;
static uint64_t gTapSeen,gAutoSeen;
static NSTimer *gTimer;
static dispatch_source_t gQuit;
static void Reconcile(void),Observe(void),ScheduleReload(void),ConsumeCounts(void),RestorePriorities(void);
static CFTimeInterval Now(void){return NSProcessInfo.processInfo.systemUptime;}
static BOOL Up(NEVPNManager *m){NEVPNStatus s=m.connection.status;return s==NEVPNStatusConnected || s==NEVPNStatusConnecting || s==NEVPNStatusReasserting;}
static NSString *ManagerID(NEVPNManager *manager){
    if(!manager)return @"";
    for(id object in @[manager,manager.connection]){SEL sel=NSSelectorFromString(@"identifier");if([object respondsToSelector:sel]){id v=((id(*)(id,SEL))objc_msgSend)(object,sel);if([v respondsToSelector:@selector(UUIDString)])return [v UUIDString];if([v isKindOfClass:NSString.class])return v;}}
    NEVPNProtocol *p=manager.protocolConfiguration;
    return [NSString stringWithFormat:@"%@|%@|%@",[p isKindOfClass:NETunnelProviderProtocol.class]?((NETunnelProviderProtocol *)p).providerBundleIdentifier:@"personal",manager.localizedDescription?:@"",p.serverAddress?:@""];
}
static NEVPNManager *Pick(void){
    for(NEVPNManager *m in gManagers)if(m.connection.status==NEVPNStatusConnected)return m;
    for(NEVPNManager *m in gManagers)if(Up(m))return m;
    for(NEVPNManager *m in gManagers)if([ManagerID(m) isEqual:gLastID])return m;
    for(NEVPNManager *m in gManagers)if(m.enabled)return m;
    return gManagers.count==1?gManagers.firstObject:nil;
}
static void Publish(BOOL force){
    if(!gReady)return;
    NEVPNStatus status=gTarget.connection.status;BOOL connected=status==NEVPNStatusConnected;
    NSDictionary *state=@{@"auto":@(gAuto),@"lastID":gLastID?:@"",@"connected":@(connected),@"status":@(status),@"busy":@(gBusy),@"desired":@(gDesired),@"attempts":@(gAttempts),@"error":@(gLastError),@"tapSeen":@(gTapSeen),@"autoSeen":@(gAutoSeen),@"originalDemand":[gOriginalDemand copy]?:@{}};
    if(!force && [state isEqual:gPublished])return;
    if(![state isEqual:gPublished]){[state writeToFile:StatePath atomically:YES];gPublished=state;}
    // One atomic snapshot, never three independently delivered state names.
    uint64_t value=(connected?1:0)|(gAuto?2:0)|((uint64_t)status<<2)|(gBusy?32:0);
    notify_set_state(gStateToken,value);notify_post(StateName);
    const char *legacy[]={"com.ratush.ccvpnonoffauto.state.off","com.ratush.ccvpnonoffauto.state.vpn","com.ratush.ccvpnonoffauto.state.auto"};
    notify_post(legacy[connected?(gAuto?2:1):0]);
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

static void Adopt(NEVPNManager *manager){
    if(!manager)return;
    NSString *identifier=ManagerID(manager);
    if(gTarget && ![ManagerID(gTarget) isEqual:identifier]){
        RestorePriorities();gRestoreDemandTarget=gTarget;
        gAttempts=0;gStartDeadline=0;gNextAttempt=0;
    }
    gTarget=manager;gLastID=identifier;
}
static void Reload(void){
    if(gReloading || gBusy || Now()<gNextLoad)return;
    gReloading=YES;NSUInteger request=++gLoadRequest;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(gReloading && request==gLoadRequest){++gLoadRequest;gReloading=NO;gNextLoad=Now()+2;gLastError=ETIMEDOUT;Publish(NO);}});
    [NETunnelProviderManager loadAllFromPreferencesWithCompletionHandler:^(NSArray<NETunnelProviderManager *> *managers,NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        if(request!=gLoadRequest)return;
        if(error){gReloading=NO;gNextLoad=Now()+2;gLastError=error.code;Publish(NO);return;}
        NEVPNManager *personal=NEVPNManager.sharedManager;
        [personal loadFromPreferencesWithCompletionHandler:^(NSError *personalError){dispatch_async(dispatch_get_main_queue(),^{
            if(request!=gLoadRequest)return;
            NSMutableArray *all=[managers mutableCopy]?:[NSMutableArray array];
            if(!personalError && personal.protocolConfiguration)[all addObject:personal];
            NEVPNManager *old=gTarget;NSString *oldID=ManagerID(old);
            gManagers=all;
            NEVPNManager *same=nil;for(NEVPNManager *m in all)if([ManagerID(m) isEqual:oldID]){same=m;break;}
            // Keep an in-flight request bound to its profile. Never start a
            // different enabled profile just because a connecting one is down.
            if(old && gDesired>=0 && same)gTarget=same;
            else {NEVPNManager *chosen=Pick();if(chosen)Adopt(chosen);else gTarget=nil;}
            gReloading=NO;gReady=YES;gLastLoad=Now();
            ConsumeCounts();Observe();
        });}];
    });}];
}
static void ScheduleReload(void){
    if(gReloadScheduled)return;gReloadScheduled=YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{gReloadScheduled=NO;Reload();});
}
static void ConfigFinished(NSUInteger request,NSError *error){
    if(request!=gConfigRequest)return;
    gBusy=NO;
    if(error){gLastError=error.code;gNextAttempt=Now()+1;if(!gAuto)gDesired=-1;fprintf(stderr,"VPN preference operation failed code=%ld\n",(long)error.code);}
    Publish(NO);if(!error)Reconcile();
}
static void Configure(NEVPNManager *manager,BOOL demand,BOOL enable){
    if(gBusy)return;gBusy=YES;NSUInteger request=++gConfigRequest;
    manager.onDemandEnabled=demand;if(enable)manager.enabled=YES;
    Publish(NO);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,8*NSEC_PER_SEC),dispatch_get_main_queue(),^{if(gBusy && request==gConfigRequest){gLastError=ETIMEDOUT;gBusy=NO;++gConfigRequest;gNextAttempt=Now()+1;if(!gAuto)gDesired=-1;Publish(NO);ScheduleReload();}});
    [manager saveToPreferencesWithCompletionHandler:^(NSError *error){dispatch_async(dispatch_get_main_queue(),^{
        if(request!=gConfigRequest)return;
        if(error){ConfigFinished(request,error);return;}
        [manager loadFromPreferencesWithCompletionHandler:^(NSError *loadError){dispatch_async(dispatch_get_main_queue(),^{ConfigFinished(request,loadError);});}];
    });}];
}
static void RetryAfterFailure(void){
    gStartDeadline=0;
    if(gAuto || gAttempts<2){gNextAttempt=Now()+MIN(5.0,.25*(1u<<MIN(gAttempts,4u)));}
    else {gDesired=-1;gLastError=ECONNREFUSED;}
}
static void Reconcile(void){
    if(!gReady || gBusy || gReloading || Now()<gNextAttempt)return;
    if(gRestoreDemandTarget){
        NEVPNManager *m=gRestoreDemandTarget;NSString *key=ManagerID(m);NSNumber *previous=gOriginalDemand[key];
        if(previous && m.onDemandEnabled!=previous.boolValue){Configure(m,previous.boolValue,NO);return;}
        [gOriginalDemand removeObjectForKey:key];gRestoreDemandTarget=nil;
    }
    if(!gTarget){Publish(NO);return;}
    if(gDesired<0 && !gAuto){Publish(NO);return;}
    BOOL start=gDesired>=0?gDesired==1:gAuto;
    NEVPNStatus status=gTarget.connection.status;
    BOOL demand=gTarget.onDemandEnabled;
    if(!start)demand=NO;
    else if(gAuto && gTarget.onDemandRules.count)demand=YES;
    else if(!gAuto && gOriginalDemand[ManagerID(gTarget)])demand=[gOriginalDemand[ManagerID(gTarget)] boolValue];
    if(demand!=gTarget.onDemandEnabled || (start && !gTarget.enabled)){
        NSString *key=ManagerID(gTarget);if(!gOriginalDemand[key])gOriginalDemand[key]=@(gTarget.onDemandEnabled);
        Configure(gTarget,demand,start);return;
    }
    if(!start){
        if(status==NEVPNStatusDisconnected || status==NEVPNStatusInvalid){gDesired=-1;gStartDeadline=0;}
        else if(status!=NEVPNStatusDisconnecting && Now()-gLastStop>.2){gLastStop=Now();[gTarget.connection stopVPNTunnel];}
        Publish(NO);return;
    }
    if(status==NEVPNStatusConnected){gDesired=-1;gAttempts=0;gStartDeadline=0;Publish(NO);return;}
    if(status==NEVPNStatusDisconnecting)return;
    if(status==NEVPNStatusConnecting || status==NEVPNStatusReasserting){
        if(gStartDeadline && Now()>gStartDeadline){[gTarget.connection stopVPNTunnel];RetryAfterFailure();Publish(NO);}return;
    }
    if(gStartDeadline){RetryAfterFailure();Publish(NO);return;}
    ++gAttempts;NSError *error=nil;
    BOOL accepted=[gTarget.connection startVPNTunnelAndReturnError:&error];
    fprintf(stderr,"VPN start attempt=%lu accepted=%d code=%ld\n",(unsigned long)gAttempts,accepted,(long)error.code);
    if(accepted){gStartDeadline=Now()+30;gLastError=0;}
    else {gLastError=error.code?:EIO;RetryAfterFailure();ScheduleReload();}
    Publish(NO);
}
static void Observe(void){
    if(!gReady)return;
    // An external profile switch must be reflected without the old 20s scan.
    if(gDesired<0){NEVPNManager *active=Pick();if(active && Up(active))Adopt(active);}
    if(gAuto && gTarget.connection.status==NEVPNStatusConnected && Now()-gLastProtect>=2){gLastProtect=Now();ProtectProvider();}
    Publish(NO);Reconcile();
}
static void Tap(uint64_t count){
    if(!count)return;
    BOOL desired=gDesired>=0?gDesired==1:(gAuto || Up(gTarget));
    if(count&1)desired=!desired;
    gAuto=NO;RestorePriorities();gRestoreDemandTarget=nil;
    gDesired=desired?1:0;gAttempts=0;gNextAttempt=0;gLastError=0;
    // A new request can cancel a start, but a duplicate ON never restarts an
    // already connected tunnel. Rapid tap parity is retained without flapping.
    if(!desired)gStartDeadline=0;
    Publish(NO);Reconcile();
}
static void Auto(uint64_t count){
    if(!(count&1))return;
    gAuto=!gAuto;gAttempts=0;gNextAttempt=0;gLastError=0;
    if(gAuto)gDesired=1;
    else {gDesired=-1;gStartDeadline=0;RestorePriorities();gRestoreDemandTarget=gTarget;}
    Publish(NO);Reconcile();
}
static void ConsumeCounts(void){
    if(!gReady)return;
    uint64_t taps=0,autos=0;
    if(notify_get_state(gTapToken,&taps)==NOTIFY_STATUS_OK && taps!=gTapSeen){uint64_t delta=taps>=gTapSeen?taps-gTapSeen:taps;gTapSeen=taps;Tap(delta);}
    if(notify_get_state(gAutoToken,&autos)==NOTIFY_STATUS_OK && autos!=gAutoSeen){uint64_t delta=autos>=gAutoSeen?autos-gAutoSeen:autos;gAutoSeen=autos;Auto(delta);}
}
static void Legacy(CFNotificationCenterRef center,void *observer,CFStringRef name,const void *object,CFDictionaryRef userInfo){
    NSString *n=(__bridge NSString *)name;dispatch_async(dispatch_get_main_queue(),^{
        if([n hasSuffix:@"query"]){Observe();Publish(YES);if(Now()-gLastLoad>15)ScheduleReload();}
        else if([n hasSuffix:@"longpress"])Auto(1);else Tap(1);
    });
}
int main(void){@autoreleasepool{
    if(geteuid()!=0)return 77;
    [[NSFileManager defaultManager] createDirectoryAtPath:StatePath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:NULL];
    NSDictionary *saved=[NSDictionary dictionaryWithContentsOfFile:StatePath];
    gAuto=[saved[@"auto"] boolValue];gLastID=saved[@"lastID"];gDesired=saved[@"desired"]?[saved[@"desired"] integerValue]:-1;
    gTapSeen=[saved[@"tapSeen"] unsignedLongLongValue];gAutoSeen=[saved[@"autoSeen"] unsignedLongLongValue];
    gProtected=[NSMutableDictionary dictionary];gOriginalDemand=[saved[@"originalDemand"] mutableCopy]?:[NSMutableDictionary dictionary];
    notify_register_check(StateName,&gStateToken);
    notify_register_dispatch(TapName,&gTapToken,dispatch_get_main_queue(),^(__unused int token){ConsumeCounts();});
    notify_register_dispatch(AutoName,&gAutoToken,dispatch_get_main_queue(),^(__unused int token){ConsumeCounts();});
    signal(SIGTERM,SIG_IGN);gQuit=dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL,SIGTERM,0,dispatch_get_main_queue());
    dispatch_source_set_event_handler(gQuit,^{RestorePriorities();Publish(NO);exit(0);});dispatch_resume(gQuit);
    for(NSString *suffix in @[@"tap",@"longpress",@"query"])CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),NULL,Legacy,(__bridge CFStringRef)[@"com.ratush.ccvpnonoffauto.cmd." stringByAppendingString:suffix],NULL,CFNotificationSuspensionBehaviorDeliverImmediately);
    [NSNotificationCenter.defaultCenter addObserverForName:NEVPNStatusDidChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){Observe();}];
    [NSNotificationCenter.defaultCenter addObserverForName:NEVPNConfigurationChangeNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification *note){ScheduleReload();}];
    Reload();
    gTimer=[NSTimer scheduledTimerWithTimeInterval:.25 repeats:YES block:^(__unused NSTimer *timer){
        if(!gReady){if(!gReloading)Reload();return;}
        Observe();if(Now()-gLastLoad>60)ScheduleReload();
    }];
    [[NSRunLoop mainRunLoop] run];return 0;
}}
