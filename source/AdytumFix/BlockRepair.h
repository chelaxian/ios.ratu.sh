#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <ptrauth.h>

extern void *_NSConcreteStackBlock[];
struct AFBlock {
    uintptr_t isa;
    uint32_t flags, reserved;
    uintptr_t invoke, descriptor;
};
typedef bool (*AFOriginCheck)(void *invoke);

// Never send Objective-C messages to the input until its isa is valid.
// Only a raw stack-block isa on the current thread's stack is eligible.
// No heap/global blocks, code pages, descriptors or function pointers are changed.
static bool AFRepairBlock(void *candidate, AFOriginCheck allowed) {
#if __has_feature(ptrauth_calls)
    if (!candidate || !allowed) return false;
    uintptr_t upper = (uintptr_t)pthread_get_stackaddr_np(pthread_self());
    size_t size = pthread_get_stacksize_np(pthread_self());
    uintptr_t address = (uintptr_t)candidate;
    if (address % sizeof(void *) || address < upper-size || address > upper-sizeof(struct AFBlock)) return false;
    struct AFBlock *block = candidate;
    uintptr_t rawClass = (uintptr_t)_NSConcreteStackBlock;
    if (block->isa != rawClass || (block->flags & ((1u<<24)|(1u<<28))) || !(block->flags & (1u<<30))) return false;
    void *invoke = ptrauth_strip((void *)block->invoke,ptrauth_key_function_pointer);
    if (!invoke || !allowed(invoke)) return false;
    // Matches __ptrauth_objc_isa_pointer in the Apple Blocks runtime:
    // DA, address diversity, discriminator ptrauth_string_discriminator("isa").
    block->isa = (uintptr_t)ptrauth_sign_unauthenticated((void *)rawClass,
        ptrauth_key_process_dependent_data,ptrauth_blend_discriminator(&block->isa,0x6ae1));
    return true;
#else
    (void)candidate; (void)allowed;
    return false;
#endif
}
