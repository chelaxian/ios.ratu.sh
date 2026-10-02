#import <Foundation/Foundation.h>
// Diagnostic only: never changes VPN state or policy. No unbound fallback.
void ASVIPProbe(NSString *interface, NSString *application, NSString *service, void (^completion)(NSArray *, NSString *));
