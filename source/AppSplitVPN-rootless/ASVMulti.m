#import "ASVMulti.h"
#import "Shared.h"
#import "ASVProfiles.h"
#import "ASVIPProbe.h"
#import <net/if.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <notify.h>
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>
#import <uuid/uuid.h>
#import <signal.h>
#import <errno.h>
#import <spawn.h>
#import <sys/wait.h>
extern char **environ;

static NSString *const ArchiveName=@"originals.archive";
static id Get(id o,NSString *name){SEL s=NSSelectorFromString(name);return [o respondsToSelector:s]?((id(*)(id,SEL))objc_msgSend)(o,s):nil;}
static void Set(id o,NSString *name,id value){((void(*)(id,SEL,id))objc_msgSend)(o,NSSelectorFromString(name),value);}
static double Clock(void){return NSProcessInfo.processInfo.systemUptime;}
static void *Session(NSString *identifier,int type){void *(*create)(const unsigned char *,int)=dlsym(RTLD_DEFAULT,"ne_session_create");NSUUID *uuid=[[NSUUID alloc] initWithUUIDString:identifier];uuid_t bytes;if(!create || !uuid)return NULL;[uuid getUUIDBytes:bytes];return create(bytes,type);}
static void Release(void *s){void(*release)(void *)=dlsym(RTLD_DEFAULT,"ne_session_release");if(s && release)release(s);}
static void Stop(NSString *identifier,int type){void *s=Session(identifier,type);void(*stop)(void *)=dlsym(RTLD_DEFAULT,"ne_session_stop");if(s && stop)stop(s);Release(s);}
static void Status(NSString *identifier,int type,void(^reply)(NSInteger)){void *s=Session(identifier,type);void(*status)(void *,dispatch_queue_t,void(^)(int))=dlsym(RTLD_DEFAULT,"ne_session_get_status");if(!s || !status){Release(s);reply(0);return;}status(s,dispatch_get_main_queue(),^(int value){Release(s);reply(value);});}
static int Directory(void){
    if(mkdir(ASV_MULTI_DIR.fileSystemRepresentation,0700)!=0 && errno!=EEXIST)return -1;
    int fd=open(ASV_MULTI_DIR.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);struct stat st;
    if(fd<0)return -1;
    if(fstat(fd,&st)!=0 || !S_ISDIR(st.st_mode) || st.st_uid!=0 || (st.st_mode&077)){close(fd);return -1;}return fd;
}
static BOOL WriteSecure(NSString *name,NSData *data){
    int dir=Directory();if(dir<0 || !data){if(dir>=0)close(dir);return NO;}
    NSString *temp=[@"pending-" stringByAppendingString:NSUUID.UUID.UUIDString];int fd=openat(dir,temp.UTF8String,O_WRONLY|O_CREAT|O_EXCL|O_NOFOLLOW,0600);
    BOOL ok=fd>=0;size_t at=0;while(ok && at<data.length){ssize_t n=write(fd,(const char *)data.bytes+at,data.length-at);if(n<0 && errno==EINTR)continue;if(n<=0){ok=NO;break;}at+=(size_t)n;}
    if(fd>=0){if(fsync(fd)!=0)ok=NO;close(fd);}if(ok)ok=renameat(dir,temp.UTF8String,dir,name.UTF8String)==0;
    if(!ok)unlinkat(dir,temp.UTF8String,0);if(ok)fsync(dir);close(dir);return ok;
}
static NSData *ReadSecure(NSString *name){int dir=Directory();if(dir<0)return nil;int fd=openat(dir,name.UTF8String,O_RDONLY|O_NOFOLLOW);close(dir);if(fd<0)return nil;struct stat st;
    if(fstat(fd,&st)!=0 || !S_ISREG(st.st_mode) || st.st_uid!=0 || (st.st_mode&077) || st.st_nlink!=1 || st.st_size<=0 || st.st_size>16*1024*1024){close(fd);return nil;}
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)st.st_size];size_t at=0;while(at<data.length){ssize_t n=read(fd,(char *)data.mutableBytes+at,data.length-at);if(n<0 && errno==EINTR)continue;if(n<=0)break;at+=(size_t)n;}close(fd);return at==data.length?data:nil;
}
static BOOL Exists(NSString *name){int dir=Directory();if(dir<0)return YES;struct stat st;BOOL yes=fstatat(dir,name.UTF8String,&st,AT_SYMLINK_NOFOLLOW)==0;close(dir);return yes;}
static BOOL Remove(NSString *name){int dir=Directory();if(dir<0)return NO;BOOL ok=unlinkat(dir,name.UTF8String,0)==0 || errno==ENOENT;if(ok)fsync(dir);close(dir);return ok;}
static BOOL Manifest(NSArray *ids){NSData *data=[NSPropertyListSerialization dataWithPropertyList:@{@"version":@1,@"enabled":@(ids.count>0),@"legacyPacketIDs":ids} format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];return WriteSecure(@"multi-manifest.plist",data);}

