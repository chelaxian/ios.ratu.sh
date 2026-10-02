#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "ASVXPC.h"
#import <notify.h>
#import <stdlib.h>
#import <string.h>
#import <dlfcn.h>
#import <fcntl.h>
#import <sys/socket.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>
#import "Shared.h"

// Inert without a root-owned, validated ownership manifest. No provider-specific
// connectors, no packet hot-path interception, no changes to other VPNs/MDM.
static __thread BOOL legacyScope;
static xpc_object_t (*originalSend)(xpc_connection_t,xpc_object_t);
static int (*originalSet)(int,int,int,const void *,socklen_t);
static int readyToken=-1;

static NSSet *ASVOwnedLegacyIDs(void) {
    // Read only at interface creation, not on the packet hot path. Validate the
    // directory as well as the file, and avoid a path-replacement TOCTOU race.
    int directory=open(ASV_MULTI_DIR.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW);
    if(directory<0)return [NSSet set];
    struct stat parent;
    if(fstat(directory,&parent)!=0 || !S_ISDIR(parent.st_mode) || parent.st_uid!=0 || (parent.st_mode&077)){close(directory);return [NSSet set];}
    int fd=openat(directory,"multi-manifest.plist",O_RDONLY|O_NOFOLLOW);
    close(directory);
    if(fd<0)return [NSSet set];
    struct stat st;
    if(fstat(fd,&st)!=0 || !S_ISREG(st.st_mode) || st.st_uid!=0 || (st.st_mode&022) || st.st_nlink!=1 || st.st_size<=0 || st.st_size>65536){close(fd);return [NSSet set];}
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)st.st_size];
    size_t offset=0;while(offset<data.length){ssize_t size=read(fd,(char *)data.mutableBytes+offset,data.length-offset);if(size<=0)break;offset+=(size_t)size;}
    close(fd);if(offset!=data.length)return [NSSet set];
    id value=[NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:NULL error:nil];
    if(![value isKindOfClass:NSDictionary.class] || ![value[@"version"] isEqual:@1] || ![value[@"enabled"] isEqual:@YES])return [NSSet set];
    NSArray *raw=value[@"legacyPacketIDs"];if(![raw isKindOfClass:NSArray.class] || raw.count>64)return [NSSet set];
    NSMutableSet *ids=[NSMutableSet set];
    for(id name in raw){if(![name isKindOfClass:NSString.class])return [NSSet set];NSUUID *uuid=[[NSUUID alloc] initWithUUIDString:name];if(!uuid)return [NSSet set];[ids addObject:uuid.UUIDString];}
    return ids;
}
static BOOL ASVOwnedConfiguration(id configuration) {
    if(!configuration || ![configuration respondsToSelector:@selector(appVPN)] || ![configuration respondsToSelector:@selector(identifier)])return NO;
    id vpn=((id(*)(id,SEL))objc_msgSend)(configuration,@selector(appVPN));
    if(![vpn respondsToSelector:@selector(tunnelType)] || ((NSInteger(*)(id,SEL))objc_msgSend)(vpn,@selector(tunnelType))!=1)return NO;
    id uuid=((id(*)(id,SEL))objc_msgSend)(configuration,@selector(identifier));
    return [uuid isKindOfClass:NSUUID.class] && [ASVOwnedLegacyIDs() containsObject:[uuid UUIDString]];
}
static xpc_object_t ASVSend(xpc_connection_t connection,xpc_object_t message) {
    if(!legacyScope || xpc_get_type(message)!=XPC_TYPE_DICTIONARY)return originalSend(connection,message);
    const char *name=xpc_dictionary_get_string(message,"socket-control-name");
    if(!name || strcmp(name,"com.apple.net.utun_control"))return originalSend(connection,message);
    xpc_object_t options=xpc_dictionary_get_value(message,"socket-options");
    if(!options || xpc_get_type(options)!=XPC_TYPE_ARRAY)return originalSend(connection,message);
    NSMutableArray *restore=[NSMutableArray array];
    xpc_array_apply(options,^bool(__unused size_t index,xpc_object_t option){
        if(xpc_get_type(option)!=XPC_TYPE_DICTIONARY || xpc_dictionary_get_uint64(option,"interface-option")!=1)return true;
        size_t size=0;const void *data=xpc_dictionary_get_data(option,"interface-option-data",&size);
        if(!data || size!=sizeof(uint32_t))return true;
        uint32_t flags;memcpy(&flags,data,sizeof flags);if(!(flags&4))return true;
        [restore addObject:@{ @"option":option,@"flags":@(flags) }];
        flags&=~UINT32_C(4);xpc_dictionary_set_data(option,"interface-option-data",&flags,sizeof flags);return true;
    });
    xpc_object_t reply=originalSend(connection,message);
    for(NSDictionary *entry in restore){uint32_t flags=[entry[@"flags"] unsignedIntValue];xpc_dictionary_set_data(entry[@"option"],"interface-option-data",&flags,sizeof flags);}
    return reply;
}
static int ASVSet(int fd,int level,int option,const void *value,socklen_t length) {
    if(!legacyScope || level!=2 || option!=1 || !value || length!=sizeof(uint32_t))return originalSet(fd,level,option,value,length);
    uint32_t flags;memcpy(&flags,value,sizeof flags);
    if(!(flags&4))return originalSet(fd,level,option,value,length);
    flags&=~UINT32_C(4);
    int result=originalSet(fd,level,option,&flags,sizeof flags),savedError=errno;
    // XNU refuses FLAGS after connect, including an idempotent setting. Accept
    // only EINVAL and an independently confirmed exact current value.
    if(result<0 && savedError==EINVAL){uint32_t current=0;socklen_t size=sizeof current;
        if(getsockopt(fd,level,option,&current,&size)==0 && size==sizeof current && current==flags)return 0;
    }
    errno=savedError;return result;
}

%hook NESMVPNSession
- (void)plugin:(id)plugin didRequestVirtualInterfaceWithParameters:(id)parameters completionHandler:(id)completion {
    id configuration=[(id)self respondsToSelector:@selector(configuration)]?((id(*)(id,SEL))objc_msgSend)((id)self,@selector(configuration)):nil;
    BOOL previous=legacyScope;legacyScope=ASVOwnedConfiguration(configuration);
    @try { %orig; } @finally { legacyScope=previous; }
}
%end
%ctor {
    if(strcmp(getprogname(),"nesessionmanager"))return;
    Class cls=NSClassFromString(@"NESMVPNSession");SEL selector=@selector(plugin:didRequestVirtualInterfaceWithParameters:completionHandler:);
    Method method=class_getInstanceMethod(cls,selector);
    if(!method || method_getNumberOfArguments(method)!=5)return;
    char *returns=method_copyReturnType(method);BOOL correct=returns && !strcmp(returns,"v");free(returns);if(!correct)return;
    for(unsigned i=2;i<5;i++){char *type=method_copyArgumentType(method,i);correct=type && type[0]=='@';free(type);if(!correct)return;}
    void *send=dlsym(RTLD_DEFAULT,"xpc_connection_send_message_with_reply_sync"),*set=dlsym(RTLD_DEFAULT,"setsockopt");
    if(!send || !set)return;
    MSHookFunction(send,(void *)ASVSend,(void **)&originalSend);
    MSHookFunction(set,(void *)ASVSet,(void **)&originalSet);
    %init;
    if(notify_register_check(ASV_MULTI_COMPAT_READY,&readyToken)==NOTIFY_STATUS_OK){notify_set_state(readyToken,((uint64_t)getpid()<<32)|1);notify_post(ASV_MULTI_COMPAT_READY);}
}
