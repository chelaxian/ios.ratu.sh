#import <Foundation/Foundation.h>
// Main-queue only. Resolver credentials remain in memory, never preferences/logs.
void ASVSystemDNSTick(BOOL enabled, void (^changed)(void));
NSArray<NSDictionary *> *ASVSystemDNSRules(void);
NSString *ASVSystemDNSWarning(void);
