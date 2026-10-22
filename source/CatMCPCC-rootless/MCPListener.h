#ifndef RATU_MCP_LISTENER_H
#define RATU_MCP_LISTENER_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <stddef.h>
#include <sys/socket.h>
#include <netinet/in.h>

/* Darwin's stable 64-bit proc_pidfdinfo ABI. The public iPhone SDK omits
 * libproc.h; retain only the fields we read, and use an oversized output buffer.
 * Layout: apple-oss-distributions/xnu/bsd/sys/proc_info.h, socket_fdinfo.
 * Never connect() to a server merely to display its launch state: unaccepted
 * health probes can fill CatMCP's listen queue while its worker is blocked. */
extern int proc_pidinfo(int, int, uint64_t, void *, int);
extern int proc_pidfdinfo(int, int, int, void *, int);
struct MCPFD { int32_t fd; uint32_t type; };
struct MCPSocketPrefix {
    uint64_t fileInfo[3], statInfo[17], socket, pcb;
    int32_t type, protocol, family;
    int16_t options, linger, state, queue, incomplete, limit, timeout;
    uint16_t error;
    uint32_t oob;
    uint64_t buffers[6];
    int32_t kind;
    uint32_t reserved;
    int32_t foreignPort, localPort;
    uint64_t generation;
    uint8_t inetRest[64];
    int32_t tcpState;
};
_Static_assert(offsetof(struct MCPSocketPrefix, kind)==256, "Darwin socket ABI");
_Static_assert(offsetof(struct MCPSocketPrefix, tcpState)==344, "Darwin TCP ABI");

/* 1 = this process owns a TCP LISTEN socket on port; 0 = none;
 * -1 = unavailable/incomplete inspection. A bound or connected socket is not
 * a listener. No loopback/routing policy or HTTP request is involved. */
static int MCPProcessListener(int pid, int port) {
    int bytes=proc_pidinfo(pid,1,0,NULL,0);
    if(bytes<=0)return errno==ESRCH?0:-1;
    if(bytes>1024*1024)return -1;
    int capacity=bytes+64*(int)sizeof(struct MCPFD);
    struct MCPFD *fds=malloc((size_t)capacity);
    if(!fds)return -1;
    bytes=proc_pidinfo(pid,1,0,fds,capacity);
    if(bytes<=0 || bytes>=capacity || bytes%(int)sizeof(*fds)){
        free(fds);return bytes<=0 && errno==ESRCH?0:-1;
    }
    int result=0;
    for(int i=0;i<bytes/(int)sizeof(*fds);i++){
        if(fds[i].type!=2)continue;
        union { uint64_t align; uint8_t raw[4096]; } info;
        int count=proc_pidfdinfo(pid,fds[i].fd,3,info.raw,sizeof(info.raw));
        if(count<(int)sizeof(struct MCPSocketPrefix)){
            /* The process may close an fd between the two snapshots. */
            if(errno!=EBADF && errno!=ENOENT && errno!=ESRCH)result=-1;
            continue;
        }
        struct MCPSocketPrefix s;memcpy(&s,info.raw,sizeof(s));
        if(s.kind==2 && s.type==SOCK_STREAM && s.protocol==IPPROTO_TCP &&
           (s.family==AF_INET || s.family==AF_INET6) && s.tcpState==1 &&
           ntohs((uint16_t)s.localPort)==port){result=1;break;}
    }
    free(fds);return result;
}
#endif
