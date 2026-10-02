#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
static id Get(id o,NSString *s) { SEL sel=NSSelectorFromString(s);return [o respondsToSelector:sel]?((id(*)(id,SEL))objc_msgSend)(o,sel):nil; }
int main(void) { @autoreleasepool {
 dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension",RTLD_NOW);
 for (NSString *name in @[@"NEVirtualInterfaceParameters"]) {
   Class c=NSClassFromString(name);printf("CLASS %s\n",name.UTF8String);
   for (int meta=0;meta<2;meta++) { unsigned count=0;Method *methods=class_copyMethodList(meta?object_getClass(c):c,&count);
     for(unsigned i=0;i<count;i++) printf("%c %s %s\n",meta?'+':'-',sel_getName(method_getName(methods[i])),method_getTypeEncoding(methods[i]));free(methods);
   }
 }
 id perApp=Get(NSClassFromString(@"NETunnelProviderManager"),@"forPerAppVPN");id connection=Get(perApp,@"connection");
 for(id object in @[perApp,connection]) for(Class cls=object_getClass(object);cls;cls=class_getSuperclass(cls)) { unsigned count;Ivar *ivars=class_copyIvarList(cls,&count);for(unsigned j=0;j<count;j++){const char *n=ivar_getName(ivars[j]),*t=ivar_getTypeEncoding(ivars[j]);if(strstr(n,"session")||strstr(n,"Session")||strstr(n,"type")||strstr(n,"Type"))printf("IVAR %s %s %s value=%ld\n",class_getName(cls),n,t,(long)(!strcmp(t,"i")?*(int *)((char *)(__bridge void*)object+ivar_getOffset(ivars[j])):!strcmp(t,"q")?*(NSInteger *)((char *)(__bridge void*)object+ivar_getOffset(ivars[j])):-1));}free(ivars); }
 id manager=Get(NSClassFromString(@"NEConfigurationManager"),@"sharedManager");
 SEL load=NSSelectorFromString(@"loadConfigurationsWithCompletionQueue:handler:");
 __block BOOL done=NO;
 ((void(*)(id,SEL,dispatch_queue_t,id))objc_msgSend)(manager,load,dispatch_get_main_queue(),^(NSArray *configs,NSError *error){
   printf("CATALOG error=%ld count=%lu\n",(long)error.code,(unsigned long)configs.count);
   for(id c in configs) {
     id vpn=Get(c,@"VPN"),app=Get(c,@"appVPN");id p=Get(vpn?:app,@"protocol");
     if([@[@"02414AFC-4D04-468C-A61C-42EFF2445475",@"E66EBF67-1B96-4D36-99A4-FE95DAC4D328"] containsObject:[Get(c,@"identifier") UUIDString]])for(NSString *name in @[@"includeAllNetworks",@"enforceRoutes",@"excludeLocalNetworks"]){SEL sel=NSSelectorFromString(name);if([p respondsToSelector:sel])printf("RESEARCH_PROTOCOL_FLAG %s %s=%d\n",[[Get(c,@"identifier") UUIDString] UTF8String],name.UTF8String,((BOOL(*)(id,SEL))objc_msgSend)(p,sel));}
     if([[Get(c,@"identifier") UUIDString] isEqual:@"02414AFC-4D04-468C-A61C-42EFF2445475"]){
       NSDictionary *values=Get(p,@"providerConfiguration");NSString *text=values[@"wgQuickConfig"];
       if([text isKindOfClass:NSString.class])for(NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){
         NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:@"^\\s*Endpoint\\s*=\\s*([A-Za-z0-9.\\[\\]:-]+)\\s*$" options:NSRegularExpressionCaseInsensitive error:nil];
         NSTextCheckingResult *match=[regex firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
         if(match)printf("RESEARCH_WG_ENDPOINT=%s\n",[line substringWithRange:[match rangeAtIndex:1]].UTF8String);
       }
     }
     if(vpn||app)printf("SERVICE %s %s\n",[[Get(c,@"name") description] UTF8String],[[Get(p,@"identifier") description] UTF8String]);
     printf("PROFILE %s name=%s owner=%s VPN=%d appVPN=%d enabled=%d provider=%s\n",[[Get(c,@"identifier") UUIDString] UTF8String],[[Get(c,@"name") description] UTF8String],[[Get(c,@"application") description] UTF8String],vpn!=nil,app!=nil,((BOOL(*)(id,SEL))objc_msgSend)(c,NSSelectorFromString(@"isEnabled")),[[Get(p,@"providerBundleIdentifier") description] UTF8String]);
     if(vpn && Get(p,@"providerBundleIdentifier")) {
       id trial=[c copy]; NSUUID *uuid=[NSUUID UUID];SEL per=NSSelectorFromString(@"setPerAppUUID:andSafariDomains:");
       BOOL changed=((BOOL(*)(id,SEL,id,id))objc_msgSend)(trial,per,uuid.UUIDString,@[]);
       id av=Get(trial,@"appVPN");
       printf("CONVERT_IN_MEMORY %s result=%d VPN=%d appVPN=%d type=%ld\n",[[Get(c,@"name") description] UTF8String],changed,Get(trial,@"VPN")!=nil,av!=nil,(long)(av?((NSInteger(*)(id,SEL))objc_msgSend)(av,NSSelectorFromString(@"tunnelType")):0));
     }
   }done=YES;
 });
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:12];while(!done && deadline.timeIntervalSinceNow>0) [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
 }return 0; }
