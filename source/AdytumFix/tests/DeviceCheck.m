#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "../BlockRepair.h"
static unsigned assertions;
#define CHECK(x) do { ++assertions; if (!(x)) { fprintf(stderr,"FAIL %d: %s\n",__LINE__,#x); return 1; } } while (0)
static bool Allow(void *p) { return p!=NULL; }
static bool Reject(void *p) { (void)p; return false; }
static unsigned finalized;
@interface Capture : NSObject
@end
@implementation Capture
- (void)dealloc { ++finalized; [super dealloc]; }
@end

int main(void) { @autoreleasepool {
#if !__has_feature(ptrauth_calls)
    fprintf(stderr,"This test must run as arm64e with real pointer authentication.\n"); return 2;
#else
    CHECK(!AFRepairBlock(NULL,Allow));
    struct AFBlock fake = {0};
    CHECK(!AFRepairBlock(&fake,Allow));
    for (unsigned i=0;i<100;++i) {
        Capture *capture = [Capture new];
        __block unsigned calls = 0;
        void (^stack)(id) = ^(id sender) { (void)sender; (void)[capture description]; ++calls; };
        struct AFBlock *layout = (void *)stack;
        uintptr_t signedISA = layout->isa;
        CHECK(signedISA!=(uintptr_t)_NSConcreteStackBlock);
        CHECK(!AFRepairBlock((void *)stack,Allow));
        layout->isa = (uintptr_t)_NSConcreteStackBlock; // Reproduce Adytum's unsigned stack isa.
        CHECK(!AFRepairBlock((void *)stack,Reject)); CHECK(layout->isa==(uintptr_t)_NSConcreteStackBlock);
        CHECK(AFRepairBlock((void *)stack,Allow)); CHECK(layout->isa==signedISA);
        CHECK(!AFRepairBlock((void *)stack,Allow)); // Idempotent.
        void (^copy)(id) = [stack copy];
        CHECK(!AFRepairBlock((void *)copy,Allow)); // Heap blocks untouched.
        [capture release];
        copy(nil); CHECK(calls==1);
        UIAction *action = [UIAction actionWithTitle:@"Adytum fixture" image:nil identifier:@"adytum-fixture" handler:stack];
        CHECK([action.title isEqual:@"Adytum fixture"]); // UIKit copies handler without SIGBUS.
        [copy release];
    }
    __block unsigned animations = 0;
    void (^animation)(void) = ^{ ++animations; };
    ((struct AFBlock *)(void *)animation)->isa = (uintptr_t)_NSConcreteStackBlock;
    CHECK(AFRepairBlock((void *)animation,Allow));
    [UIView animateWithDuration:0 delay:0 options:0 animations:animation completion:nil];
    CHECK(animations==1);
    __block unsigned springAnimations = 0;
    void (^spring)(void) = ^{ ++springAnimations; };
    ((struct AFBlock *)(void *)spring)->isa = (uintptr_t)_NSConcreteStackBlock;
    CHECK(AFRepairBlock((void *)spring,Allow));
    [UIView animateWithDuration:0 delay:0 usingSpringWithDamping:1 initialSpringVelocity:0 options:0 animations:spring completion:nil];
    CHECK(springAnimations==1);
    printf("PASS: %u arm64e assertions; repaired blocks copy and execute, UIAction and both UIView routes accept them.\n",assertions);
#endif
} // Drain autoreleased UIActions, releasing their captured objects.
    if (finalized!=100) { fprintf(stderr,"FAIL captured objects finalized=%u, expected=100\n",finalized); return 1; }
    puts("PASS: captured object lifetimes preserved.");
    return 0;
}
