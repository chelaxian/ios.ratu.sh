#import "Shared.h"

// Settings only: never export VPN credentials or configuration objects.
static inline NSDictionary *ASVSettingsDefaults(void) {
 return @{@"enabled":@NO,@"mode":@"bypass",@"language":@"system",@"badgeColor":@YES,
 ASV_VPN:@[],ASV_DIRECT:@[],ASV_MATRIX:@{},ASV_LS_DISCONNECT:@NO,ASV_LS_MEDIA:@NO,
 ASV_ALWAYS_ON:@NO,ASV_HEALTH:@NO,ASV_REDUNDANCY:@NO,ASV_RESERVES:@[],ASV_PRIMARY:@"",
 ASV_RED_ALGORITHM:@"roundRobin",ASV_RED_CYCLES:@1,ASV_LS_DELAY:@5,ASV_HC_METHOD:@"https",
 ASV_HC_TARGET:ASV_DEFAULT_HC_TARGET,ASV_HC_PORT:@0,ASV_HC_INTERVAL:@60,ASV_HC_TIMEOUT:@15,
 ASV_HC_FAILURES:@3,ASV_IP_SERVICE:ASV_DEFAULT_IP_SERVICE};
}
static inline NSDictionary *ASVExportSettings(NSDictionary *prefs,NSArray *catalog) {
 NSMutableDictionary *settings=[ASVSettingsDefaults() mutableCopy];
 for(NSString *key in settings.allKeys)if(prefs[key])settings[key]=prefs[key];
 NSMutableArray *profiles=[NSMutableArray array];
 for(NSDictionary *r in catalog)if([r[@"id"] isKindOfClass:NSString.class] && [r[@"name"] isKindOfClass:NSString.class] && [r[@"owner"] isKindOfClass:NSString.class])
 [profiles addObject:@{@"id":r[@"id"],@"name":r[@"name"],@"owner":r[@"owner"]}];
 return @{@"format":@"appsplitvpn-settings-v3",@"settings":settings,@"profiles":profiles};
}
static inline NSMutableDictionary *ASVImportSettings(NSDictionary *payload,NSDictionary *current,NSSet *apps,NSArray *catalog,BOOL (^validText)(NSString *,NSString *),NSUInteger *skipped) {
 if(![payload isKindOfClass:NSDictionary.class])return nil;
 BOOL full=[payload[@"format"] isEqual:@"appsplitvpn-settings-v3"];
 if(!full && ![@[@"appsplitvpn-lists-v1",@"appsplitvpn-lists-v2"] containsObject:payload[@"format"] ?: @""])return nil;
 NSDictionary *raw=full?payload[@"settings"]:payload;if(![raw isKindOfClass:NSDictionary.class] || raw.count>128)return nil;
 NSMutableDictionary *result=[current mutableCopy] ?: [NSMutableDictionary dictionary];
 NSMutableDictionary *known=[NSMutableDictionary dictionary],*mapping=[NSMutableDictionary dictionary];
 for(NSDictionary *r in catalog)if([r[@"id"] isKindOfClass:NSString.class])known[r[@"id"]]=r;
 id exported=payload[@"profiles"];
 if([exported isKindOfClass:NSArray.class] && [exported count]<=4096)for(id r in exported){
  if(![r isKindOfClass:NSDictionary.class] || ![r[@"id"] isKindOfClass:NSString.class])continue;
  NSString *match=nil;NSUInteger count=0;
  for(NSDictionary *local in catalog)if([local[@"name"] isEqual:r[@"name"]] && [local[@"owner"] isEqual:r[@"owner"]]){match=local[@"id"];count++;}
  if(count==1)mapping[r[@"id"]]=match;
 }
 NSString *(^profile)(id)=^NSString *(id value){if(![value isKindOfClass:NSString.class])return nil;return known[value]?value:mapping[value];};
 NSUInteger ignored=0;
 NSArray *bools=@[@"enabled",@"badgeColor",ASV_LS_DISCONNECT,ASV_LS_MEDIA,ASV_ALWAYS_ON,ASV_HEALTH,ASV_REDUNDANCY];
 NSDictionary *choices=@{@"mode":@[@"bypass",@"tunnelOnly",@"multiVPN"],@"language":@[@"system",@"ru",@"en"],ASV_HC_METHOD:@[@"https",@"http",@"tcp",@"ping"],ASV_RED_ALGORITHM:@[@"roundRobin",@"random"]};
 NSDictionary *ranges=@{ASV_LS_DELAY:@[@0,@600],ASV_RED_CYCLES:@[@1,@10],ASV_HC_FAILURES:@[@1,@10],ASV_HC_INTERVAL:@[@10,@3600],ASV_HC_TIMEOUT:@[@1,@120],ASV_HC_PORT:@[@0,@65535]};
 for(NSString *key in ASVSettingsDefaults()){
  id value=raw[key];if(!value)continue;
  if([bools containsObject:key]){if([value isKindOfClass:NSNumber.class] && ( [value isEqual:@YES] || [value isEqual:@NO]))result[key]=@([value boolValue]);else ignored++;}
  else if(choices[key]){if([choices[key] containsObject:value])result[key]=value;else ignored++;}
  else if(ranges[key]){NSArray *range=ranges[key];if([value isKindOfClass:NSNumber.class] && [value doubleValue]==[value integerValue] && [value integerValue]>=[range[0] integerValue] && [value integerValue]<=[range[1] integerValue])result[key]=value;else ignored++;}
  else if([key isEqual:ASV_VPN] || [key isEqual:ASV_DIRECT]){
   if(![value isKindOfClass:NSArray.class] || [value count]>2048){ignored++;continue;}
   NSMutableOrderedSet *kept=[NSMutableOrderedSet orderedSet];for(id app in value)if([app isKindOfClass:NSString.class] && [apps containsObject:app])[kept addObject:app];else ignored++;
   result[key]=kept.array;
  }else if([key isEqual:ASV_MATRIX]){
   if(![value isKindOfClass:NSDictionary.class] || [value count]>2048){ignored++;continue;}
   NSMutableDictionary *kept=[NSMutableDictionary dictionary];for(id app in value){NSString *local=profile(value[app]);if([app isKindOfClass:NSString.class] && [apps containsObject:app] && local)kept[app]=local;else ignored++;}result[key]=kept;
  }else if([key isEqual:ASV_RESERVES]){
   if(![value isKindOfClass:NSArray.class] || [value count]>64){ignored++;continue;}
   NSMutableOrderedSet *kept=[NSMutableOrderedSet orderedSet];for(id uuid in value){NSString *local=profile(uuid);if(local)[kept addObject:local];else ignored++;}result[key]=kept.array;
  }else if([key isEqual:ASV_PRIMARY]){NSString *local=profile(value);if(local)result[key]=local;else {[result removeObjectForKey:key];if([value isKindOfClass:NSString.class] && [value length])ignored++;}}
  else if([value isKindOfClass:NSString.class] && [value length]<=2048 && (!validText || validText(key,value)))result[key]=value;
  else ignored++;
 }
 if([result[ASV_REDUNDANCY] boolValue]){result[ASV_HEALTH]=@YES;result[ASV_ALWAYS_ON]=@YES;}
 if(result[ASV_PRIMARY] && [result[ASV_RESERVES] isKindOfClass:NSArray.class]){NSMutableArray *reserves=[result[ASV_RESERVES] mutableCopy];[reserves removeObject:result[ASV_PRIMARY]];result[ASV_RESERVES]=reserves;}
 if(skipped)*skipped=ignored;return result;
}
