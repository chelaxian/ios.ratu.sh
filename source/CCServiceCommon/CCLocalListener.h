#ifndef RATU_CC_LOCAL_LISTENER_H
#define RATU_CC_LOCAL_LISTENER_H
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdbool.h>
#include <string.h>
#include <time.h>

// Probe this device's own interface addresses concurrently. A VPN/filter can
// reject IPv4 loopback while the same service is listening on Wi-Fi or IPv6.
// Never contact a gateway, peer, or remote VPN endpoint to infer local state.
static bool CCLocalListener(int port) {
    struct ifaddrs *interfaces=NULL;
    if(getifaddrs(&interfaces)!=0)return false;
    int sockets[64],count=0,maximum=-1;bool listening=false;
    fd_set pending;FD_ZERO(&pending);
    for(struct ifaddrs *item=interfaces;item && count<64;item=item->ifa_next){
        if(!item->ifa_addr || !(item->ifa_flags&IFF_UP) || (item->ifa_flags&IFF_POINTOPOINT))continue;
        int family=item->ifa_addr->sa_family;
        if(family!=AF_INET && family!=AF_INET6)continue;
        struct sockaddr_storage address;memset(&address,0,sizeof(address));
        socklen_t length=family==AF_INET?sizeof(struct sockaddr_in):sizeof(struct sockaddr_in6);
        memcpy(&address,item->ifa_addr,length);
        if(family==AF_INET)((struct sockaddr_in *)&address)->sin_port=htons(port);
        else ((struct sockaddr_in6 *)&address)->sin6_port=htons(port);
        int fd=socket(family,SOCK_STREAM,0);if(fd<0)continue;
        if(fd>=FD_SETSIZE || fcntl(fd,F_SETFL,O_NONBLOCK)<0){close(fd);continue;}
        int result=connect(fd,(struct sockaddr *)&address,length);
        if(result==0){close(fd);listening=true;break;}
        if(errno!=EINPROGRESS){close(fd);continue;}
        sockets[count++]=fd;FD_SET(fd,&pending);if(fd>maximum)maximum=fd;
    }
    freeifaddrs(interfaces);
    if(!listening && count){
        struct timespec started;clock_gettime(CLOCK_MONOTONIC,&started);
        int outstanding=count;
        while(!listening && outstanding){
            struct timespec now;clock_gettime(CLOCK_MONOTONIC,&now);
            double remaining=.15-(now.tv_sec-started.tv_sec)-(now.tv_nsec-started.tv_nsec)/1e9;
            if(remaining<=0)break;
            struct timeval timeout={0,(int)(remaining*1e6)};fd_set ready=pending;
            int result=select(maximum+1,NULL,&ready,NULL,&timeout);
            if(result<0 && errno==EINTR)continue;
            if(result<=0)break;
            for(int i=0;i<count;i++)if(FD_ISSET(sockets[i],&ready)){
                int error=0;socklen_t length=sizeof(error);
                if(getsockopt(sockets[i],SOL_SOCKET,SO_ERROR,&error,&length)==0 && !error){listening=true;break;}
                FD_CLR(sockets[i],&pending);outstanding--;
            }
        }
    }
    for(int i=0;i<count;i++)close(sockets[i]);
    return listening;
}
#endif
