#import "../source/AppSplitVPN-rootless/ASVSettingsTransfer.h"
#import <assert.h>
int main(void){@autoreleasepool{
 NSArray *local=@[@{@"id":@"local-a",@"owner":@"app.vpn",@"name":@"A"}];
 NSDictionary *prefs=@{@"enabled":@YES,ASV_RED_CYCLES:@3,ASV_VPN:@[@"good",@"missing"],ASV_DIRECT:@[],ASV_MATRIX:@{@"good":@"foreign-a",@"missing":@"gone"},ASV_RESERVES:@[@"foreign-a",@"gone"],ASV_PRIMARY:@"gone",ASV_REDUNDANCY:@YES};
 NSArray *foreign=@[@{@"id":@"foreign-a",@"owner":@"app.vpn",@"name":@"A"}];
 NSDictionary *export=ASVExportSettings(prefs,foreign);NSUInteger skipped=0;
 NSDictionary *result=ASVImportSettings(export,@{},[NSSet setWithObject:@"good"],local,nil,&skipped);
 assert(result && skipped==4);assert([result[ASV_VPN] isEqual:@[@"good"]]);assert([result[ASV_MATRIX][@"good"] isEqual:@"local-a"]);
 assert([result[ASV_RESERVES] isEqual:@[@"local-a"]]);assert(!result[ASV_PRIMARY]);assert([result[ASV_RED_CYCLES] isEqual:@3]);
 assert([result[ASV_HEALTH] boolValue] && [result[ASV_ALWAYS_ON] boolValue]);
 NSMutableDictionary *bad=[export mutableCopy];NSMutableDictionary *settings=[export[@"settings"] mutableCopy];settings[ASV_RED_CYCLES]=@99;bad[@"settings"]=settings;
 result=ASVImportSettings(bad,@{ASV_RED_CYCLES:@2},[NSSet setWithObject:@"good"],local,nil,&skipped);assert([result[ASV_RED_CYCLES] isEqual:@2]);
 assert(!ASVImportSettings(@{@"format":@"wrong"},@{},[NSSet set],local,nil,NULL));
 NSDictionary *off=@{@"enabled":@NO,@"mode":@"bypass",ASV_ALWAYS_ON:@YES};assert(!ASVExtraOptionActive(off,ASV_ALWAYS_ON));assert(ASVExtraOptionConfigured(off,ASV_ALWAYS_ON));
 assert(ASVExtraOptionActive(@{@"enabled":@YES,@"mode":@"bypass",ASV_ALWAYS_ON:@YES},ASV_ALWAYS_ON));
 assert(!ASVExtraOptionActive(@{@"enabled":@YES,@"mode":@"multiVPN",ASV_ALWAYS_ON:@YES},ASV_ALWAYS_ON));
 puts("settings transfer and global gate: PASS");
}return 0;}