@implementation ASVMulti {
    ASVPolicyEngine *_engine;
    BOOL _busy,_ownsProfiles,_wanted,_restoring,_startupDone,_compatRestartAttempted;
    NSString *_status,*_error,*_names;
    NSDictionary *_matrix,*_requested;
    NSDictionary *_publishedInterfaces;
    NSArray *_originals,*_activeBefore,*_providers;
    NSMutableDictionary *_connections,*_statuses;
    double _lastPoll,_started,_retry;
    NSUInteger _generation;
    NSMutableDictionary *_publicIPs;
    NSString *_ipService;
    BOOL _ipBusy;
    double _lastIPRefresh;
    NSUInteger _ipEpoch;
}
- (BOOL)busy{return _busy;}
- (BOOL)ownsProfiles{return _ownsProfiles || !_startupDone;}
- (NSString *)status{return _status ?: @"waitingVPN";}
- (NSString *)error{return _error;}
- (NSString *)names{return _names ?: @"";}
- (NSArray<NSDictionary *> *)activeProfiles {
    NSMutableArray *records=[NSMutableArray new];
    if(_restoring || !_wanted)return records;
    for(id c in _originals){NSString *uuid=[Get(c,@"identifier") UUIDString],*interface=_publishedInterfaces[uuid];if(!interface.length)continue;
        NSString *owner=Get(c,@"application") ?: Get(Get(Get(c,@"VPN"),@"protocol"),@"providerBundleIdentifier");
        NSDictionary *cached=_publicIPs[uuid];
        BOOL valid=[cached[@"interface"] isEqual:interface] && [cached[@"index"] unsignedIntValue]==if_nametoindex(interface.UTF8String) && [cached[@"service"] isEqual:_ipService];
        [records addObject:@{@"id":uuid,@"name":Get(c,@"name") ?: uuid,@"owner":owner ?: @"",@"interface":interface,
            @"publicIP":valid?(cached[@"result"] ?: @[]):@[],@"ipError":valid?(cached[@"error"] ?: @""):@"",@"ipPending":@(!valid)}];
    }return records;
}
- (void)refreshPublicIPs {
    if(Clock()-_lastIPRefresh<5)return;_lastIPRefresh=Clock();++_ipEpoch;[_publicIPs removeAllObjects];[self probeNextIP];
}
- (void)probeNextIP {
    if(_ipBusy || !_wanted || _busy || _restoring)return;
    NSString *service=ASVIPService([NSDictionary dictionaryWithContentsOfFile:ASV_PREFS] ?: @{});
    if(![_ipService isEqual:service]){_ipService=service;++_ipEpoch;[_publicIPs removeAllObjects];}
    NSDictionary *target=nil;for(NSDictionary *record in self.activeProfiles)if([record[@"ipPending"] boolValue]){target=record;break;}
    if(!target)return;
    _ipBusy=YES;NSUInteger generation=_generation,epoch=_ipEpoch;NSString *uuid=target[@"id"],*interface=target[@"interface"];unsigned index=if_nametoindex(interface.UTF8String);
    NSString *application=nil;for(NSString *bundle in [_matrix.allKeys sortedArrayUsingSelector:@selector(compare:)])if([_matrix[bundle] isEqual:uuid]){application=bundle;break;}
    void(^finish)(NSArray *,NSString *)=^(NSArray *result,NSString *error){
        self->_ipBusy=NO;
        if(generation==self->_generation && epoch==self->_ipEpoch && self->_wanted && !self->_restoring &&
           [self->_publishedInterfaces[uuid] isEqual:interface] && if_nametoindex(interface.UTF8String)==index){
            self->_publicIPs[uuid]=@{@"interface":interface,@"index":@(index),@"service":service,@"result":result ?: @[],@"error":error ?: @""};
        }
        [self probeNextIP];
    };
    ASVIPProbe(interface,application,service,^(NSArray *result,NSString *error){
        if(!result && [service isEqual:ASV_DEFAULT_IP_SERVICE] && generation==self->_generation && epoch==self->_ipEpoch && self->_wanted && !self->_restoring){
            // Numeric Cloudflare endpoint avoids a DNS dependency, keeping the same attribution and route verification.
            ASVIPProbe(interface,application,@"https://1.1.1.1/cdn-cgi/trace",finish);
        }else finish(result,error);
    });
}
- (instancetype)initWithEngine:(ASVPolicyEngine *)engine{if((self=[super init])){_engine=engine;_status=@"recovering";_connections=[NSMutableDictionary dictionary];_statuses=[NSMutableDictionary dictionary];_publicIPs=[NSMutableDictionary dictionary];}return self;}
- (void)load:(void(^)(NSArray *,NSError *))reply{
    id manager=Get(NSClassFromString(@"NEConfigurationManager"),@"sharedManager");SEL s=NSSelectorFromString(@"loadConfigurationsWithCompletionQueue:handler:");
    if(![manager respondsToSelector:s]){reply(nil,[NSError errorWithDomain:@"ASVMulti" code:1 userInfo:nil]);return;}
    ((void(*)(id,SEL,id,id))objc_msgSend)(manager,s,dispatch_get_main_queue(),reply);
}
- (void)save:(id)configuration reply:(void(^)(BOOL))reply{
    id manager=Get(NSClassFromString(@"NEConfigurationManager"),@"sharedManager");SEL s=NSSelectorFromString(@"saveConfiguration:withCompletionQueue:handler:");
    if(![manager respondsToSelector:s]){reply(NO);return;}
    ((void(*)(id,SEL,id,id,id))objc_msgSend)(manager,s,configuration,dispatch_get_main_queue(),^(NSError *error){reply(!error || error.code==9);});
}
- (void)fail:(NSString *)message{_status=@"error";_error=message;_retry=Clock()+15;}
- (void)restoreWithCompletion:(void(^)(BOOL))completion{
    _wanted=NO;
    if(_busy && !_restoring){_wanted=NO;dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self restoreWithCompletion:completion];});return;}
    if(_restoring){dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self restoreWithCompletion:completion];});return;}
    if(!Exists(ArchiveName)){Manifest(@[]);[_engine clear];_ownsProfiles=NO;_startupDone=YES;_busy=NO;_status=@"disabled";completion(YES);return;}
    NSData *data=ReadSecure(ArchiveName);NSDictionary *backup=nil;
    @try{NSKeyedUnarchiver *reader=[[NSKeyedUnarchiver alloc] initForReadingFromData:data error:nil];reader.requiresSecureCoding=NO;backup=[reader decodeObjectForKey:NSKeyedArchiveRootObjectKey];[reader finishDecoding];}@catch(__unused NSException *e){}
    if(![backup isKindOfClass:NSDictionary.class] || ![backup[@"version"] isEqual:@1] || ![backup[@"originals"] isKindOfClass:NSArray.class] || [backup[@"originals"] count]>64){[self fail:@"Cannot read protected MULTI recovery archive"];completion(NO);return;}
    _originals=backup[@"originals"];_activeBefore=backup[@"activeBefore"] ?: @[];_ownsProfiles=YES;_busy=YES;_restoring=YES;_status=@"recovering";++_generation;
    for(id c in _originals)Stop([Get(c,@"identifier") UUIDString],2);
    [_connections removeAllObjects];[_statuses removeAllObjects];
    // Keep ownership valid until all appVPN sessions have been stopped/restored.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self waitRestoreStopped:Clock()+20 completion:completion];});
}
- (void)waitRestoreStopped:(double)deadline completion:(void(^)(BOOL))completion{
    dispatch_group_t group=dispatch_group_create();__block BOOL stopped=YES;
    for(id c in _originals){dispatch_group_enter(group);Status([Get(c,@"identifier") UUIDString],2,^(NSInteger status){if(status!=1)stopped=NO;dispatch_group_leave(group);});}
    dispatch_group_notify(group,dispatch_get_main_queue(),^{
        if(stopped){[self restoreIndex:0 completion:completion];return;}
        if(Clock()>=deadline){self->_busy=NO;self->_restoring=NO;[self fail:@"MULTI sessions did not stop; backup retained"];completion(NO);return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self waitRestoreStopped:deadline completion:completion];});
    });
}
- (void)restoreIndex:(NSUInteger)index completion:(void(^)(BOOL))completion{
    if(index<_originals.count){id c=_originals[index];
        if(!Get(c,@"VPN") || Get(c,@"appVPN") || ![Get(c,@"identifier") isKindOfClass:NSUUID.class]){_busy=NO;_restoring=NO;[self fail:@"Invalid original MULTI profile"];completion(NO);return;}
        [self save:c reply:^(BOOL ok){if(!ok){_busy=NO;_restoring=NO;[self fail:@"MULTI profile restoration failed; backup retained"];completion(NO);return;}[self restoreIndex:index+1 completion:completion];}];return;
    }
    if(!Manifest(@[]) || !Remove(ArchiveName)){_busy=NO;_restoring=NO;[self fail:@"MULTI recovery cleanup failed"];completion(NO);return;}
    [_engine clear];_publishedInterfaces=nil;++_ipEpoch;[_publicIPs removeAllObjects];_ownsProfiles=NO;_startupDone=YES;_matrix=nil;_originals=nil;_providers=nil;_names=nil;_busy=NO;_restoring=NO;_status=@"disabled";_error=nil;
    // Restore only sessions that were actually active before this transaction.
    void(*start)(void *)=dlsym(RTLD_DEFAULT,"ne_session_start");for(NSString *uuid in _activeBefore){void *s=Session(uuid,1);if(s && start)start(s);Release(s);}_activeBefore=nil;ASVProfilesRefresh();completion(YES);
}
- (void)begin:(NSDictionary *)matrix{
    if(!matrix.count){NSString *error=nil;BOOL ok=[_engine replaceMatrix:@{} interfaces:@{} providerIDs:@[] error:&error];_matrix=matrix;_status=ok?@"active":@"error";_error=error;return;}
    if(matrix.count>2048 || [NSSet setWithArray:matrix.allValues].count>64){[self fail:@"MULTI ownership manifest limit exceeded"];return;}
    int token=-1;uint64_t ready=0;notify_register_check(ASV_MULTI_COMPAT_READY,&token);if(token>=0){notify_get_state(token,&ready);notify_cancel(token);}
    pid_t pid=(pid_t)(ready>>32);if(!(ready&1) || pid<=1 || (kill(pid,0)!=0 && errno!=EPERM)){
        // One bounded recovery per activation, before profiles are converted.
        // Never restart a service during restoration, or bypass the readiness gate.
        NSDictionary *prefs=[NSDictionary dictionaryWithContentsOfFile:ASV_PREFS];
        if(!_compatRestartAttempted && !_ownsProfiles && !Exists(ArchiveName) &&
           _wanted && [prefs[@"enabled"] boolValue] && ASVIsMultiMode(prefs)){
            _compatRestartAttempted=YES;
            const char *path="/var/jb/bin/launchctl";
            char *args[]={(char *)path,"kickstart","-k","user/501/com.apple.nesessionmanager",NULL};
            pid_t child=0;int result=posix_spawn(&child,path,NULL,NULL,args,environ);
            if(!result){
                _busy=YES;_status=@"connecting";_error=nil;
                [self waitCompatibilityRestart:child deadline:Clock()+5];return;
            }
        }
        [self fail:@"MULTI compatibility module is not loaded; restart VPN service or check tweak injection"];return;
    }
    _busy=YES;_status=@"connecting";_error=nil;NSUInteger generation=++_generation;
    [self load:^(NSArray *configs,NSError *error){
        if(error || !self->_wanted || generation!=self->_generation){self->_busy=NO;if(error)[self fail:@"Cannot load VPN profiles"];return;}
        NSMutableDictionary *all=[NSMutableDictionary dictionary];for(id c in configs){NSString *uuid=[Get(c,@"identifier") UUIDString];if(uuid)all[uuid]=c;}
        NSMutableArray *selected=[NSMutableArray array],*providers=[NSMutableArray array];NSMutableSet *extensions=[NSMutableSet set];
        for(NSString *uuid in [[NSSet setWithArray:matrix.allValues].allObjects sortedArrayUsingSelector:@selector(compare:)]){
            id c=all[uuid],vpn=Get(c,@"VPN"),protocol=Get(vpn,@"protocol");NSString *provider=Get(protocol,@"providerBundleIdentifier"),*owner=Get(c,@"application");
            if(!vpn || Get(c,@"appVPN") || Get(c,@"payloadInfo") || !provider.length || ![vpn respondsToSelector:NSSelectorFromString(@"tunnelType")] || ((NSInteger(*)(id,SEL))objc_msgSend)(vpn,NSSelectorFromString(@"tunnelType"))!=1){self->_busy=NO;[self fail:@"MULTI requires ordinary unmanaged PacketTunnel profiles"];return;}
            if([extensions containsObject:provider]){self->_busy=NO;[self fail:@"Two profiles of the same provider are not validated yet"];return;}[extensions addObject:provider];[providers addObject:provider];if(owner.length)[providers addObject:owner];[selected addObject:[c copy]];
            if(matrix[provider] || (owner.length && matrix[owner])){self->_busy=NO;[self fail:@"VPN provider apps cannot themselves be assigned in this experiment"];return;}
        }
        NSString *policyError=nil;if(![self->_engine replaceMatrix:matrix interfaces:@{} providerIDs:providers error:&policyError]){self->_busy=NO;[self fail:policyError];return;}
        self->_publishedInterfaces=@{};
        self->_originals=selected;self->_providers=providers;self->_matrix=[matrix copy];
        NSMutableArray *active=[NSMutableArray array];dispatch_group_t group=dispatch_group_create();
        for(id c in configs)if(Get(c,@"VPN")){NSString *uuid=[Get(c,@"identifier") UUIDString];if(!uuid)continue;dispatch_group_enter(group);Status(uuid,1,^(NSInteger s){if(s>=2 && s<=4)[active addObject:uuid];dispatch_group_leave(group);});}
        dispatch_group_notify(group,dispatch_get_main_queue(),^{
            if(!self->_wanted || generation!=self->_generation){self->_busy=NO;return;}
            self->_activeBefore=[active copy];NSData *archive=[NSKeyedArchiver archivedDataWithRootObject:@{@"version":@1,@"originals":selected,@"activeBefore":active} requiringSecureCoding:NO error:nil];
            if(Exists(ArchiveName) || !WriteSecure(ArchiveName,archive)){self->_busy=NO;[self fail:@"Cannot secure original VPN profiles"];return;}
            self->_ownsProfiles=YES;
            if(!Manifest([selected valueForKeyPath:@"identifier.UUIDString"])){self->_busy=NO;[self fail:@"Cannot enable owned-session manifest"];return;}
            for(NSString *uuid in active)Stop(uuid,1);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self waitOrdinaryStopped:Clock()+20 generation:generation];});
        });
    }];
}
- (void)waitCompatibilityRestart:(pid_t)child deadline:(double)deadline {
    int status=0;pid_t result=waitpid(child,&status,WNOHANG);
    if(result==child || (result<0 && errno!=EINTR)){
        _busy=NO;_retry=Clock()+2;
        if(_wanted && (result<0 || !WIFEXITED(status) || WEXITSTATUS(status)!=0))
            [self fail:@"Cannot restart MULTI VPN service; check tweak injection"];
        return;
    }
    if(Clock()>=deadline)kill(child,SIGKILL); // Only our launchctl child, not VPN providers.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC/10),dispatch_get_main_queue(),^{
        [self waitCompatibilityRestart:child deadline:deadline];
    });
}
- (void)waitOrdinaryStopped:(double)deadline generation:(NSUInteger)generation{
    if(!_wanted || generation!=_generation){_busy=NO;return;}
    dispatch_group_t group=dispatch_group_create();__block BOOL stopped=YES;
    for(NSString *uuid in _activeBefore){dispatch_group_enter(group);Status(uuid,1,^(NSInteger status){if(status!=1)stopped=NO;dispatch_group_leave(group);});}
    dispatch_group_notify(group,dispatch_get_main_queue(),^{
        if(!self->_wanted || generation!=self->_generation){self->_busy=NO;return;}
        if(stopped){[self startIndex:0 generation:generation];return;}
        if(Clock()>=deadline){self->_busy=NO;[self fail:@"Ordinary VPN did not stop; MULTI not started"];return;}
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{[self waitOrdinaryStopped:deadline generation:generation];});
    });
}
- (void)startIndex:(NSUInteger)index generation:(NSUInteger)generation{
    if(!_wanted || generation!=_generation){_busy=NO;return;}
    if(index>=_originals.count){_busy=NO;_started=Clock();_lastPoll=0;ASVProfilesRefresh();return;}
    id c=[_originals[index] copy];NSString *uuid=[Get(c,@"identifier") UUIDString];id old=Get(c,@"VPN"),app=[NSClassFromString(@"NEVPNApp") new];
    Set(app,@"setProtocol:",[Get(old,@"protocol") copy]);((void(*)(id,SEL,BOOL))objc_msgSend)(app,NSSelectorFromString(@"setEnabled:"),YES);((void(*)(id,SEL,BOOL))objc_msgSend)(app,NSSelectorFromString(@"setNoRestriction:"),YES);((void(*)(id,SEL,NSInteger))objc_msgSend)(app,NSSelectorFromString(@"setTunnelType:"),1);
    if([app respondsToSelector:NSSelectorFromString(@"setOnDemandEnabled:")])((void(*)(id,SEL,BOOL))objc_msgSend)(app,NSSelectorFromString(@"setOnDemandEnabled:"),NO);
    NSMutableArray *rules=[NSMutableArray array];for(NSString *bundle in _matrix)if([_matrix[bundle] isEqual:uuid]){
        NSArray *ids=[NSClassFromString(@"NEProcessInfo") copyUUIDsForBundleID:bundle uid:501];if(!ids.count)continue;
        id rule=((id(*)(id,SEL,id))objc_msgSend)([NSClassFromString(@"NEAppRule") alloc],NSSelectorFromString(@"initWithSigningIdentifier:"),bundle);Set(rule,@"setCachedMachOUUIDs:",ids);((void(*)(id,SEL,BOOL))objc_msgSend)(rule,NSSelectorFromString(@"setNoRestriction:"),YES);[rules addObject:rule];
    }
    Set(app,@"setAppRules:",rules);Set(c,@"setVPN:",nil);Set(c,@"setAppVPN:",app);
    [self save:c reply:^(BOOL ok){if(!ok){self->_busy=NO;[self fail:@"Cannot save per-app VPN; restore required"];self->_wanted=NO;return;}if(!self->_wanted || generation!=self->_generation){self->_busy=NO;return;}
        id manager=Get(NSClassFromString(@"NETunnelProviderManager"),@"forPerAppVPN");Set(manager,@"setConfiguration:",c);self->_connections[uuid]=manager;
        ((void(*)(id,SEL,id))objc_msgSend)(manager,NSSelectorFromString(@"loadFromPreferencesWithCompletionHandler:"),^(NSError *loadError){
            if(!self->_wanted || generation!=self->_generation){self->_busy=NO;return;}
            NSError *startError=nil;BOOL began=!loadError && ((BOOL(*)(id,SEL,id,NSError **))objc_msgSend)(Get(manager,@"connection"),NSSelectorFromString(@"startVPNTunnelWithOptions:andReturnError:"),nil,&startError);
            if(!began){self->_busy=NO;[self fail:@"Per-app VPN start failed; restore required"];self->_wanted=NO;return;}[self startIndex:index+1 generation:generation];
        });
    }];
}
- (void)tickMatrix:(NSDictionary *)matrix enabled:(BOOL)enabled{
    _wanted=enabled;_requested=[matrix copy];
    if(!enabled)_compatRestartAttempted=NO;
    if(!_startupDone){if(!_busy && Clock()>=_retry)[self restoreWithCompletion:^(__unused BOOL ok){}];return;}
    if(_busy)return;
    if(_ownsProfiles && (!enabled || ![_matrix isEqual:matrix] || [_status isEqual:@"error"])){[self restoreWithCompletion:^(__unused BOOL ok){}];return;}
    if(!enabled)return;
    if(!_ownsProfiles){
        if(![_matrix isEqual:matrix]){NSString *error=nil;if(![_engine replaceMatrix:matrix interfaces:@{} providerIDs:@[] error:&error]){[self fail:error];return;}_matrix=[matrix copy];}
        if(Clock()>=_retry)[self begin:matrix];return;
    }
    if(Clock()-_lastPoll<3)return;_lastPoll=Clock();NSUInteger generation=_generation;NSMutableDictionary *interfaces=[NSMutableDictionary dictionary];NSMutableArray *names=[NSMutableArray array];dispatch_group_t group=dispatch_group_create();
    for(id c in _originals){NSString *uuid=[Get(c,@"identifier") UUIDString];dispatch_group_enter(group);Status(uuid,2,^(NSInteger status){if(generation==self->_generation){self->_statuses[uuid]=@(status);NSString *interface=ASVProfileInterface(uuid);if(status==3 && interface.length){interfaces[uuid]=interface;[names addObject:Get(c,@"name") ?: uuid];}}dispatch_group_leave(group);});}
    dispatch_group_notify(group,dispatch_get_main_queue(),^{if(generation!=self->_generation || !self->_wanted)return;NSString *error=nil;
        if(![self->_publishedInterfaces isEqual:interfaces]){
            if(![self->_engine replaceMatrix:self->_matrix interfaces:interfaces providerIDs:self->_providers error:&error]){[self fail:error];return;}
            ++self->_ipEpoch;
            for(NSString *uuid in [self->_publicIPs.allKeys copy])if(![self->_publicIPs[uuid][@"interface"] isEqual:interfaces[uuid]])[self->_publicIPs removeObjectForKey:uuid];
            self->_publishedInterfaces=[interfaces copy];
        }
        self->_names=[names componentsJoinedByString:@" + "];self->_status=interfaces.count==self->_originals.count?@"active":(interfaces.count?@"partial":@"connecting");
        self->_error=interfaces.count==self->_originals.count?nil:@"Assigned VPN unavailable: its applications are blocked";
        [self probeNextIP];
        if(Clock()-self->_started>60 && !interfaces.count){[self fail:@"No assigned VPN connected; restoring originals"];}
    });
}
@end
