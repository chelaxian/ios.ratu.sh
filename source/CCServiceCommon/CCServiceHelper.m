#import <Foundation/Foundation.h>
#import <notify.h>
#import <spawn.h>
#import <sys/wait.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <sys/socket.h>
#import <sys/select.h>
#import <netinet/in.h>
#import <arpa/inet.h>
#import <fcntl.h>
#import <signal.h>
#import <unistd.h>
#import <errno.h>
#import <limits.h>
#import <pwd.h>
extern int proc_listallpids(void *, int);
extern int proc_pidpath(int, void *, uint32_t);
extern char **environ;
static NSString *const prefix = @"/var/jb";
static NSString *const stateDir = @"/var/jb/var/lib/ratu-cc";
static const char *const domains[] = {"user/501", "system"};
static char *safeEnv[] = {"PATH=/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin", "HOME=/var/root", "TMPDIR=/var/jb/var/tmp", NULL};
static NSString *Label(void) { return @SERVICE_LABEL; }
static NSString *JobPath(void) { return [prefix stringByAppendingFormat:@"/Library/LaunchDaemons/%@.plist", Label()]; }
static NSString *Marker(void) { return [stateDir stringByAppendingFormat:@"/%@.off", Label()]; }
static NSString *MobilePrefs(void) { struct passwd *user=getpwuid(501);NSString *home=user && user->pw_dir?@(user->pw_dir):@"/var/mobile";return [home stringByAppendingString:@"/Library/Preferences/com.catmcp.server.plist"]; }
static BOOL Exists(NSString *p) { return [[NSFileManager defaultManager] fileExistsAtPath:p]; }
static int Run(NSString *exe, NSArray<NSString *> *args) {
    char *argv[32] = {0}; argv[0] = (char *)exe.fileSystemRepresentation;
    if (args.count > 29) return 64;
    for (NSUInteger i=0; i<args.count; i++) argv[i+1] = (char *)args[i].UTF8String;
    pid_t pid = 0; int status = 0;
    posix_spawn_file_actions_t actions; posix_spawn_file_actions_init(&actions);
    posix_spawn_file_actions_addopen(&actions, STDOUT_FILENO, "/dev/null", O_WRONLY, 0);
    posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0);
    int rc = posix_spawn(&pid, argv[0], &actions, NULL, argv, safeEnv);
    posix_spawn_file_actions_destroy(&actions);
    if (rc) return rc;
    CFTimeInterval deadline=NSProcessInfo.processInfo.systemUptime+2;
    while(NSProcessInfo.processInfo.systemUptime<deadline){
        pid_t result=waitpid(pid,&status,WNOHANG);
        if(result==pid)return WIFEXITED(status)?WEXITSTATUS(status):126;
        if(result<0 && errno!=EINTR)return 126;
        usleep(10000);
    }
    kill(pid,SIGKILL);while(waitpid(pid,&status,0)<0 && errno==EINTR){}
    return 124;
}
static int Launch(NSArray<NSString *> *args) { return Run(@"/var/jb/bin/launchctl",args); }
static BOOL PortOpen(int port) {
    int fd=socket(AF_INET,SOCK_STREAM,0); if(fd<0)return NO;
    fcntl(fd,F_SETFL,O_NONBLOCK);
    struct sockaddr_in a={0};a.sin_family=AF_INET;a.sin_port=htons(port);a.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    int r=connect(fd,(struct sockaddr *)&a,sizeof(a));
    if(r<0 && errno==EINPROGRESS){fd_set set;FD_ZERO(&set);FD_SET(fd,&set);struct timeval tv={0,150000};
        if(select(fd+1,NULL,&set,NULL,&tv)>0){int err=0;socklen_t len=sizeof(err);r=getsockopt(fd,SOL_SOCKET,SO_ERROR,&err,&len)==0 && !err ? 0:-1;}}
    close(fd);return r==0;
}
static BOOL ServiceProcess(NSString *exe) {
    NSString *name=exe.lastPathComponent;
    BOOL matches=NO;
#if SERVICE_KIND == 1
    matches=[@[@"sshd",@"sshd-session",@"sshd-auth"] containsObject:name];
#elif SERVICE_KIND == 2
    matches=[@[@"frida-server",@"frida-server-wrapper"] containsObject:name];
#else
    matches=[@[@"catmcp",@"catmcp-launcher"] containsObject:name];
#endif
    if(!matches)return NO;
    NSString *physical=exe.stringByResolvingSymlinksInPath;
    NSString *jb=prefix.stringByResolvingSymlinksInPath;
    return [physical hasPrefix:[jb stringByAppendingString:@"/"]];
}
static int Processes(int sig) {
    int count=proc_listallpids(NULL,0);if(count<=0)return -1;
    size_t bytes=(size_t)(count+64)*sizeof(pid_t);pid_t *pids=calloc(1,bytes);if(!pids)return -1;
    int got=proc_listallpids(pids,(int)bytes);int found=0;
    for(int i=0;i<got && i<(int)(bytes/sizeof(pid_t));i++){char path[4096]={0};
        if(pids[i]>1 && pids[i]!=getpid() && proc_pidpath(pids[i],path,sizeof(path))>0 && ServiceProcess(@(path))){found++;if(sig)kill(pids[i],sig);}}
    free(pids);return found;
}
static NSArray<NSNumber *> *Ports(void) {
#if SERVICE_KIND == 1
    NSDictionary *s=[NSDictionary dictionaryWithContentsOfFile:JobPath()][@"Sockets"];
    NSMutableArray *ports=[NSMutableArray array];
    for(id item in s.allValues){NSArray *entries=[item isKindOfClass:NSArray.class]?item:@[item];for(NSDictionary *d in entries){id v=d[@"SockServiceName"];int p=[v isEqual:@"ssh"]?22:[v intValue];if(p>0 && p<65536 && ![ports containsObject:@(p)])[ports addObject:@(p)];}}
    return ports.count?ports:@[@22,@2222];
#elif SERVICE_KIND == 2
    return @[@27042];
#else
    NSDictionary *p=[NSDictionary dictionaryWithContentsOfFile:MobilePrefs()];
    int port=[p[@"port"] intValue];return @[@(port>0 && port<65536?port:9000)];
#endif
}
static BOOL Listening(void){for(NSNumber *p in Ports())if(PortOpen(p.intValue))return YES;return NO;}
static NSInteger State(void){
#if SERVICE_KIND == 1
    if(Exists([stateDir stringByAppendingString:@"/sshd.local-active"]) && Listening())return 2;
    return Listening()?1:0;
#else
    int processes=Processes(0);
    if(processes<0)return -1;
    return processes>0 && Listening()?1:0;
#endif
}
static void Publish(NSInteger value,BOOL changed){
    // Unknown/error is not OFF. Status polls must never change the service or
    // create a notification feedback loop in the module.
    if(value<0){puts("unknown");return;}
    if(changed){int token=NOTIFY_TOKEN_INVALID;if(notify_register_check(SERVICE_NOTIFICATION,&token)==NOTIFY_STATUS_OK){notify_set_state(token,value);notify_post(SERVICE_NOTIFICATION);notify_cancel(token);}}
    puts(value==1?"on":value==2?"local":"off");
}
static BOOL WriteMarker(BOOL off){if(off)return [@"off\n" writeToFile:Marker() atomically:YES encoding:NSUTF8StringEncoding error:NULL];return !Exists(Marker()) || [[NSFileManager defaultManager] removeItemAtPath:Marker() error:NULL];}
static BOOL RestoreSSH(void){
#if SERVICE_KIND == 1
    NSString *backup=[stateDir stringByAppendingString:@"/sshd_config.original"];
    if(Exists(backup)){NSData *data=[NSData dataWithContentsOfFile:backup];if(!data || ![data writeToFile:@"/var/jb/etc/ssh/sshd_config" options:NSDataWritingAtomic error:NULL])return NO;[[NSFileManager defaultManager] removeItemAtPath:backup error:NULL];[[NSFileManager defaultManager] removeItemAtPath:[stateDir stringByAppendingString:@"/sshd.local-active"] error:NULL];}
#endif
    return YES;
}
static BOOL RestrictSSH(void){
#if SERVICE_KIND == 1
    NSString *config=@"/var/jb/etc/ssh/sshd_config";
    NSString *backup=[stateDir stringByAppendingString:@"/sshd_config.original"];
    NSData *original=[NSData dataWithContentsOfFile:config];if(!original)return NO;
    if(!Exists(backup) && ![original writeToFile:backup options:NSDataWritingAtomic error:NULL])return NO;
    NSString *text=[[NSString alloc] initWithData:original encoding:NSUTF8StringEncoding];if(!text)return NO;
    NSString *candidate=[stateDir stringByAppendingString:@"/sshd_config.local"];
    text=[text stringByAppendingString:@"\nMatch Address *,!127.0.0.1,!::1\n    DenyUsers *\n"];
    if(![text writeToFile:candidate atomically:YES encoding:NSUTF8StringEncoding error:NULL])return NO;
    if(Run(@"/var/jb/usr/sbin/sshd",@[@"-t",@"-f",candidate])!=0)return NO;
    if(![[NSData dataWithContentsOfFile:candidate] writeToFile:config options:NSDataWritingAtomic error:NULL])return NO;
    // Socket-activated sshd reads this file for every new connection.
    Processes(SIGTERM);usleep(300000);
    return [@"local\n" writeToFile:[stateDir stringByAppendingString:@"/sshd.local-active"] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
#else
    return NO;
#endif
}
static BOOL SetEnabled(BOOL enabled){
#if SERVICE_KIND == 3
    NSString *prefs=MobilePrefs();
    NSMutableDictionary *values=[[NSDictionary dictionaryWithContentsOfFile:prefs] mutableCopy] ?: [NSMutableDictionary dictionary];
    values[@"enabled"]=@(enabled);
    if(![values writeToFile:prefs atomically:YES])return NO;
    chown(prefs.fileSystemRepresentation,501,501);chmod(prefs.fileSystemRepresentation,0600);
    CFPreferencesSetValue(CFSTR("enabled"),enabled?kCFBooleanTrue:kCFBooleanFalse,CFSTR("com.catmcp.server"),CFSTR("mobile"),kCFPreferencesAnyHost);
    CFPreferencesSynchronize(CFSTR("com.catmcp.server"),CFSTR("mobile"),kCFPreferencesAnyHost);
#endif
    if(!Exists(JobPath())){fprintf(stderr,"service plist missing\n");return NO;}
    if(enabled && !RestoreSSH())return NO;
    if(!WriteMarker(!enabled))return NO;
    for(int i=0;i<2;i++){
        NSString *domain=@(domains[i]);NSString *target=[domain stringByAppendingFormat:@"/%@",Label()];
        if(enabled){Launch(@[@"enable",target]);if(Launch(@[@"print",target])==0){Launch(@[@"kickstart",target]);break;}
            if(Launch(@[@"bootstrap",domain,JobPath()])==0){Launch(@[@"kickstart",target]);break;}}
        else{Launch(@[@"disable",target]);Processes(SIGTERM);Launch(@[@"bootout",target]);}
    }
    if(!enabled && Processes(0)>0){usleep(50000);Processes(SIGKILL);}
    for(int i=0;i<100;i++){BOOL listening=Listening();int processes=Processes(0);
        if(enabled?listening:(!listening && processes==0))return YES;usleep(50000);}
    if(!enabled && RestrictSSH())return YES;
    return NO;
}
int main(int argc,char **argv){@autoreleasepool{
    if(argc!=2 || ![@[@"status",@"toggle",@"on",@"off"] containsObject:@(argv[1])])return 64;
    if(setgid(0)!=0 || setuid(0)!=0 || getuid()!=0 || geteuid()!=0){fprintf(stderr,"root helper required\n");return 77;}
    umask(022);setenv("PATH","/var/jb/usr/bin:/var/jb/bin:/usr/bin:/bin",1);
    if(!Exists(prefix))return 78;
    if(![[NSFileManager defaultManager] createDirectoryAtPath:stateDir withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0755} error:NULL])return 73;
    struct stat st;if(lstat(stateDir.fileSystemRepresentation,&st)!=0 || !S_ISDIR(st.st_mode) || st.st_uid!=0 || (st.st_mode&0022))return 77;
    NSString *lock=[stateDir stringByAppendingFormat:@"/%@.lock",Label()];int fd=open(lock.fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if(fd<0)return 75;
    BOOL locked=NO;CFTimeInterval lockDeadline=NSProcessInfo.processInfo.systemUptime+([@(argv[1]) isEqual:@"status"]?0:5);
    do {if(flock(fd,LOCK_EX|LOCK_NB)==0){locked=YES;break;}if(errno!=EWOULDBLOCK)break;usleep(10000);}while(NSProcessInfo.processInfo.systemUptime<lockDeadline);
    if(!locked){close(fd);return 75;}
    NSInteger before=State();BOOL ok=YES;NSString *command=@(argv[1]);
    if(before<0){Publish(-1,NO);flock(fd,LOCK_UN);close(fd);return 1;}
    if(![command isEqual:@"status"]){BOOL enabled=[command isEqual:@"on"] || ([command isEqual:@"toggle"] && before!=1);ok=SetEnabled(enabled);}
    NSInteger after=State();Publish(after,![command isEqual:@"status"]);flock(fd,LOCK_UN);close(fd);return ok?0:1;
}}
