#ifndef RATU_CC_COMMAND_IO_H
#define RATU_CC_COMMAND_IO_H
#include <poll.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <signal.h>
#include <sys/wait.h>
#include <time.h>
#include <stdbool.h>
#include <stddef.h>
typedef struct { bool complete,timedOut,reaped,exitKnown; int readError,status; } CCCommandResult;
static double CCCommandTime(void) { struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);return now.tv_sec+now.tv_nsec/1e9; }
// SpringBoard may reap a child independently (or ignore SIGCHLD). Pipe EOF,
// not ownership of its wait status, confirms that a helper has finished.
static CCCommandResult CCReadCommand(pid_t pid,int fd,double timeout,char *output,size_t capacity) {
    CCCommandResult result={0};size_t length=0;bool overflow=false;
    int flags=fcntl(fd,F_GETFL,0);if(flags<0 || fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0){result.readError=errno;return result;}
    double deadline=CCCommandTime()+timeout;
    while(!result.complete && !result.readError && CCCommandTime()<deadline){
        char bytes[64];ssize_t count;
        while((count=read(fd,bytes,sizeof(bytes)))>0){
            for(ssize_t i=0;i<count;i++){if(length+1<capacity)output[length++]=bytes[i];else overflow=true;}
        }
        if(count==0){result.complete=true;break;}
        if(errno!=EAGAIN && errno!=EWOULDBLOCK && errno!=EINTR){result.readError=errno;break;}
        struct pollfd item={.fd=fd,.events=POLLIN|POLLHUP};
        double left=deadline-CCCommandTime();if(left<=0)break;
        int milliseconds=left>.05?50:(int)(left*1000)+1;
        if(poll(&item,1,milliseconds)<0 && errno!=EINTR){result.readError=errno;break;}
    }
    if(capacity)output[length]='\0';
    if(overflow)result.readError=EOVERFLOW;
    result.timedOut=!result.complete && !result.readError;
    pid_t waited=waitpid(pid,&result.status,WNOHANG);
    result.exitKnown=waited==pid;
    result.reaped=waited==pid || (waited<0 && errno==ECHILD);
    // A setuid helper may reject kill from mobile. Never follow that with an
    // unbounded waitpid(...,0), and never signal a PID we no longer own.
    if(!result.complete && waited==0){kill(pid,SIGKILL);waited=waitpid(pid,&result.status,WNOHANG);result.exitKnown=waited==pid;result.reaped=waited==pid || (waited<0 && errno==ECHILD);}
    return result;
}
#endif
