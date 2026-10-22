#include <assert.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include "../source/CatMCPCC-rootless/MCPListener.h"

int main(void) {
    int fd=socket(AF_INET,SOCK_STREAM,0);assert(fd>=0);
    struct sockaddr_in address={0};address.sin_family=AF_INET;
    address.sin_addr.s_addr=htonl(INADDR_LOOPBACK);
    assert(bind(fd,(struct sockaddr *)&address,sizeof(address))==0);
    socklen_t length=sizeof(address);
    assert(getsockname(fd,(struct sockaddr *)&address,&length)==0);
    int port=ntohs(address.sin_port);
    assert(MCPProcessListener(getpid(),port)==0); // bind alone is not ON
    assert(listen(fd,2)==0);
    assert(fcntl(fd,F_SETFL,O_NONBLOCK)==0);
    for(int i=0;i<1000;i++)assert(MCPProcessListener(getpid(),port)==1);
    // Repeated status reads must not enqueue even one TCP connection.
    assert(accept(fd,NULL,NULL)==-1 && (errno==EAGAIN || errno==EWOULDBLOCK));
    assert(MCPProcessListener(getpid(),port==65535?port-1:port+1)==0);
    close(fd);
    assert(MCPProcessListener(getpid(),port)==0);
    assert(MCPProcessListener(2147483647,port)!=1);
    puts("PASS: bound/listening/closed, wrong port/PID, 1000 passive polls without queued clients");
    return 0;
}
