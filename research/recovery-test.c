#include <assert.h>
#include <stdio.h>
#include "../source/AppSplitVPN-rootless/RecoveryCore.h"
#include "../source/AppSplitVPN-rootless/MediaCore.h"
int main(void) {
 assert(!ASVMediaShouldHold(false,true,true,true,true,0));
 assert(!ASVMediaShouldHold(true,false,true,true,true,0));
 assert(!ASVMediaShouldHold(true,true,false,true,true,0));
 assert(ASVMediaShouldHold(true,true,true,true,true,0));
 assert(!ASVMediaShouldHold(true,true,true,true,false,0));
 assert(ASVMediaShouldHold(true,true,true,false,false,0));
 assert(ASVMediaShouldHold(true,true,true,true,false,7));
 ASVRecovery r={0};assert(!ASVRecoveryProbeFailed(&r,3));assert(!ASVRecoveryProbeFailed(&r,3));assert(ASVRecoveryProbeFailed(&r,3));
 assert(!ASVRecoveryCycleFailed(&r,3));assert(!ASVRecoveryCycleFailed(&r,3));assert(ASVRecoveryCycleFailed(&r,3));
 ASVRecoverySuccess(&r);assert(!ASVRecoveryCycleFailed(&r,3));assert(r.cycles==0);assert(!ASVRecoveryCycleFailed(&r,3));assert(r.cycles==1);ASVRecoverySuccess(&r);assert(r.cycles==0);
 for(unsigned random=0;random<2;random++){uint64_t tried=0;unsigned cursor=3;for(unsigned n=0;n<4;n++){int next=ASVReserveNext(tried,4,cursor,random,17+n);assert(next>=0 && !(tried&(UINT64_C(1)<<next)));tried|=UINT64_C(1)<<next;cursor=next;}assert(ASVReserveNext(tried,4,cursor,random,0)==-1);}
 assert(ASVReserveNext(0,0,0,false,0)==-1);puts("recovery state machine: PASS");return 0;
}
