#import <Foundation/Foundation.h>
// Lock-screen disconnect, Always ON reconnect and health-check disconnect.
// Acts only on the VPN configuration selected in iOS Settings, through the same
// session API as the system VPN switch, so it is independent of the VPN client.
void ASVSupervisorStart(void);
void ASVSupervisorTick(void);
void ASVSupervisorSetEnabled(BOOL enabled);
void ASVSupervisorSetTransactionPaused(BOOL paused);
NSString *ASVSupervisorVPNName(void);

