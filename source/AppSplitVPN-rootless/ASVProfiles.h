#import <Foundation/Foundation.h>
// Only public display metadata is written to the catalogue, never protocol data or credentials.
void ASVProfilesRefresh(void);
NSArray<NSDictionary *> *ASVProfilesCatalog(void);
NSDictionary *ASVProfileRecord(NSString *uuid);
void ASVProfileConnect(NSString *uuid,BOOL (^shouldStart)(void),void (^completion)(BOOL ok,NSString *error));
void ASVProfileStop(NSString *uuid);
void ASVProfileStatus(NSString *uuid,void (^completion)(NSInteger status));
NSString *ASVProfileInterface(NSString *uuid);
