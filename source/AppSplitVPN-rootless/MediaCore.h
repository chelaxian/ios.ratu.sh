#ifndef ASV_MEDIA_CORE_H
#define ASV_MEDIA_CORE_H
#include <stdbool.h>
static inline bool ASVMediaShouldHold(bool locked,bool lsEnabled,bool protectedMedia,bool known,bool playing,double observationAge) {
 return locked && lsEnabled && protectedMedia && (!known || observationAge>6 || playing);
}
#endif
