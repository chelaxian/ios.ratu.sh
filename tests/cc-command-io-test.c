#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "../source/CCServiceCommon/CCServiceCommandIO.h"
static void run(const char *name,int ignored,double delay,double timeout,int expectTimeout){
    signal(SIGCHLD,ignored?SIG_IGN:SIG_DFL);int pipeFD[2];assert(pipe(pipeFD)==0);pid_t child=fork();assert(child>=0);
    if(!child){close(pipeFD[0]);struct timespec wait={0,(long)(delay*1e9)};nanosleep(&wait,NULL);write(pipeFD[1],"on\n",3);close(pipeFD[1]);_exit(0);}
    close(pipeFD[1]);char output[32]={0};double start=CCCommandTime();CCCommandResult result=CCReadCommand(child,pipeFD[0],timeout,output,sizeof(output));double elapsed=CCCommandTime()-start;close(pipeFD[0]);
    assert(result.timedOut==expectTimeout);assert(elapsed<timeout+.25);
    if(!expectTimeout){assert(result.complete);assert(!strcmp(output,"on\n"));assert(elapsed>=delay*.8);}
    printf("PASS %s complete=%d timeout=%d elapsed=%.3f\n",name,result.complete,result.timedOut,elapsed);
    int status;waitpid(child,&status,0);
}
static void deniedKill(void){
    if(geteuid()!=0){puts("SKIP root-to-mobile timeout requires root");return;}
    signal(SIGCHLD,SIG_DFL);int fds[2];assert(pipe(fds)==0);pid_t child=fork();assert(child>=0);
    if(!child){close(fds[0]);struct timespec pause={0,400000000};nanosleep(&pause,NULL);write(fds[1],"on\n",3);_exit(0);}
    close(fds[1]);assert(seteuid(65534)==0);double start=CCCommandTime();char output[32]={0};CCCommandResult result=CCReadCommand(child,fds[0],.1,output,sizeof(output));double elapsed=CCCommandTime()-start;
    assert(result.timedOut && !result.reaped);assert(elapsed<.25);assert(seteuid(0)==0);close(fds[0]);int status;waitpid(child,&status,0);
    printf("PASS permission-denied kill remains bounded elapsed=%.3f\n",elapsed);
}
int main(void){deniedKill();run("normal child",0,.1,1,0);run("auto-reaped child",1,.2,1,0);run("bounded timeout",0,.8,.1,1);return 0;}
