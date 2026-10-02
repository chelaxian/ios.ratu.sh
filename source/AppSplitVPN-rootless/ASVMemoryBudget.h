#pragma once
#include <stdint.h>
#include <unistd.h>
#include <dlfcn.h>
// Narrow Darwin 23 ABI, bsd/sys/kern_memorystatus.h. Only the calling daemon's
// PID is used. Preserve fatal attributes and never change priority/global limits.
typedef struct {int32_t active;uint32_t activeAttributes;int32_t inactive;uint32_t inactiveAttributes;} ASVMemLimits;
static inline int ASVConfigureOwnMemoryBudget(void){
    int(*control)(uint32_t,int32_t,uint32_t,void *,size_t)=dlsym(RTLD_DEFAULT,"memorystatus_control");
    if(!control || getuid()!=0)return 0;
    ASVMemLimits limits={0};if(control(8,getpid(),0,&limits,sizeof limits)!=0)return 0;
    if(limits.active>0 && limits.active<32)limits.active=32;
    if(limits.inactive>0 && limits.inactive<32)limits.inactive=32;
    if(control(7,getpid(),0,&limits,sizeof limits)!=0)return 0;
    ASVMemLimits actual={0};if(control(8,getpid(),0,&actual,sizeof actual)!=0)return 0;
    return actual.active==32 && actual.inactive==32?32:0;
}
