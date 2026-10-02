#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <uuid/uuid.h>
#import <notify.h>
static id Get(id o,NSString *s) { SEL sel=NSSelectorFromString(s);return [o respondsToSelector:sel]?((id(*)(id,SEL))objc_msgSend)(o,sel):nil; }
static void Set(id o,NSString *s,id v) { ((void(*)(id,SEL,id))objc_msgSend)(o,NSSelectorFromString(s),v); }
static BOOL Wait(BOOL *done,int seconds) { NSDate *end=[NSDate dateWithTimeIntervalSinceNow:seconds];while(!*done && end.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];return *done; }
static BOOL Save(id manager,id c) {
 __block BOOL done=NO;__block BOOL ok=NO;
 ((void(*)(id,SEL,id,id,id))objc_msgSend)(manager,NSSelectorFromString(@"saveConfiguration:withCompletionQueue:handler:"),c,dispatch_get_main_queue(),^(NSError *e){printf("SAVE %s error=%ld %s\n",[[Get(c,@"name") description] UTF8String],(long)e.code,e.localizedDescription.UTF8String);ok=e==nil || e.code==9;done=YES;});
 return Wait(&done,12)&&ok;
}
static id AppControl(NSArray *configs,BOOL ready) {
 id session=[NSClassFromString(@"NEPolicySession") new];((void(*)(id,SEL,NSInteger))objc_msgSend)(session,NSSelectorFromString(@"setPriority:"),1);
 id direct=Get(NSClassFromString(@"NEPolicyResult"),@"scopeToDirectInterface");
 id chosen=ready?((id(*)(id,SEL,unsigned))objc_msgSend)(NSClassFromString(@"NEPolicyResult"),NSSelectorFromString(@"skipWithOrder:"),0):Get(NSClassFromString(@"NEPolicyResult"),@"drop");
 void(^add)(NSUUID*,id,unsigned,BOOL)=^(NSUUID *uuid,id outcome,unsigned order,BOOL real){NSArray *conditions=uuid?@[ ((id(*)(id,SEL,id))objc_msgSend)(NSClassFromString(@"NEPolicyCondition"),NSSelectorFromString(real?@"realApplication:":@"effectiveApplication:"),uuid),Get(NSClassFromString(@"NEPolicyCondition"),@"allInterfaces") ]:@[Get(NSClassFromString(@"NEPolicyCondition"),@"allInterfaces")];id policy=((id(*)(id,SEL,unsigned,id,id))objc_msgSend)([NSClassFromString(@"NEPolicy") alloc],NSSelectorFromString(@"initWithOrder:result:conditions:"),order,outcome,conditions);((NSUInteger(*)(id,SEL,id))objc_msgSend)(session,NSSelectorFromString(@"addPolicy:"),policy);};
 for(id c in configs){id vpn=Get(c,@"VPN")?:Get(c,@"appVPN");NSString *provider=Get(Get(vpn,@"protocol"),@"providerBundleIdentifier"),*owner=Get(c,@"application");for(NSString *bundle in @[provider?:@"",owner?:@""])if(bundle.length){NSArray *ids=((id(*)(id,SEL,id,unsigned))objc_msgSend)(NSClassFromString(@"NEProcessInfo"),NSSelectorFromString(@"copyUUIDsForBundleID:uid:"),bundle,501);for(NSUUID *uuid in ids)add(uuid,direct,10,getenv("ASV_PROVIDER_REAL_APP")!=NULL);printf("PROVIDER_DIRECT identities=%lu real=%d\n",(unsigned long)ids.count,getenv("ASV_PROVIDER_REAL_APP")!=NULL);}}
 for(NSString *bundle in @[@"mobi.secured.whatsmyip",@"com.monvpn.myip"]){NSArray *ids=((id(*)(id,SEL,id,unsigned))objc_msgSend)(NSClassFromString(@"NEProcessInfo"),NSSelectorFromString(@"copyUUIDsForBundleID:uid:"),bundle,501);for(NSUUID *uuid in ids)add(uuid,chosen,100,NO);}
 add(nil,direct,1000,NO);
 BOOL ok=((BOOL(*)(id,SEL))objc_msgSend)(session,NSSelectorFromString(@"apply"));printf("APP_CONTROL=%d ready=%d\n",ok,ready);return ok?session:nil;
}
int main(int argc,char **argv) { @autoreleasepool {
 setbuf(stdout,NULL);
 if(argc==2 && (!strcmp(argv[1],"split-off") || !strcmp(argv[1],"split-restore"))) {
   NSString *flag=@"/var/mobile/asv040-split-enabled.flag";
   BOOL restore=!strcmp(argv[1],"split-restore");
   BOOL enabled=[[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.plist"][@"enabled"] boolValue];
   if(!restore){[(enabled?@"1":@"0") writeToFile:flag atomically:YES encoding:NSUTF8StringEncoding error:nil];chmod(flag.UTF8String,0600);}
   BOOL wanted=restore && [[NSString stringWithContentsOfFile:flag encoding:NSUTF8StringEncoding error:nil] isEqual:@"1"];
   int token;notify_register_check("com.ratush.appsplitvpn.set",&token);notify_set_state(token,wanted?1:2);notify_post("com.ratush.appsplitvpn.set");
   NSDate *end=[NSDate dateWithTimeIntervalSinceNow:10];
   while(end.timeIntervalSinceNow>0){NSDictionary *state=[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.state.plist"];
     BOOL on=[[NSDictionary dictionaryWithContentsOfFile:@"/var/mobile/Library/Preferences/com.ratush.appsplitvpn.plist"][@"enabled"] boolValue];
     if(on==wanted && (wanted || [state[@"status"] isEqual:@"disabled"])){printf("SPLIT_SWITCH_RECONCILED=%d\n",wanted);return 0;}
     [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];
   }return 5;
 }
 dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension",RTLD_NOW);
 void *lib=dlopen("/usr/lib/system/libsystem_networkextension.dylib",RTLD_NOW);
 void *(*create)(const unsigned char*,int)=dlsym(lib,"ne_session_create");
 void (*start)(void*)=dlsym(lib,"ne_session_start"),(*stop)(void*)=dlsym(lib,"ne_session_stop");
 void (*status)(void*,dispatch_queue_t,void(^)(int))=dlsym(lib,"ne_session_get_status");
 id manager=Get(NSClassFromString(@"NEConfigurationManager"),@"sharedManager");
 NSString *backup=@"/var/mobile/asv040-profile-backup.archive";
 if(argc==2 && !strcmp(argv[1],"restore")) {
   NSData *data=[NSData dataWithContentsOfFile:backup];
   NSArray *old=[NSKeyedUnarchiver unarchiveObjectWithData:data];
   for(id c in old) { Save(manager,c);id vpn=Get(c,@"VPN");if(vpn && ((BOOL(*)(id,SEL))objc_msgSend)(vpn,NSSelectorFromString(@"isEnabled"))) { uuid_t b;[Get(c,@"identifier") getUUIDBytes:b];start(create(b,1)); } }return 0;
 }
 if(argc<3) return 2;
 __block NSArray *configs;__block BOOL done=NO;
 ((void(*)(id,SEL,id,id))objc_msgSend)(manager,NSSelectorFromString(@"loadConfigurationsWithCompletionQueue:handler:"),dispatch_get_main_queue(),^(NSArray *c,NSError *e){configs=c;done=YES;});
 if(!Wait(&done,12)) return 3;
 if(argc==3 && !strcmp(argv[1],"stats")) {
   id target=nil;for(id c in configs)if([[Get(c,@"identifier") UUIDString] isEqual:@(argv[2])])target=c;
   if(![Get(target,@"application") isEqual:@"com.wireguard.ios"])return 10;
   printf("STATS_PER_APP=%d\n",Get(target,@"appVPN")!=nil);
   id m=Get(target,@"appVPN")?Get(NSClassFromString(@"NETunnelProviderManager"),@"forPerAppVPN"):[NSClassFromString(@"NETunnelProviderManager") new];Set(m,@"setConfiguration:",target);
   __block BOOL loaded=NO;((void(*)(id,SEL,id))objc_msgSend)(m,NSSelectorFromString(@"loadFromPreferencesWithCompletionHandler:"),^(NSError *e){printf("STATS_LOAD error=%ld\n",(long)e.code);loaded=YES;});if(!Wait(&loaded,10))return 11;
   id connection=Get(m,@"connection");
   ((BOOL(*)(id,SEL))objc_msgSend)(connection,NSSelectorFromString(@"installNotify"));
   ((void(*)(id,SEL,BOOL))objc_msgSend)(connection,NSSelectorFromString(@"setInstalled:"),YES);
   printf("STATS_CONNECTION_STATUS=%ld\n",(long)((NSInteger(*)(id,SEL))objc_msgSend)(connection,NSSelectorFromString(@"status")));
   uint8_t zero=0;NSData *request=[NSData dataWithBytes:&zero length:1];NSError *error=nil;__block BOOL received=NO;
   BOOL sent=((BOOL(*)(id,SEL,id,NSError **,id))objc_msgSend)(Get(m,@"connection"),NSSelectorFromString(@"sendProviderMessage:returnError:responseHandler:"),request,&error,^(NSData *data){
     printf("STATS_BYTES=%lu\n",(unsigned long)data.length);
     NSString *text=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
     for(NSString *line in [text componentsSeparatedByString:@"\n"]){NSRange equal=[line rangeOfString:@"="];if(equal.location==NSNotFound)continue;NSString *key=[line substringToIndex:equal.location];
       if([@[@"endpoint",@"rx_bytes",@"tx_bytes",@"last_handshake_time_sec"] containsObject:key]){NSString *value=[line substringFromIndex:equal.location+1];NSCharacterSet *allowed=[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:[]"];if(value.length<=255 && [value rangeOfCharacterFromSet:allowed.invertedSet].location==NSNotFound)printf("WG_STATS %s=%s\n",key.UTF8String,value.UTF8String);}
     }received=YES;
   });printf("STATS_SENT=%d error=%ld\n",sent,(long)error.code);if(sent)Wait(&received,8);return received?0:12;
 }
 if(argc==3 && !strcmp(argv[1],"baseline")) {
   NSArray *originals=[NSKeyedUnarchiver unarchiveObjectWithData:[NSData dataWithContentsOfFile:backup]];
   id target=nil;for(id c in configs)if([[Get(c,@"identifier") UUIDString] isEqual:@(argv[2])])target=c;
   BOOL archived=NO;for(id c in originals)if([[Get(c,@"identifier") UUIDString] isEqual:@(argv[2])])archived=YES;
   if(!target || !archived || !Get(target,@"VPN") || Get(target,@"appVPN"))return 8;
   for(id c in originals){uuid_t b;[Get(c,@"identifier") getUUIDBytes:b];stop(create(b,1));}
   [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
   ((void(*)(id,SEL,BOOL))objc_msgSend)(Get(target,@"VPN"),NSSelectorFromString(@"setEnabled:"),YES);
   if(!Save(manager,target))return 9;
   id m=[NSClassFromString(@"NETunnelProviderManager") new];Set(m,@"setConfiguration:",target);
   __block BOOL loaded=NO;((void(*)(id,SEL,id))objc_msgSend)(m,NSSelectorFromString(@"loadFromPreferencesWithCompletionHandler:"),^(NSError *e){printf("BASELINE_LOAD error=%ld\n",(long)e.code);loaded=YES;});Wait(&loaded,10);
   NSError *error=nil;BOOL began=((BOOL(*)(id,SEL,id,NSError **))objc_msgSend)(Get(m,@"connection"),NSSelectorFromString(@"startVPNTunnelWithOptions:andReturnError:"),nil,&error);printf("BASELINE_START=%d error=%ld\n",began,(long)error.code);
   uuid_t b;[Get(target,@"identifier") getUUIDBytes:b];void *s=create(b,1);
   for(int n=0;n<8;n++){status(s,dispatch_get_main_queue(),^(int value){printf("BASELINE_STATUS=%d\n",value);});[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];if(n==1)printf("BASELINE_READY\n");}
   stop(s);[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
   for(id c in originals){Save(manager,c);if(((BOOL(*)(id,SEL))objc_msgSend)(Get(c,@"VPN"),NSSelectorFromString(@"isEnabled"))){uuid_t bytes;[Get(c,@"identifier") getUUIDBytes:bytes];start(create(bytes,1));}}
   printf("BASELINE_RESTORED\n");return 0;
 }
 NSMutableArray *old=[NSMutableArray array],*trials=[NSMutableArray array];
 for(int i=1;i<argc;i++) for(id c in configs) if([[Get(c,@"identifier") UUIDString] isEqual:@(argv[i])]) { [old addObject:[c copy]];[trials addObject:c]; }
 if(trials.count!=(NSUInteger)(argc-1)) return 4;
 // Never overwrite the rollback archive with an already converted configuration.
 for(id c in trials)if(!Get(c,@"VPN") || Get(c,@"appVPN")){printf("REFUSED: profile is already per-app; restore first\n");return 6;}
 NSData *data=[NSKeyedArchiver archivedDataWithRootObject:old requiringSecureCoding:NO error:nil];[data writeToFile:backup atomically:YES];chmod(backup.UTF8String,0600);
 NSMutableArray *sessions=[NSMutableArray array],*managers=[NSMutableArray array];id policies=nil;
 if(getenv("ASV_PROBE_CONTROL")){policies=AppControl(trials,NO);if(!policies)return 7;}
 for(id c in trials) {
   uuid_t originalBytes;[Get(c,@"identifier") getUUIDBytes:originalBytes];
   stop(create(originalBytes,1));
   [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:2]];
   id vpn=Get(c,@"VPN"), app=[NSClassFromString(@"NEVPNApp") new];
   Set(app,@"setProtocol:",[Get(vpn,@"protocol") copy]);
   ((void(*)(id,SEL,BOOL))objc_msgSend)(app,NSSelectorFromString(@"setEnabled:"),YES);
   ((void(*)(id,SEL,BOOL))objc_msgSend)(app,NSSelectorFromString(@"setNoRestriction:"),YES);
   id rule=((id(*)(id,SEL,id))objc_msgSend)([NSClassFromString(@"NEAppRule") alloc],NSSelectorFromString(@"initWithSigningIdentifier:"),sessions.count?@"com.monvpn.myip":@"mobi.secured.whatsmyip");
   ((void(*)(id,SEL,BOOL))objc_msgSend)(rule,NSSelectorFromString(@"setNoRestriction:"),YES);
   NSArray *appUUIDs=((id(*)(id,SEL,id,unsigned))objc_msgSend)(NSClassFromString(@"NEProcessInfo"),NSSelectorFromString(@"copyUUIDsForBundleID:uid:"),sessions.count?@"com.monvpn.myip":@"mobi.secured.whatsmyip",501);
   if(appUUIDs.count)Set(rule,@"setCachedMachOUUIDs:",appUUIDs);
   printf("APP_RULE_IDENTITIES=%lu\n",(unsigned long)appUUIDs.count);
   NSInteger type=((NSInteger(*)(id,SEL))objc_msgSend)(vpn,NSSelectorFromString(@"tunnelType"));printf("TUNNELTYPE old=%ld new=%ld\n",(long)type,(long)((NSInteger(*)(id,SEL))objc_msgSend)(app,NSSelectorFromString(@"tunnelType")));
   ((void(*)(id,SEL,NSInteger))objc_msgSend)(app,NSSelectorFromString(@"setTunnelType:"),type);
   NSString *cli=sessions.count?@"/var/jb/usr/bin/wget":@"/var/jb/usr/bin/curl";
   NSArray *cliUUIDs=((id(*)(id,SEL,id))objc_msgSend)(NSClassFromString(@"NEProcessInfo"),NSSelectorFromString(@"copyUUIDsForExecutable:"),cli);
   id cliRule=((id(*)(id,SEL,id))objc_msgSend)([NSClassFromString(@"NEAppRule") alloc],NSSelectorFromString(@"initWithSigningIdentifier:"),sessions.count?@"org.asv.probe.wget":@"org.asv.probe.curl");
   Set(cliRule,@"setCachedMachOUUIDs:",cliUUIDs);
   ((void(*)(id,SEL,BOOL))objc_msgSend)(cliRule,NSSelectorFromString(@"setNoRestriction:"),YES);
   NSMutableArray *rules=[NSMutableArray arrayWithObject:rule];
   if(sessions.count && getenv("ASV_PROBE_LEGACY_TELEGRAM")){
     NSArray *cloneUUIDs=((id(*)(id,SEL,id,unsigned))objc_msgSend)(NSClassFromString(@"NEProcessInfo"),NSSelectorFromString(@"copyUUIDsForBundleID:uid:"),@"ph.teleg.Telegrapf",501);
     if(cloneUUIDs.count){id clone=((id(*)(id,SEL,id))objc_msgSend)([NSClassFromString(@"NEAppRule") alloc],NSSelectorFromString(@"initWithSigningIdentifier:"),@"ph.teleg.Telegrapf");Set(clone,@"setCachedMachOUUIDs:",cloneUUIDs);((void(*)(id,SEL,BOOL))objc_msgSend)(clone,NSSelectorFromString(@"setNoRestriction:"),YES);[rules addObject:clone];}
   }
   if(!getenv("ASV_PROBE_NATIVE_RULES"))[rules addObject:cliRule];
   Set(app,@"setAppRules:",rules);Set(c,@"setVPN:",nil);Set(c,@"setAppVPN:",app);
   NSMutableArray *errors=[NSMutableArray array];BOOL valid=((BOOL(*)(id,SEL,id))objc_msgSend)(c,NSSelectorFromString(@"checkValidityAndCollectErrors:"),errors);printf("VALID %d %s\n",valid,errors.description.UTF8String);
   if(!Save(manager,c)) break;
   [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
   id m=Get(NSClassFromString(@"NETunnelProviderManager"),@"forPerAppVPN");Set(m,@"setConfiguration:",c);id conn=Get(m,@"connection");
   __block BOOL loaded=NO;((void(*)(id,SEL,id))objc_msgSend)(m,NSSelectorFromString(@"loadFromPreferencesWithCompletionHandler:"),^(NSError *e){printf("LOAD error=%ld\n",(long)e.code);loaded=YES;});Wait(&loaded,10);
   printf("MANAGER enabled=%d id=%s installed=%d\n",((BOOL(*)(id,SEL))objc_msgSend)(m,NSSelectorFromString(@"isEnabled")),[[Get(m,@"identifier") description] UTF8String],((BOOL(*)(id,SEL))objc_msgSend)(conn,NSSelectorFromString(@"installed")));
   ((BOOL(*)(id,SEL))objc_msgSend)(conn,NSSelectorFromString(@"installNotify"));
   ((void(*)(id,SEL,BOOL))objc_msgSend)(conn,NSSelectorFromString(@"setInstalled:"),YES);
   printf("CONNECTION manager=%d options=%s\n",Get(conn,@"manager")==m,[[Get(m,@"copyCurrentUserStartOptions") allKeys] description].UTF8String);
   NSError *err=nil;BOOL began=((BOOL(*)(id,SEL,id,NSError **))objc_msgSend)(conn,NSSelectorFromString(@"startVPNTunnelWithOptions:andReturnError:"),nil,&err);printf("START result=%d error=%ld %s\n",began,(long)err.code,err.localizedDescription.UTF8String);
   [managers addObject:m];uuid_t bytes;[Get(c,@"identifier") getUUIDBytes:bytes];void *s=create(bytes,2);[sessions addObject:[NSValue valueWithPointer:s]];
 }
 int steps=getenv("ASV_PROBE_STEPS")?atoi(getenv("ASV_PROBE_STEPS")):8;steps=MAX(8,MIN(36,steps));
 for(int n=0;n<steps;n++) { [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:5]];
   if(n==1){void *sc=dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration",RTLD_NOW);CFDictionaryRef(*copy)(void*,CFArrayRef,CFArrayRef)=dlsym(sc,"SCDynamicStoreCopyMultiple");if(copy){NSDictionary *states=CFBridgingRelease(copy(NULL,NULL,(__bridge CFArrayRef)@[@"State:/Network/Service/.*/IPv[46]"]));
     if(!policies){policies=[NSClassFromString(@"NEPolicySession") new];((void(*)(id,SEL,NSInteger))objc_msgSend)(policies,NSSelectorFromString(@"setPriority:"),1);}
     BOOL ready=trials.count==2 && sessions.count==trials.count;
     for(NSValue *value in sessions){__block BOOL answered=NO;__block int current=0;status(value.pointerValue,dispatch_get_main_queue(),^(int s){current=s;answered=YES;});Wait(&answered,5);if(!answered || current!=3)ready=NO;}
     for(NSUInteger i=0;i<trials.count;i++) { NSString *service=[Get(Get(Get(trials[i],@"appVPN"),@"protocol"),@"identifier") description];NSString *interface=nil;
       for(NSString *key in states)if([key containsString:service]){interface=states[key][@"InterfaceName"];printf("NETWORK %s %s\n",key.UTF8String,[states[key] description].UTF8String);}
       if(!interface){ready=NO;continue;}NSString *executable=i?@"/var/jb/usr/bin/wget":@"/var/jb/usr/bin/curl";
       NSArray *ids=((id(*)(id,SEL,id))objc_msgSend)(NSClassFromString(@"NEProcessInfo"),NSSelectorFromString(@"copyUUIDsForExecutable:"),executable);
       if(getenv("ASV_PROBE_NATIVE_RULES")){printf("NATIVE_APP_ROUTE -> %s\n",interface.UTF8String);continue;}
       for(NSUUID *uuid in ids) { id condition=((id(*)(id,SEL,id))objc_msgSend)(NSClassFromString(@"NEPolicyCondition"),NSSelectorFromString(getenv("ASV_PROBE_REAL_APP")?@"realApplication:":@"effectiveApplication:"),uuid);id result;
         if(getenv("ASV_PROBE_SOCKET_SCOPE"))result=((id(*)(id,SEL,id))objc_msgSend)(NSClassFromString(@"NEPolicyResult"),NSSelectorFromString(@"scopeSocketToInterfaceName:"),interface);
         else result=((id(*)(id,SEL,id,NSInteger))objc_msgSend)(NSClassFromString(@"NEPolicyResult"),NSSelectorFromString(@"tunnelIPToInterfaceName:secondaryResultType:"),interface,getenv("ASV_PROBE_SECONDARY_PASS")?1:0);
         id policy=((id(*)(id,SEL,unsigned,id,id))objc_msgSend)([NSClassFromString(@"NEPolicy") alloc],NSSelectorFromString(@"initWithOrder:result:conditions:"),100,result,@[condition,Get(NSClassFromString(@"NEPolicyCondition"),@"allInterfaces")]);((NSUInteger(*)(id,SEL,id))objc_msgSend)(policies,NSSelectorFromString(@"addPolicy:"),policy);
       }printf("ROUTE %s -> %s identities=%lu\n",executable.UTF8String,interface.UTF8String,(unsigned long)ids.count);
     }
     if(ready && getenv("ASV_PROBE_CONTROL")){id next=AppControl(trials,YES);if(next){((BOOL(*)(id,SEL))objc_msgSend)(policies,NSSelectorFromString(@"removeAllPolicies"));((BOOL(*)(id,SEL))objc_msgSend)(policies,NSSelectorFromString(@"apply"));policies=next;}else ready=NO;}
     BOOL applied=((BOOL(*)(id,SEL))objc_msgSend)(policies,NSSelectorFromString(@"apply"));
     printf("POLICIES_APPLIED=%d %s\n",applied,(ready && applied)?"READY":"NOT_READY");
   }}
   for(NSValue *v in sessions) { status(v.pointerValue,dispatch_get_main_queue(),^(int s){NSUInteger index=[sessions indexOfObject:v];printf("SESSION %lu STATUS %d\n",(unsigned long)index,s);if(s==1){id conn=Get(managers[index],@"connection");((void(*)(id,SEL,id))objc_msgSend)(conn,NSSelectorFromString(@"fetchLastDisconnectErrorWithCompletionHandler:"),^(NSError *err){printf("DISCONNECT domain=%s code=%ld\n",err.domain.UTF8String,(long)err.code);});}fflush(stdout);}); }
   if(n==1)for(NSUInteger i=0;i<trials.count;i++){uuid_t b;[Get(trials[i],@"identifier") getUUIDBytes:b];status(create(b,1),dispatch_get_main_queue(),^(int s){printf("DEVICE_SESSION %lu STATUS %d\n",(unsigned long)i,s);});}
 }
 for(NSValue *v in sessions) stop(v.pointerValue);
 policies=nil;
 [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:3]];
 for(id c in old) { Save(manager,c);id vpn=Get(c,@"VPN");if(vpn && ((BOOL(*)(id,SEL))objc_msgSend)(vpn,NSSelectorFromString(@"isEnabled"))) { uuid_t b;[Get(c,@"identifier") getUUIDBytes:b];start(create(b,1)); } }
 printf("RESTORED\n");
 }return 0; }
