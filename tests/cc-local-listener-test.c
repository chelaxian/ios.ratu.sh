#define _DEFAULT_SOURCE
#include <assert.h>
#include <stdio.h>
#include "../source/CCServiceCommon/CCLocalListener.h"
static void check(int family,struct sockaddr *address,socklen_t length,const char *name){
    int fd=socket(family,SOCK_STREAM,0);assert(fd>=0);
    if(family==AF_INET6){int only=1;assert(setsockopt(fd,IPPROTO_IPV6,IPV6_V6ONLY,&only,sizeof(only))==0);}
    assert(bind(fd,address,length)==0);assert(listen(fd,16)==0);
    assert(getsockname(fd,address,&length)==0);
    int port=ntohs(family==AF_INET?((struct sockaddr_in *)address)->sin_port:((struct sockaddr_in6 *)address)->sin6_port);
    assert(CCLocalListener(port));close(fd);assert(!CCLocalListener(port));
    printf("PASS %s listener ON -> OFF\n",name);
}
int main(void){
    struct sockaddr_in v4={0};v4.sin_family=AF_INET;v4.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    check(AF_INET,(struct sockaddr *)&v4,sizeof(v4),"IPv4 loopback");
    struct sockaddr_in6 v6={0};v6.sin6_family=AF_INET6;v6.sin6_addr=in6addr_loopback;
    check(AF_INET6,(struct sockaddr *)&v6,sizeof(v6),"IPv6 only (no IPv4 listener)");
    struct ifaddrs *interfaces=NULL;assert(getifaddrs(&interfaces)==0);bool found=false;
    for(struct ifaddrs *item=interfaces;item;item=item->ifa_next){
        if(!item->ifa_addr || item->ifa_addr->sa_family!=AF_INET || !(item->ifa_flags&IFF_UP) || (item->ifa_flags&(IFF_LOOPBACK|IFF_POINTOPOINT)))continue;
        memcpy(&v4,item->ifa_addr,sizeof(v4));v4.sin_port=0;
        check(AF_INET,(struct sockaddr *)&v4,sizeof(v4),"interface only (no loopback listener)");found=true;break;
    }
    freeifaddrs(interfaces);if(!found)puts("SKIP no non-loopback IPv4 interface");return 0;
}
