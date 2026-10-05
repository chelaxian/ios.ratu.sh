#import "OFShared.h"
#import <errno.h>
#import <signal.h>
#import <spawn.h>
#import <sys/sysctl.h>
#import <sys/wait.h>
extern char **environ;

// A stalled App Store download (appstored stuck in AppInstallPreambleTask)
// resumes after launchd restarts appstored. SpringBoard runs as mobile without
// a sandbox, so it may restart the per-user job itself; Settings asks it to.
static const char *OFStoreRestart = "com.ratush.offloader.restart-appstored";
static NSString *const OFStoreRequestKey = @"storeRestartRequest";
static NSString *const OFStoreResponseKey = @"storeRestartResponse";

static NSString *OFStoreTarget(uid_t uid) { return [NSString stringWithFormat:@"user/%u/com.apple.appstored",(unsigned)uid]; }
static pid_t OFStorePID(void) {
    int name[] = {CTL_KERN,KERN_PROC,KERN_PROC_UID,(int)getuid()};
    size_t size = 0;
    if (sysctl(name,4,NULL,&size,NULL,0) != 0 || size == 0) return 0;
    size += size / 4;
    struct kinfo_proc *list = malloc(size);
    if (!list) return 0;
    pid_t result = 0;
    if (sysctl(name,4,list,&size,NULL,0) == 0) {
        for (size_t i = 0; i < size / sizeof(struct kinfo_proc); ++i)
            if (!strcmp(list[i].kp_proc.p_comm,"appstored")) { result = list[i].kp_proc.p_pid; break; }
    }
    free(list);
    return result;
}
static NSString *OFLaunchctlPath(void) {
    for (NSString *path in @[@"/var/jb/usr/bin/launchctl",@"/var/jb/bin/launchctl",@"/usr/bin/launchctl"])
        if ([NSFileManager.defaultManager isExecutableFileAtPath:path]) return path;
    return nil;
}
// Returns the exit status, -1 when it could not run, -2 when the status is unknown.
static int OFRunLaunchctl(NSString *path, NSString *target) {
    char *const arguments[] = {(char *)"launchctl",(char *)"kickstart",(char *)"-k",(char *)target.UTF8String,NULL};
    pid_t child = 0;
    if (posix_spawn(&child,path.fileSystemRepresentation,NULL,NULL,arguments,environ) != 0) return -1;
    for (int attempt = 0; attempt < 150; ++attempt) {
        int status = 0;
        pid_t done = waitpid(child,&status,WNOHANG);
        if (done == child) return WIFEXITED(status) ? WEXITSTATUS(status) : -2;
        if (done < 0) return errno == ECHILD ? -2 : -1;
        usleep(100000);
    }
    kill(child,SIGKILL); waitpid(child,NULL,0);
    return -2;
}
static NSString *OFStoreMessage(BOOL restarted) {
    return restarted ?
        OFText(@"The App Store service (appstored) was restarted. Stalled downloads continue in a few seconds; if one does not, tap its icon once.",@"Служба App Store (appstored) перезапущена. Зависшие загрузки продолжатся через несколько секунд; если загрузка не пошла, нажмите на её значок один раз.") :
        OFText(@"Could not restart appstored. Restart the device or run: launchctl kickstart -k user/501/com.apple.appstored",@"Не удалось перезапустить appstored. Перезагрузите устройство или выполните: launchctl kickstart -k user/501/com.apple.appstored");
}
// Blocking; call off the main thread.
static BOOL OFRestartAppStore(NSString **message) {
    pid_t before = OFStorePID();
    NSString *launchctl = OFLaunchctlPath();
    int status = launchctl ? OFRunLaunchctl(launchctl,OFStoreTarget(getuid())) : -1;
    pid_t after = 0;
    for (int attempt = 0; attempt < 30; ++attempt) {
        after = OFStorePID();
        if (after && after != before) break;
        usleep(100000);
    }
    BOOL restarted = status == 0 || (after && after != before);
    if (!restarted && before && kill(before,SIGKILL) == 0) {
        // launchd starts appstored again on the next App Store request.
        restarted = YES;
        for (int attempt = 0; attempt < 30 && !(after = OFStorePID()); ++attempt) usleep(100000);
    }
    if (message) *message = OFStoreMessage(restarted);
    NSLog(@"[Offloader] appstored restart: launchctl=%@ status=%d pid %d -> %d",launchctl,status,before,after);
    return restarted;
}
static BOOL OFStoreRequestValid(id request, NSDate *now) {
    if (![request isKindOfClass:NSDictionary.class]) return NO;
    NSDate *date = request[@"date"];
    return OFValidID(request[@"id"]) && [date isKindOfClass:NSDate.class] && [now timeIntervalSinceDate:date] <= 30 && [now timeIntervalSinceDate:date] >= -5;
}
