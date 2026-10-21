#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import "../source/AppSplitVPN-rootless/ASVSystemDNS.h"
// Bounded device diagnostic: no application routing policies, no profile edits,
// no endpoints or credentials printed. Link ASVSystemDNS.m and sign like ne-probe.
int main(void){@autoreleasepool{
    dlopen("/System/Library/Frameworks/NetworkExtension.framework/NetworkExtension",RTLD_NOW);
    ASVSystemDNSTick(YES,^{NSLog(@"DNS rules=%lu warning=%@",(unsigned long)ASVSystemDNSRules().count,ASVSystemDNSWarning());});
    [[NSRunLoop mainRunLoop]runUntilDate:[NSDate dateWithTimeIntervalSinceNow:6]];
    NSUInteger count=ASVSystemDNSRules().count;
    ASVSystemDNSTick(NO,nil);
    NSLog(@"DNS cleanup=%lu",(unsigned long)ASVSystemDNSRules().count);
    return count?0:2;
}}
