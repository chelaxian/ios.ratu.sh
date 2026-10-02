#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <notify.h>
int main(void){@autoreleasepool{
 int token=-1;uint64_t state=0;
 if(notify_register_check("com.apple.springboard.lockstate",&token)==NOTIFY_STATUS_OK){notify_get_state(token,&state);notify_cancel(token);printf("SCREEN_LOCKED=%d\n",state!=0);}
 token=-1;state=0;
 if(notify_register_check("com.ratush.appsplitvpn.ui-lock",&token)==NOTIFY_STATUS_OK){notify_get_state(token,&state);notify_cancel(token);printf("UI_LOCK_VALID=%d UI_LOCKED=%d\n",(state&2)!=0,(state&1)!=0);}
 void *library=dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote",RTLD_NOW);
 void(*query)(dispatch_queue_t,void(^)(BOOL))=library?dlsym(library,"MRMediaRemoteGetNowPlayingApplicationIsPlaying"):NULL;
 if(!query){puts("MEDIA_QUERY_UNAVAILABLE");return 2;}
 __block BOOL done=NO;
 query(dispatch_get_main_queue(),^(BOOL playing){printf("MEDIA_PLAYING=%d\n",playing);done=YES;});
 NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:6];
 while(!done&&deadline.timeIntervalSinceNow>0)[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
 if(!done){puts("MEDIA_QUERY_TIMEOUT");return 3;}return 0;
}}
