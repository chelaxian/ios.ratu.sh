#ifndef ASV_RECOVERY_CORE_H
#define ASV_RECOVERY_CORE_H
#include <stdint.h>
#include <stdbool.h>
// A cycle ends only when an established tunnel fails health or a start times out.
// An individual failed probe is not a failed recovery cycle.
typedef struct { unsigned probes, cycles; bool healthy; } ASVRecovery;
static inline void ASVRecoverySuccess(ASVRecovery *s) { s->probes=0;s->cycles=0;s->healthy=true; }
static inline bool ASVRecoveryProbeFailed(ASVRecovery *s,unsigned limit) { return ++s->probes>=limit; }
static inline bool ASVRecoveryCycleFailed(ASVRecovery *s,unsigned limit) {
 bool hadSuccess=s->healthy;s->healthy=false;s->probes=0;if(hadSuccess){s->cycles=0;return false;}return ++s->cycles>=limit;
}
static inline int ASVReserveNext(uint64_t tried,unsigned count,unsigned after,bool random,unsigned entropy) {
 if(count>64)count=64;
 if(!count)return -1;
 unsigned remaining=0;for(unsigned i=0;i<count;i++)if(!(tried&(UINT64_C(1)<<i)))remaining++;
 if(!remaining)return -1;
 unsigned rank=random?entropy%remaining:0;
 for(unsigned offset=1;offset<=count;offset++){unsigned i=(after+offset)%count;if(!(tried&(UINT64_C(1)<<i))){if(!rank)return (int)i;rank--;}}
 return -1;
}
#endif
