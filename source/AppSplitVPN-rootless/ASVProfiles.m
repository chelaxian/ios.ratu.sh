#import "ASVProfiles.h"
#import "Shared.h"
#import <objc/message.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <notify.h>
#import <uuid/uuid.h>
static NSArray *catalog;
static NSMutableDictionary *configurations;
static NSMutableDictionary *sessions;
static NSMutableDictionary *sessionTypes;
static NSMutableDictionary *clientManagers;
static BOOL loading;
static id Get(id o,NSString *s) { SEL sel=NSSelectorFromString(s);return [o respondsToSelector:sel]?((id(*)(id,SEL))objc_msgSend)(o,sel):nil; }
static id Manager(void) { return Get(NSClassFromString(@"NEConfigurationManager"),@"sharedManager"); }
static void *Session(NSString *uuid) {
 if(!sessions){sessions=[NSMutableDictionary dictionary];sessionTypes=[NSMutableDictionary dictionary];}
 int type=Get(configurations[uuid],@"appVPN")?2:1;NSValue *saved=sessions[uuid];if(saved && [sessionTypes[uuid] intValue]==type)return saved.pointerValue;
 if(saved){void(*release)(void*)=dlsym(RTLD_DEFAULT,"ne_session_release");if(release)release(saved.pointerValue);[sessions removeObjectForKey:uuid];}
 void *(*create)(const unsigned char*,int)=dlsym(RTLD_DEFAULT,"ne_session_create");
 NSUUID *idValue=[[NSUUID alloc] initWithUUIDString:uuid];if(!create||!idValue)return NULL;
 uuid_t bytes;[idValue getUUIDBytes:bytes];void *session=create(bytes,type);
 if(session){sessions[uuid]=[NSValue valueWithPointer:session];sessionTypes[uuid]=@(type);}return session;
}
NSArray *ASVProfilesCatalog(void) { return catalog ?: [NSArray arrayWithContentsOfFile:ASV_PROFILE_CATALOG] ?: @[]; }
NSDictionary *ASVProfileRecord(NSString *uuid) { for(NSDictionary *r in ASVProfilesCatalog()) if([r[@"id"] isEqual:uuid])return r;return nil; }
void ASVProfilesRefresh(void) {
 if(loading)return;id manager=Manager();SEL sel=NSSelectorFromString(@"loadConfigurationsWithCompletionQueue:handler:");if(![manager respondsToSelector:sel])return;
 loading=YES;
 ((void(*)(id,SEL,id,id))objc_msgSend)(manager,sel,dispatch_get_main_queue(),^(NSArray *configs,NSError *error){
   loading=NO;if(error)return;
   NSMutableArray *records=[NSMutableArray array];NSMutableDictionary *all=[NSMutableDictionary dictionary];
   for(id c in configs) {
     id vpn=Get(c,@"VPN") ?: Get(c,@"appVPN");NSString *uuid=[Get(c,@"identifier") UUIDString];if(!vpn||!uuid.length)continue;
     NSString *owner=Get(c,@"application") ?: Get(Get(vpn,@"protocol"),@"providerBundleIdentifier") ?: @"";
     NSString *name=Get(c,@"name") ?: uuid;
     if([name hasPrefix:@"com.apple."])continue;
     all[uuid]=c;
     BOOL enabled=((BOOL(*)(id,SEL))objc_msgSend)(vpn,NSSelectorFromString(@"isEnabled"));
     [records addObject:@{@"id":uuid,@"name":name,@"owner":owner,@"serviceID":[Get(Get(vpn,@"protocol"),@"identifier") description] ?: @"",@"enabled":@(enabled),@"perApp":@(Get(c,@"appVPN")!=nil)}];
   }
   configurations=all;catalog=[records sortedArrayUsingComparator:^NSComparisonResult(id a,id b){ return [a[@"name"] localizedCaseInsensitiveCompare:b[@"name"]]; }];
   [catalog writeToFile:ASV_PROFILE_CATALOG atomically:YES];chmod(ASV_PROFILE_CATALOG.UTF8String,0644);notify_post(ASV_PROFILES_NOTIFY);
 });
}
void ASVProfileStatus(NSString *uuid,void (^completion)(NSInteger)) {
 void *s=Session(uuid);void(*status)(void*,dispatch_queue_t,void(^)(int))=dlsym(RTLD_DEFAULT,"ne_session_get_status");
 if(!s||!status){completion(0);return;}status(s,dispatch_get_main_queue(),^(int value){completion(value);});
}
void ASVProfileStop(NSString *uuid) { void *s=Session(uuid);void(*stop)(void*)=dlsym(RTLD_DEFAULT,"ne_session_stop");if(s&&stop)stop(s); }
NSString *ASVProfileInterface(NSString *uuid) {
 static void *sc; if(!sc)sc=dlopen("/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration",RTLD_NOW);
 CFDictionaryRef(*copy)(void*,CFArrayRef,CFArrayRef)=dlsym(sc,"SCDynamicStoreCopyMultiple");if(!copy)return nil;
 NSDictionary *states=CFBridgingRelease(copy(NULL,NULL,(__bridge CFArrayRef)@[@"State:/Network/Service/.*/IPv[46]"]));
 NSString *serviceID=ASVProfileRecord(uuid)[@"serviceID"];
 if(!serviceID.length)return nil;
 for(NSString *key in states)if([key containsString:[NSString stringWithFormat:@"/Service/%@/",serviceID]]) { NSString *name=states[key][@"InterfaceName"];if([name isKindOfClass:NSString.class] && ([name hasPrefix:@"utun"] || [name hasPrefix:@"ipsec"] || [name hasPrefix:@"ppp"]))return name; }
 return nil;
}
void ASVProfileConnect(NSString *uuid,BOOL (^shouldStart)(void),void (^completion)(BOOL,NSString*)) {
 if(!shouldStart || !shouldStart()){completion(NO,@"Cancelled");return;}
 id cfg=configurations[uuid];id vpn=Get(cfg,@"VPN") ?: Get(cfg,@"appVPN");
 if(!cfg||!vpn){completion(NO,@"Profile unavailable");ASVProfilesRefresh();return;}
 id candidate=[cfg copy];id tunnel=Get(candidate,@"VPN") ?: Get(candidate,@"appVPN");
 ((void(*)(id,SEL,BOOL))objc_msgSend)(tunnel,NSSelectorFromString(@"setEnabled:"),YES);
 ((void(*)(id,SEL,id,id,id))objc_msgSend)(Manager(),NSSelectorFromString(@"saveConfiguration:withCompletionQueue:handler:"),candidate,dispatch_get_main_queue(),^(NSError *error){
   if(error&&error.code!=9){completion(NO,[NSString stringWithFormat:@"Configuration error %ld",(long)error.code]);return;}
   configurations[uuid]=candidate;
   if(!shouldStart()){completion(NO,@"Cancelled");return;}
   // Give nesessionmanager the saved configuration before requesting a start.
   dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
     if(!shouldStart()){completion(NO,@"Cancelled");return;}
     Class cls=NSClassFromString(@"NETunnelProviderManager");
     id m=Get(candidate,@"appVPN")?Get(cls,@"forPerAppVPN"):[cls new];
     ((void(*)(id,SEL,id))objc_msgSend)(m,NSSelectorFromString(@"setConfiguration:"),candidate);
     ((void(*)(id,SEL,id))objc_msgSend)(m,NSSelectorFromString(@"loadFromPreferencesWithCompletionHandler:"),^(NSError *loadError){
       if(loadError){completion(NO,[NSString stringWithFormat:@"Profile load error %ld",(long)loadError.code]);return;}
       if(!shouldStart()){completion(NO,@"Cancelled");return;}
       NSError *startError=nil;BOOL began=((BOOL(*)(id,SEL,id,NSError **))objc_msgSend)(Get(m,@"connection"),NSSelectorFromString(@"startVPNTunnelWithOptions:andReturnError:"),nil,&startError);
       if(!clientManagers)clientManagers=[NSMutableDictionary dictionary];clientManagers[uuid]=m;
       completion(began,began?nil:[NSString stringWithFormat:@"Start error %ld",(long)startError.code]);ASVProfilesRefresh();
     });
   });
 });
}
