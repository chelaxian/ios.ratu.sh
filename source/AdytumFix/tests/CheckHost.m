#import <Foundation/Foundation.h>
#import <stdio.h>
#import <stdarg.h>
static FILE *AFOutput;
static int AFPrintf(const char *format,...) {
    va_list args; va_start(args,format); int result=vfprintf(AFOutput,format,args); va_end(args);
    fflush(AFOutput); return result;
}
static int AFPuts(const char *text) { return AFPrintf("%s\n",text); }
#define printf AFPrintf
#define fprintf(stream,...) AFPrintf(__VA_ARGS__)
#define puts AFPuts
#define main AFRunCheck
#import "DeviceCheck.m"
#undef main
__attribute__((constructor)) static void AFCheckStart(void) {
    @autoreleasepool {
        if (![NSBundle.mainBundle.bundleIdentifier isEqual:@"com.apple.Preferences"]) return;
        dispatch_async(dispatch_get_main_queue(),^{
            AFOutput=fopen("/var/mobile/Library/Logs/AdytumFix-check.log","w");
            if (!AFOutput) return;
            int result=AFRunCheck();
            AFPrintf("RESULT=%d\n",result);
            fclose(AFOutput); AFOutput=NULL;
        });
    }
}
