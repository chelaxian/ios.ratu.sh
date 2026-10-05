#import "Shared.h"
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>
#import <sys/resource.h>
extern int proc_listpids(uint32_t, uint32_t, void *, int);
extern int proc_pidpath(int, void *, uint32_t);
extern int proc_pid_rusage(int, int, rusage_info_t *);
#define PROC_ALL_PIDS 1
#import <mach/mach.h>
#import <mach/mach_host.h>
extern char **environ;
static NSMutableDictionary *state;
static NSDictionary *catalog;
static NSMutableArray *errors;
static dispatch_queue_t queue;
static NSString *lastOperation=@"Готово";
static int Run(NSArray *args, NSString **output) {
    // Fixed executable and catalog-derived arguments only; no shell or user paths.
    int p[2]; if(pipe(p)) return 255;
    posix_spawn_file_actions_t fa; posix_spawn_file_actions_init(&fa);
    posix_spawn_file_actions_adddup2(&fa,p[1],STDOUT_FILENO);
    posix_spawn_file_actions_adddup2(&fa,p[1],STDERR_FILENO);
    posix_spawn_file_actions_addclose(&fa,p[0]);
    char **av=calloc(args.count+2,sizeof(char*)); av[0]="/var/jb/usr/bin/launchctl";
    for(NSUInteger i=0;i<args.count;i++) av[i+1]=(char*)[args[i] UTF8String];
    pid_t pid=0; int rc=posix_spawn(&pid,av[0],&fa,NULL,av,environ);
    free(av); posix_spawn_file_actions_destroy(&fa); close(p[1]);
    if(rc){close(p[0]);return rc;}
    // Drain concurrently to avoid pipe deadlocks with long launchctl print output.
    NSMutableData *data=[NSMutableData data];
    dispatch_group_t g=dispatch_group_create();
    int readfd=p[0];
    dispatch_group_async(g,dispatch_get_global_queue(QOS_CLASS_UTILITY,0),^{
        char b[4096]; ssize_t n; while((n=read(readfd,b,sizeof b))>0) if(data.length<262144) [data appendBytes:b length:n]; close(readfd);
    });
    int status=0; BOOL finished=NO;
    for(int i=0;i<100;i++){pid_t w=waitpid(pid,&status,WNOHANG);if(w==pid){finished=YES;break;}if(w<0){NSLog(@"waitpid failed: %d",errno);break;}usleep(50000);}
    if(!finished){kill(pid,SIGKILL);waitpid(pid,&status,0);}
    dispatch_group_wait(g,DISPATCH_TIME_FOREVER);
    if(output) *output=[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
    return finished && WIFEXITED(status) ? WEXITSTATUS(status) : 254;
}
static NSString *Target(NSDictionary *job){ return [@"system/" stringByAppendingString:job[@"label"]]; }
static BOOL Loaded(NSDictionary *job){return Run(@[@"print",Target(job)],NULL)==0;}
static NSDictionary *Disabled(void){
    NSString *s=nil; Run(@[@"print-disabled",@"system"],&s);
    NSMutableDictionary *d=[NSMutableDictionary dictionary];
    NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"\"([^\"]+)\"\\s*=>\\s*(disabled|enabled)" options:0 error:nil];
    for(NSTextCheckingResult *m in [rx matchesInString:s?:@"" options:0 range:NSMakeRange(0,s.length)])
        d[[s substringWithRange:[m rangeAtIndex:1]]]=@([[s substringWithRange:[m rangeAtIndex:2]] isEqual:@"disabled"]);
    return d;
}
static void Save(void){
    [[NSFileManager defaultManager] createDirectoryAtPath:[RPPrivate stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    [state writeToFile:RPPrivate atomically:YES]; chmod(RPPrivate.UTF8String,0600);
}
static void Error(NSString *text){[errors addObject:text]; NSLog(@"%@",text);}
static NSDictionary *Job(NSString *jid){for(NSDictionary *j in catalog[@"jobs"]) if([j[@"id"] isEqual:jid]) return j; return nil;}
static NSArray *Desired(void){
    if(![state[@"enabled"] boolValue]) return @[];
    if([state[@"preset"] isEqual:@"custom"]) return state[@"custom"]?:@[];
    for(NSDictionary *p in catalog[@"presets"]) if([p[@"id"] isEqual:state[@"preset"]]) return p[@"jobs"];
    return @[];
}
static void Publish(void){
    NSDictionary *disabled=Disabled(); NSMutableDictionary *jobs=[NSMutableDictionary dictionary];
    BOOL verified=YES;
    NSArray *desired=Desired();
    for(NSDictionary *j in catalog[@"jobs"]){
        BOOL loaded=Loaded(j),off=[disabled[j[@"label"]] boolValue],selected=[desired containsObject:j[@"id"]];
        if(selected && (!off || loaded)) verified=NO;
        jobs[j[@"id"]]=@{@"disabled":@(off),@"loaded":@(loaded),@"selected":@(selected)};
    }
    NSMutableDictionary *pub=[state mutableCopy]; [pub removeObjectForKey:@"baseline"];
    if(![state[@"enabled"] boolValue] && [state[@"baseline"] count])verified=NO;
    pub[@"jobs"]=jobs;pub[@"verified"]=@(verified);pub[@"errors"]=verified?@[]:[errors copy];pub[@"operation"]=lastOperation;pub[@"updated"]=[NSDate date];
    [pub writeToFile:RPStatus atomically:YES];chmod(RPStatus.UTF8String,0644);
    notify_post("com.ratush.daemonpresets.changed");
}
static BOOL RestoreJob(NSDictionary *j,NSDictionary *b){
    NSString *t=Target(j); int rc=Run(@[[b[@"disabled"] boolValue]?@"disable":@"enable",t],NULL);
    if(rc){Error([NSString stringWithFormat:@"%@: восстановление запрета: %d",j[@"name"],rc]);return NO;}
    if([b[@"loaded"] boolValue] && !Loaded(j)){
        rc=Run(@[@"bootstrap",@"system",j[@"path"]],NULL);
        if(rc && !Loaded(j)){Error([NSString stringWithFormat:@"%@: восстановление загрузки: %d",j[@"name"],rc]);return NO;}
    } else if(![b[@"loaded"] boolValue] && Loaded(j)) {
        Run(@[@"bootout",t],NULL);
        if(Loaded(j)){Error([NSString stringWithFormat:@"%@: не восстановлено исходное отсутствие службы",j[@"name"]]);return NO;}
    }
    BOOL off=[Disabled()[j[@"label"]] boolValue];
    if(off!=[b[@"disabled"] boolValue]){Error([NSString stringWithFormat:@"%@: не восстановлен исходный запрет",j[@"name"]]);return NO;}
    return YES;
}
static void Apply(void){
    errors=[NSMutableArray array]; NSArray *want=Desired();
    NSMutableDictionary *baseline=[state[@"baseline"] mutableCopy]?:[NSMutableDictionary dictionary];
    NSDictionary *disabled=Disabled();
    // Journal every original service state before the first mutation.
    for(NSString *jid in want){NSDictionary *j=Job(jid); if(j && !baseline[jid]) baseline[jid]=@{@"disabled":@([disabled[j[@"label"]] boolValue]),@"loaded":@(Loaded(j))};}
    state[@"baseline"]=baseline; Save();
    for(NSString *jid in [baseline.allKeys copy]){
        if([want containsObject:jid]) continue;
        NSDictionary *j=Job(jid);if(j && RestoreJob(j,baseline[jid])){[baseline removeObjectForKey:jid];state[@"baseline"]=baseline;Save();}
    }
    for(NSString *jid in want){
        NSDictionary *j=Job(jid); if(!j || ![[NSFileManager defaultManager] fileExistsAtPath:j[@"path"]]){Error([NSString stringWithFormat:@"%@: служба отсутствует",jid]);continue;}
        int rc=Run(@[@"disable",Target(j)],NULL);
        if(rc){Error([NSString stringWithFormat:@"%@: запрет запуска: %d",jid,rc]);continue;}
        if(Loaded(j)) {
            Run(@[@"bootout",Target(j)],NULL);
            for(int i=0;i<10 && Loaded(j);i++)usleep(100000);
        }
        if(Loaded(j) || ![Disabled()[j[@"label"]] boolValue]) Error([NSString stringWithFormat:@"%@: отключение не подтверждено",jid]);
    }
    Save();Publish();
}
static void HandleCommand(NSString *cmd){
    lastOperation=cmd;
    if([cmd isEqual:@"query"]){Publish();return;}
    if([cmd isEqual:@"toggle"])state[@"enabled"]=@(![state[@"enabled"] boolValue]);
    else if([cmd isEqual:@"on"])state[@"enabled"]=@YES;
    else if([cmd isEqual:@"off"])state[@"enabled"]=@NO;
    else if([cmd hasPrefix:@"preset."]){state[@"preset"]=[cmd substringFromIndex:7];}
    else if([cmd hasPrefix:@"cc."]){NSMutableArray *a=[state[@"ccPresets"] mutableCopy];NSString *p=[cmd substringFromIndex:3];if([a containsObject:p])[a removeObject:p];else [a addObject:p];state[@"ccPresets"]=a;Save();Publish();return;}
    else if([cmd hasPrefix:@"job."]){
        NSMutableArray *a=[Desired() mutableCopy];if(![state[@"enabled"] boolValue])a=[state[@"custom"] mutableCopy]?:[NSMutableArray array];
        NSString *jid=[cmd substringFromIndex:4]; if([a containsObject:jid])[a removeObject:jid];else [a addObject:jid];
        state[@"preset"]=@"custom";state[@"custom"]=a; // editing while off does not enable the master
    } else return;
    Apply();
}
static void Snapshot(void){
    int count=proc_listpids(PROC_ALL_PIDS,0,NULL,0);pid_t *pids=calloc(1,count+4096);count=proc_listpids(PROC_ALL_PIDS,0,pids,count+4096)/sizeof(pid_t);
    NSMutableArray *processes=[NSMutableArray array];
    for(int i=0;i<count;i++){char path[4096]={0};struct rusage_info_v2 r={0};if(proc_pidpath(pids[i],path,sizeof path)>0 && proc_pid_rusage(pids[i],RUSAGE_INFO_V2,(rusage_info_t*)&r)==0)[processes addObject:@{@"pid":@(pids[i]),@"path":@(path),@"rss":@(r.ri_resident_size),@"footprint":@(r.ri_phys_footprint)}];}
    free(pids);vm_statistics64_data_t vm={0};mach_msg_type_number_t n=HOST_VM_INFO64_COUNT;host_statistics64(mach_host_self(),HOST_VM_INFO64,(host_info64_t)&vm,&n);vm_size_t pagesize=0;host_page_size(mach_host_self(),&pagesize);
    NSDictionary *d=@{@"processes":processes,@"free":@((uint64_t)vm.free_count*pagesize),@"inactive":@((uint64_t)vm.inactive_count*pagesize),@"compressor":@((uint64_t)vm.compressor_page_count*pagesize),@"timestamp":@([[NSDate date] timeIntervalSince1970])};
    NSData *json=[NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingPrettyPrinted error:nil];fwrite(json.bytes,1,json.length,stdout);puts("");
}
int main(int argc,char **argv){@autoreleasepool{
    signal(SIGCHLD,SIG_DFL);
    if(getuid()!=0){fprintf(stderr,"root required\n");return 77;}
    if(argc==2 && !strcmp(argv[1],"--snapshot")){Snapshot();return 0;}
    catalog=Catalog();if(![catalog[@"jobs"] count])return 78;
    state=[[NSDictionary dictionaryWithContentsOfFile:RPPrivate] mutableCopy]?:[@{@"enabled":@NO,@"preset":@"report",@"custom":@[],@"ccPresets":@[@"report",@"report-photos",@"photos"],@"baseline":@{}} mutableCopy];
    errors=[NSMutableArray array];
    if(argc==2 && !strcmp(argv[1],"--restore")){state[@"enabled"]=@NO;Apply();return errors.count?1:0;}
    queue=dispatch_queue_create("com.ratush.daemonpresets.worker",DISPATCH_QUEUE_SERIAL);
    NSMutableArray *commands=[@[@"query",@"toggle",@"on",@"off"] mutableCopy];
    for(NSDictionary *p in catalog[@"presets"]){[commands addObject:[@"preset." stringByAppendingString:p[@"id"]]];[commands addObject:[@"cc." stringByAppendingString:p[@"id"]]];}
    for(NSDictionary *j in catalog[@"jobs"])[commands addObject:[@"job." stringByAppendingString:j[@"id"]]];
    if(argc==3 && !strcmp(argv[1],"--command")){
        NSString *c=@(argv[2]); if(![commands containsObject:c])return 64; Command(c);return 0;
    }
    for(NSString *c in commands){int token;notify_register_dispatch([[RPPrefix stringByAppendingString:c] UTF8String],&token,queue,^(int t){@autoreleasepool{HandleCommand(c);}});}
    dispatch_async(queue,^{Apply();});dispatch_main();
}}
