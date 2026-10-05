#import "Shared.h"
#import <spawn.h>
#import <sys/wait.h>
#import <sys/stat.h>
#import <unistd.h>
#import <signal.h>
#import <fcntl.h>
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
static NSString *Domain(NSDictionary *job){NSDictionary *b=state[@"baseline"][job[@"id"]];return b?(b[@"domain"]?:@"system"):(state[@"domains"][job[@"id"]]?:@"system");}
static NSString *Target(NSDictionary *job){ return [NSString stringWithFormat:@"%@/%@",Domain(job),job[@"label"]]; }
static void ResolveDomains(void){
    NSMutableDictionary *domains=[state[@"domains"] mutableCopy]?:[NSMutableDictionary dictionary];
    for(NSDictionary *job in catalog[@"jobs"]){if(state[@"baseline"][job[@"id"]])continue;BOOL found=NO;
        for(NSString *candidate in @[@"system",@"user/501"]){NSString *text=nil;int rc=Run(@[@"print",[NSString stringWithFormat:@"%@/%@",candidate,job[@"label"]]],&text);if(rc)continue;
            for(NSString *line in [text componentsSeparatedByString:@"\n"])for(NSString *domain in @[@"system",@"user/501"])
                if([line hasPrefix:[NSString stringWithFormat:@"%@/%@ = {",domain,job[@"label"]]]){domains[job[@"id"]]=domain;found=YES;break;}
            if(found)break;
        }
    }
    state[@"domains"]=domains;
}
static BOOL Loaded(NSDictionary *job){return Run(@[@"print",Target(job)],NULL)==0;}
static NSSet *LoadedSet(void){
    NSString *s=nil; if(Run(@[@"list"],&s)!=0)return nil;
    NSMutableSet *set=[NSMutableSet set];
    for(NSString *line in [s componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]){
        NSArray *fields=[line componentsSeparatedByString:@"\t"];
        if(fields.count==3 && ![fields[0] isEqual:@"PID"])[set addObject:fields[2]];
    }
    for(NSDictionary *job in catalog[@"jobs"]){[set removeObject:job[@"label"]];if(Loaded(job))[set addObject:job[@"label"]];}
    return set;
}
static NSDictionary *DisabledForDomain(NSString *domain){
    NSString *s=nil; if(Run(@[@"print-disabled",domain],&s)!=0)return nil;
    NSMutableDictionary *d=[NSMutableDictionary dictionary];
    NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"\"([^\"]+)\"\\s*=>\\s*(disabled|enabled)" options:0 error:nil];
    for(NSTextCheckingResult *m in [rx matchesInString:s?:@"" options:0 range:NSMakeRange(0,s.length)])
        d[[s substringWithRange:[m rangeAtIndex:1]]]=@([[s substringWithRange:[m rangeAtIndex:2]] isEqual:@"disabled"]);
    return d;
}
static NSDictionary *Disabled(void){
    NSDictionary *system=DisabledForDomain(@"system"),*user=DisabledForDomain(@"user/501");if(!system || !user)return nil;
    NSMutableDictionary *out=[NSMutableDictionary dictionary];for(NSDictionary *job in catalog[@"jobs"])out[job[@"label"]]=[Domain(job) isEqual:@"system"]?(system[job[@"label"]]?:@NO):(user[job[@"label"]]?:@NO);return out;
}
// Match launchd labels to their actual PID. Never guess from executable names:
// several jobs can share a process, so totals must deduplicate PID samples.
static NSDictionary *MemoryByLabel(void){
    NSString *text=nil;if(Run(@[@"list"],&text)!=0)return @{};
    NSString *system=nil;if(Run(@[@"print",@"system"],&system)==0){
        NSRange start=[system rangeOfString:@"\tservices = {\n"];if(start.location!=NSNotFound){NSString *tail=[system substringFromIndex:NSMaxRange(start)];NSRange end=[tail rangeOfString:@"\n\t}"];if(end.location!=NSNotFound){NSString *section=[tail substringToIndex:end.location];NSRegularExpression *rx=[NSRegularExpression regularExpressionWithPattern:@"^\\s*(\\d+)\\s+\\S+\\s+(\\S+)\\s*$" options:NSRegularExpressionAnchorsMatchLines error:nil];NSMutableString *combined=[text mutableCopy];for(NSTextCheckingResult *m in [rx matchesInString:section options:0 range:NSMakeRange(0,section.length)]){NSString *pid=[section substringWithRange:[m rangeAtIndex:1]],*label=[section substringWithRange:[m rangeAtIndex:2]];[combined appendFormat:@"\n%@\t0\t%@",[pid isEqual:@"0"]?@"-":pid,label];}text=combined;}}
    }
    NSMutableDictionary *out=[NSMutableDictionary dictionary],*samples=[NSMutableDictionary dictionary];
    for(NSString *line in [text componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]){
        NSArray *f=[line componentsSeparatedByString:@"\t"];if(f.count!=3 || [f[0] isEqual:@"PID"])continue;
        if([f[0] isEqual:@"-"]){out[f[2]]=@{@"known":@YES,@"bytes":@0,@"pid":@0};continue;}
        int pid=[f[0] intValue];if(pid<=0)continue;NSString *key=f[0];NSDictionary *sample=samples[key];
        if(!sample){struct rusage_info_v2 r={0};BOOL known=proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&r)==0;
            sample=@{@"known":@(known),@"bytes":@(known?r.ri_phys_footprint:0),@"pid":@(pid),@"start":@(known?r.ri_proc_start_abstime:0)};samples[key]=sample;}
        out[f[2]]=sample;
    }
    return out;
}
static BOOL SampleGone(NSDictionary *sample){
    int pid=[sample[@"pid"] intValue];if(pid<=0)return YES;
    struct rusage_info_v2 r={0};if(proc_pid_rusage(pid,RUSAGE_INFO_V2,(rusage_info_t*)&r)==0)return r.ri_proc_start_abstime!=[sample[@"start"] unsignedLongLongValue];
    return kill(pid,0)<0 && errno==ESRCH;
}
static void Save(void){
    [[NSFileManager defaultManager] createDirectoryAtPath:[RPPrivate stringByDeletingLastPathComponent] withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    [state writeToFile:RPPrivate atomically:YES]; chmod(RPPrivate.UTF8String,0600);
}
static void Error(NSString *text){[errors addObject:text]; NSLog(@"%@",text);}
static NSDictionary *Job(NSString *jid){for(NSDictionary *j in catalog[@"jobs"]) if([j[@"id"] isEqual:jid]) return j; return nil;}
static NSArray *AllPresets(void){NSMutableArray *a=[catalog[@"presets"] mutableCopy];[a addObjectsFromArray:state[@"userPresets"]?:@[]];return a;}
static BOOL ValidPreset(NSString *pid){for(NSDictionary *p in AllPresets())if([p[@"id"] isEqual:pid])return YES;return NO;}
static NSArray *Planned(void){
    if([state[@"preset"] isEqual:@"custom"]) return state[@"custom"]?:@[];
    for(NSDictionary *p in AllPresets()) if([p[@"id"] isEqual:state[@"preset"]]) return p[@"jobs"];
    return @[];
}
static NSArray *Desired(void){return [state[@"enabled"] boolValue]?Planned():@[];}
static void Publish(void){
    NSDictionary *disabled=Disabled(); NSSet *loadedSet=LoadedSet(); NSMutableDictionary *jobs=[NSMutableDictionary dictionary];
    NSDictionary *memory=MemoryByLabel();NSMutableDictionary *released=[NSMutableDictionary dictionary];NSUInteger missing=0;
    BOOL verified=loadedSet!=nil && disabled!=nil;
    NSArray *desired=Desired();
    for(NSDictionary *j in catalog[@"jobs"]){
        BOOL loaded=[loadedSet containsObject:j[@"label"]],off=[disabled[j[@"label"]] boolValue],selected=[desired containsObject:j[@"id"]];
        if(selected && (!off || loaded)) verified=NO;
        NSDictionary *before=state[@"baseline"][j[@"id"]][@"memory"],*now=memory[j[@"label"]];
        BOOL measured=[before[@"known"] boolValue],known=selected?measured:[now[@"known"] boolValue];
        uint64_t estimate=[(selected?before:now)[@"bytes"] unsignedLongLongValue];
        jobs[j[@"id"]]=@{@"disabled":@(off),@"loaded":@(loaded),@"selected":@(selected),@"ramKnown":@(known),@"ramBytes":@(estimate),@"ramCurrentBytes":now[@"bytes"]?:@0};
        if(selected){if(!measured)missing++;else if(off && !loaded && ![state[@"baseline"][j[@"id"]][@"disabled"] boolValue] && SampleGone(before)){
            NSString *key=[NSString stringWithFormat:@"%@:%@",before[@"pid"],before[@"start"]];released[key]=before[@"bytes"]?:@0;
        }}
    }
    for(NSString *jid in state[@"baseline"]){
        if([desired containsObject:jid])continue;
        NSDictionary *b=state[@"baseline"][jid],*live=jobs[jid];
        if(!live || [live[@"disabled"] boolValue]!=[b[@"disabled"] boolValue] || [live[@"loaded"] boolValue]!=[b[@"loaded"] boolValue])verified=NO;
    }
    NSMutableDictionary *pub=[state mutableCopy]; [pub removeObjectForKey:@"baseline"];
    uint64_t total=0;for(NSNumber *bytes in released.allValues)total+=bytes.unsignedLongLongValue;
    pub[@"ramByLabel"]=memory;pub[@"ramSavedBytes"]=@(total);pub[@"ramMissingJobs"]=@(missing);pub[@"ramUpdated"]=[NSDate date];
    if(![state[@"enabled"] boolValue] && [state[@"baseline"] count])verified=NO;
    pub[@"jobs"]=jobs;pub[@"verified"]=@(verified);pub[@"errors"]=verified?@[]:[errors copy];pub[@"operation"]=lastOperation;pub[@"updated"]=[NSDate date];
    [pub writeToFile:RPStatus atomically:YES];chmod(RPStatus.UTF8String,0644);
    notify_post("com.ratush.daemonpresets.changed");
}
static BOOL RestoreJob(NSDictionary *j,NSDictionary *b){
    NSString *t=Target(j); int rc=Run(@[[b[@"disabled"] boolValue]?@"disable":@"enable",t],NULL);
    if(rc){Error([NSString stringWithFormat:@"%@: восстановление запрета: %d",j[@"name"],rc]);return NO;}
    if([b[@"loaded"] boolValue] && !Loaded(j)){
        rc=Run(@[@"bootstrap",Domain(j),j[@"path"]],NULL);
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
    // Older versions journaled system targets. Restore them before recapturing
    // the actual domain, rather than losing their original override state.
    for(NSString *jid in [baseline.allKeys copy])if(!baseline[jid][@"domain"]){NSDictionary *job=Job(jid);if(!job || !RestoreJob(job,baseline[jid])){Publish();return;}[baseline removeObjectForKey:jid];state[@"baseline"]=baseline;Save();}
    ResolveDomains();
    NSDictionary *disabled=Disabled(); NSSet *loadedSet=LoadedSet();
    if(!loadedSet || !disabled){Error(@"Не удалось получить состояния служб launchd");Publish();return;}
    // Journal every original service state before the first mutation.
    NSDictionary *memory=MemoryByLabel();
    for(NSString *jid in want){NSDictionary *j=Job(jid); if(j && !baseline[jid]) baseline[jid]=@{@"domain":Domain(j),@"disabled":@([disabled[j[@"label"]] boolValue]),@"loaded":@([loadedSet containsObject:j[@"label"]]),@"memory":memory[j[@"label"]]?:@{@"known":@([loadedSet containsObject:j[@"label"]]?NO:YES),@"bytes":@0,@"pid":@0,@"start":@0},@"memorySampled":[NSDate date]};}
    state[@"baseline"]=baseline; Save();
    for(NSString *jid in [baseline.allKeys copy]){
        if([want containsObject:jid]) continue;
        NSDictionary *j=Job(jid);if(j && RestoreJob(j,baseline[jid])){[baseline removeObjectForKey:jid];state[@"baseline"]=baseline;Save();}
    }
    dispatch_group_t work=dispatch_group_create();
    dispatch_semaphore_t slots=dispatch_semaphore_create(4);
    for(NSString *jid in want){
        NSDictionary *j=Job(jid); if(!j || ![[NSFileManager defaultManager] fileExistsAtPath:j[@"path"]]){Error([NSString stringWithFormat:@"%@: служба отсутствует",jid]);continue;}
        dispatch_semaphore_wait(slots,DISPATCH_TIME_FOREVER);
        dispatch_group_async(work,dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{@autoreleasepool{
            if(![disabled[j[@"label"]] boolValue])Run(@[@"disable",Target(j)],NULL);
            if([loadedSet containsObject:j[@"label"]])Run(@[@"bootout",Target(j)],NULL);
            dispatch_semaphore_signal(slots);
        }});
    }
    dispatch_group_wait(work,DISPATCH_TIME_FOREVER);
    Save();Publish();
}
// Only bounded regular files are read from mobile. Imported jobs are identifiers,
// never executable paths or launchctl arguments. The immutable catalog is the allowlist.
static NSDictionary *ReadRequest(void){
    int fd=open(RPRequest.UTF8String,O_RDONLY|O_NOFOLLOW|O_NONBLOCK);if(fd<0)return nil;
    struct stat st;if(fstat(fd,&st) || !S_ISREG(st.st_mode) || st.st_size<1 || st.st_size>65536){close(fd);return nil;}
    NSMutableData *d=[NSMutableData dataWithLength:(NSUInteger)st.st_size];size_t n=0;
    while(n<d.length){ssize_t r=read(fd,(char*)d.mutableBytes+n,d.length-n);if(r<=0)break;n+=r;}close(fd);
    if(n!=d.length)return nil;
    id o=[NSPropertyListSerialization propertyListWithData:d options:NSPropertyListImmutable format:nil error:nil];return [o isKindOfClass:NSDictionary.class]?o:nil;
}
static NSString *FreeSlot(NSArray *a){for(int i=0;i<32;i++){NSString *pid=[NSString stringWithFormat:@"user%02d",i];BOOL exists=NO;for(NSDictionary *p in a)if([p[@"id"] isEqual:pid])exists=YES;if(!exists)return pid;}return nil;}
static void LibraryCommand(void){
    NSDictionary *r=ReadRequest();NSMutableArray *a=[state[@"userPresets"] mutableCopy]?:[NSMutableArray array];NSString *failure=nil;
    NSString *op=r[@"op"];BOOL reapply=NO;
    if([op isEqual:@"delete"]){
        NSString *pid=r[@"id"];NSDictionary *found=nil;for(NSDictionary *p in a)if([p[@"id"] isEqual:pid])found=p;
        if(!found)failure=@"Свой пресет не найден";
        else {if([state[@"preset"] isEqual:pid]){state[@"custom"]=Planned();state[@"preset"]=@"custom";reapply=YES;}[a removeObject:found];NSMutableArray *cc=[state[@"ccPresets"] mutableCopy];[cc removeObject:pid];state[@"ccPresets"]=cc;}
    } else if([op isEqual:@"save"] || [op isEqual:@"import"]){
        NSArray *incoming=nil;
        if([op isEqual:@"save"])incoming=@[@{@"name":r[@"name"]?:@"",@"jobs":Planned()}];
        else {id document=r[@"document"];if([document isKindOfClass:NSDictionary.class] && [document[@"schema"] isEqual:@1] && [document[@"presets"] isKindOfClass:NSArray.class])incoming=document[@"presets"];}
        if(!incoming.count || incoming.count>32 || a.count+incoming.count>32)failure=@"Неверный формат или превышен лимит: 32 своих пресета";
        NSMutableArray *added=[NSMutableArray array];
        if(!failure)for(id item in incoming){
            if(![item isKindOfClass:NSDictionary.class]){failure=@"Неверная запись пресета";break;}
            id name=item[@"name"],list=item[@"jobs"];
            if(![name isKindOfClass:NSString.class] || ![name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length || [name length]>80 || ![list isKindOfClass:NSArray.class] || [list count]>[catalog[@"jobs"] count]){failure=@"Название должно содержать 1–80 символов, а состав — проверенные службы";break;}
            NSMutableArray *ids=[NSMutableArray array];
            for(id value in list){NSDictionary *j=nil;if([value isKindOfClass:NSString.class])for(NSDictionary *candidate in catalog[@"jobs"])if([candidate[@"id"] isEqual:value] || [candidate[@"label"] isEqual:value]){j=candidate;break;}
                if(!j){failure=@"Импорт отклонён: есть неизвестная или защищённая служба";break;}if(![ids containsObject:j[@"id"]])[ids addObject:j[@"id"]];}
            if(failure)break;
            NSMutableArray *used=[a mutableCopy];[used addObjectsFromArray:added];NSString *pid=FreeSlot(used);
            [added addObject:@{@"id":pid,@"name":[name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet],@"jobs":ids}];
        }
        if(!failure)[a addObjectsFromArray:added];
    } else failure=@"Неверный запрос библиотеки пресетов";
    if(!failure)state[@"userPresets"]=a;
    state[@"libraryError"]=failure?:@"";state[@"libraryRequest"]= [r[@"request"] isKindOfClass:NSString.class]?r[@"request"]:@"";
    Save();if(reapply)Apply();else Publish();
}
static void HandleCommand(NSString *cmd){
    lastOperation=cmd;
    if([cmd isEqual:@"query"]){Publish();return;}
    if([cmd isEqual:@"library"]){LibraryCommand();return;}
    if([cmd isEqual:@"toggle"])state[@"enabled"]=@(![state[@"enabled"] boolValue]);
    else if([cmd isEqual:@"on"])state[@"enabled"]=@YES;
    else if([cmd isEqual:@"off"])state[@"enabled"]=@NO;
    else if([cmd hasPrefix:@"preset."]){NSString *pid=[cmd substringFromIndex:7];if(!ValidPreset(pid))return;state[@"preset"]=pid;}
    else if([cmd hasPrefix:@"cc."]){NSMutableArray *a=[state[@"ccPresets"] mutableCopy];NSString *p=[cmd substringFromIndex:3];if(!ValidPreset(p))return;if([a containsObject:p])[a removeObject:p];else [a addObject:p];state[@"ccPresets"]=a;Save();Publish();return;}
    else if([cmd hasPrefix:@"job."]){
        NSMutableArray *a=[Planned() mutableCopy];
        NSString *jid=[cmd substringFromIndex:4]; if([a containsObject:jid])[a removeObject:jid];else [a addObject:jid];
        if(!Job(jid))return;
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
static int RegisterCC(BOOL add){
    NSFileManager *fm=[NSFileManager defaultManager];NSString *path=nil;
    for(NSString *p in @[@"/var/jb/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist",@"/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist"])
        if([fm fileExistsAtPath:p]){path=p;break;}
    if(!path)return 0;
    NSMutableDictionary *d=[[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy];if(!d)return 1;
    NSString *identifier=@"com.ratush.daemonpresets.cc";NSMutableArray *a=[d[@"module-identifiers"] mutableCopy];if(!a)return 1;
    if(add==[a containsObject:identifier])return 0;
    NSString *suffix=[NSString stringWithFormat:@".ratu-daemonpresets.%.0f.bak",[[NSDate date] timeIntervalSince1970]];
    NSString *backup=[path stringByAppendingString:suffix];NSError *e=nil;
    if(![fm copyItemAtPath:path toPath:backup error:&e])return 1;
    [fm createDirectoryAtPath:@"/var/jb/var/root/ratu-daemon-backups" withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    if(![fm copyItemAtPath:path toPath:[@"/var/jb/var/root/ratu-daemon-backups" stringByAppendingPathComponent:backup.lastPathComponent] error:&e])return 1;
    struct stat st;stat(path.UTF8String,&st);
    if(add)[a addObject:identifier];else [a removeObject:identifier];d[@"module-identifiers"]=a;
    if(![d writeToFile:path atomically:YES])return 1;chown(path.UTF8String,st.st_uid,st.st_gid);chmod(path.UTF8String,0644);return 0;
}
int main(int argc,char **argv){@autoreleasepool{
    signal(SIGCHLD,SIG_DFL);
    if(getuid()!=0){fprintf(stderr,"root required\n");return 77;}
    if(argc==2 && !strcmp(argv[1],"--register-cc"))return RegisterCC(YES);
    if(argc==2 && !strcmp(argv[1],"--unregister-cc"))return RegisterCC(NO);
    if(argc==2 && !strcmp(argv[1],"--snapshot")){Snapshot();return 0;}
    catalog=Catalog();if(![catalog[@"jobs"] count])return 78;
    state=[[NSDictionary dictionaryWithContentsOfFile:RPPrivate] mutableCopy]?:[@{@"enabled":@NO,@"preset":@"report",@"custom":@[],@"ccPresets":@[@"report",@"report-photos",@"photos"],@"baseline":@{}} mutableCopy];
    errors=[NSMutableArray array];
    if(argc==2 && !strcmp(argv[1],"--restore")){state[@"enabled"]=@NO;Apply();return errors.count?1:0;}
    queue=dispatch_queue_create("com.ratush.daemonpresets.worker",DISPATCH_QUEUE_SERIAL);
    NSMutableArray *commands=[@[@"query",@"toggle",@"on",@"off",@"library"] mutableCopy];
    for(NSDictionary *p in catalog[@"presets"]){[commands addObject:[@"preset." stringByAppendingString:p[@"id"]]];[commands addObject:[@"cc." stringByAppendingString:p[@"id"]]];}
    for(NSDictionary *j in catalog[@"jobs"])[commands addObject:[@"job." stringByAppendingString:j[@"id"]]];
    for(int i=0;i<32;i++){NSString *pid=[NSString stringWithFormat:@"user%02d",i];[commands addObject:[@"preset." stringByAppendingString:pid]];[commands addObject:[@"cc." stringByAppendingString:pid]];}
    if(argc==3 && !strcmp(argv[1],"--command")){
        NSString *c=@(argv[2]); if(![commands containsObject:c])return 64; Command(c);return 0;
    }
    for(NSString *c in commands){int token;notify_register_dispatch([[RPPrefix stringByAppendingString:c] UTF8String],&token,queue,^(int t){@autoreleasepool{HandleCommand(c);}});}
    dispatch_async(queue,^{Apply();});dispatch_main();
}}
