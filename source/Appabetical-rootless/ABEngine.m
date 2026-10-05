// Appabetical 2, Dopamine/ElleKit, GPLv3. Original: Avangelista/Appabetical,
// Avangelista and sourcelocation. Presets inspired by OwnGoalStudio/IconRestore.
#import "ABShared.h"
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <unistd.h>
static NSString *const ABPresetPath=@"/var/mobile/Library/SpringBoard/AppabeticalPresets.plist";
static NSString *const ABCheckpointPath=@"/var/mobile/Library/SpringBoard/AppabeticalRestore.plist";
static NSString *const ABRecoveryPath=@"/var/mobile/Library/SpringBoard/AppabeticalRecovery";
static NSString *const ABLogPath=@"/var/mobile/Library/Preferences/com.ratush.appabetical.debug.log";
static BOOL ABReady,ABBusy;
static NSDictionary *ABOptions;
static void ABLog(NSString *format,...) NS_FORMAT_FUNCTION(1,2);
static void ABLog(NSString *format,...) {
    va_list args;va_start(args,format);NSString *line=[[NSString alloc] initWithFormat:format arguments:args];va_end(args);
    if([NSFileManager.defaultManager attributesOfItemAtPath:ABLogPath error:nil].fileSize>1024*1024) [NSFileManager.defaultManager removeItemAtPath:ABLogPath error:nil];
    FILE *file=fopen(ABLogPath.fileSystemRepresentation,"a");if(file){fprintf(file,"%s %s\n",NSDate.date.description.UTF8String,line.UTF8String);fclose(file);}
}
static id ABGet(id object,NSString *name) {
    SEL s=NSSelectorFromString(name);return [object respondsToSelector:s] ? ((id(*)(id,SEL))objc_msgSend)(object,s) : nil;
}
static id ABGet1(id object,NSString *name,id arg) {
    SEL s=NSSelectorFromString(name);return [object respondsToSelector:s] ? ((id(*)(id,SEL,id))objc_msgSend)(object,s,arg) : nil;
}
static BOOL ABFlag(id object,NSString *name) {
    SEL s=NSSelectorFromString(name);return [object respondsToSelector:s] && ((BOOL(*)(id,SEL))objc_msgSend)(object,s);
}
static void ABVoid(id object,NSString *name) {
    SEL s=NSSelectorFromString(name);if([object respondsToSelector:s]) ((void(*)(id,SEL))objc_msgSend)(object,s);
}
static id ABController(void){return ABGet(NSClassFromString(@"SBIconController"),@"sharedInstance");}
static id ABModel(void){return ABGet(ABController(),@"model");}
static BOOL ABWritePlist(id value,NSString *path,NSError **error) {
    NSData *data=[NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:error];
    return data && [data writeToFile:path options:NSDataWritingAtomic error:error];
}
// iconState reads the model STORE; flush live mutations before any snapshot.
static NSDictionary *ABSnapshot(NSError **error) {
    id model=ABModel();SEL save=NSSelectorFromString(@"saveIconStateIfNeeded");
    if(!model || ![model respondsToSelector:save] || !((BOOL(*)(id,SEL))objc_msgSend)(model,save)) {
        if(error)*error=[NSError errorWithDomain:ABDomain code:1 userInfo:@{NSLocalizedDescriptionKey:@"SpringBoard could not save the current layout"}];return nil;
    }
    id state=ABGet(model,@"iconState");
    return [state isKindOfClass:NSDictionary.class] && [state[@"iconLists"] isKindOfClass:NSArray.class] && [state[@"buttonBar"] isKindOfClass:NSArray.class] ? state : nil;
}
static BOOL ABBackup(NSDictionary *state,NSError **error) {
    NSString *path=[ABRecoveryPath stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    if(![NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error])return NO;
    ABLog(@"Recovery snapshot %@",path);return ABWritePlist(state,[path stringByAppendingPathComponent:@"IconState.plist"],error);
}
static void ABCollect(id value,NSMutableDictionary *counts) {
    if([value isKindOfClass:NSArray.class]){for(id item in value)ABCollect(item,counts);return;}
    id key=nil;
    if([value isKindOfClass:NSString.class])key=[@"app:" stringByAppendingString:value];
    else if([value isKindOfClass:NSDictionary.class]) {
        if([value[@"listType"] isEqual:@"folder"]){key=[@"folder:" stringByAppendingString:value[@"uniqueIdentifier"] ?: value[@"displayName"] ?: @""];ABCollect(value[@"iconLists"],counts);}
        else if([@[@"app",@"user",@"system"] containsObject:value[@"iconType"] ?: @""])key=[@"app:" stringByAppendingString:value[@"bundleIdentifier"] ?: value[@"displayIdentifier"] ?: @""];
        else key=value; // Full dictionary equality preserves every widget element.
    }else if(value)key=value;
    if(key)counts[key]=@([counts[key] unsignedIntegerValue]+1);
}
static NSDictionary *ABInventory(NSDictionary *state) {
    NSMutableDictionary *counts=NSMutableDictionary.dictionary;ABCollect(state[@"iconLists"],counts);ABCollect(state[@"buttonBar"],counts);ABCollect(state[@"today"],counts);return counts;
}
static BOOL ABValidState(NSDictionary *state) {
    if(![state isKindOfClass:NSDictionary.class] || ![state[@"iconLists"] isKindOfClass:NSArray.class] || ![state[@"buttonBar"] isKindOfClass:NSArray.class])return NO;
    NSArray *lists=state[@"iconLists"],*ids=state[@"listUniqueIdentifiers"];
    if(![ids isKindOfClass:NSArray.class] || ids.count!=lists.count)return NO;
    for(id page in lists){if(![page isKindOfClass:NSArray.class])return NO;for(id item in page)
        if([item isKindOfClass:NSDictionary.class] && [item[@"listType"] isEqual:@"folder"] && !ABValidState(@{@"iconLists":item[@"iconLists"] ?: @[],@"listUniqueIdentifiers":item[@"listUniqueIdentifiers"] ?: @[],@"buttonBar":@[]}))return NO;}
    return YES;
}
static void ABRespond(NSDictionary *request,BOOL ok,NSString *message,NSDictionary *details) {
    NSMutableDictionary *response=[@{@"id":request[@"id"] ?: @"automatic",@"command":request[@"command"] ?: @"sort",@"ok":@(ok),@"message":message ?: @"",@"date":NSDate.date} mutableCopy];
    if(details)[response addEntriesFromDictionary:details];ABWritePreference(@"response",response);notify_post(ABResponseNotification.UTF8String);ABLog(@"%@ %@: %@",response[@"command"],ok ? @"PASS" : @"FAIL",message);
}
static BOOL ABEmojiScalar(UTF32Char c) {
    return (c>=0x1F000&&c<=0x1FAFF)||(c>=0x2600&&c<=0x27BF)||c==0xFE0F||c==0xFE0E||c==0x200D||c==0x20E3||(c>=0xE0020&&c<=0xE007F)||
    c==0x00A9||c==0x00AE||c==0x203C||c==0x2049||c==0x2122||c==0x2139||(c>=0x2194&&c<=0x2199)||c==0x21A9||c==0x21AA||c==0x231A||c==0x231B||c==0x2328||c==0x23CF||(c>=0x23E9&&c<=0x23F3)||(c>=0x23F8&&c<=0x23FA)||c==0x24C2||c==0x25AA||c==0x25AB||c==0x25B6||c==0x25C0||(c>=0x25FB&&c<=0x25FE)||c==0x2934||c==0x2935||(c>=0x2B05&&c<=0x2B07)||c==0x2B1B||c==0x2B1C||c==0x2B50||c==0x2B55||c==0x3030||c==0x303D||c==0x3297||c==0x3299;
}
static NSString *ABSortKey(NSString *title,BOOL strip) {
    if(!strip)return title ?: @"";NSMutableString *result=NSMutableString.string;
    for(NSUInteger i=0;i<title.length;i++){unichar high=[title characterAtIndex:i];UTF32Char scalar=high;NSUInteger length=1;
        if(CFStringIsSurrogateHighCharacter(high)&&i+1<title.length){unichar low=[title characterAtIndex:i+1];if(CFStringIsSurrogateLowCharacter(low)){scalar=CFStringGetLongCharacterForSurrogatePair(high,low);length=2;}}
        if(!ABEmojiScalar(scalar))[result appendString:[title substringWithRange:NSMakeRange(i,length)]];i+=length-1;}
    return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
static NSUInteger ABBucket(NSString *key) {
    NSString *folded=[key stringByFoldingWithOptions:NSDiacriticInsensitiveSearch locale:[NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"]];
    for(NSUInteger i=0;i<folded.length;i++){unichar c=[folded characterAtIndex:i];if((c>='A'&&c<='Z')||(c>='a'&&c<='z'))return 0;if(c>=0x0400&&c<=0x052F)return 1;if([NSCharacterSet.letterCharacterSet characterIsMember:c])return 2;}return 2;
}
@interface ABEntry : NSObject
@property(nonatomic,strong)id icon;
@property(nonatomic,copy)NSString *key;
@property(nonatomic)NSUInteger index,bucket,tier,end;
@end
@implementation ABEntry
@end
static BOOL ABMovable(id icon,BOOL folders) {
    if(ABFlag(icon,@"isWidgetIcon")||ABFlag(icon,@"isPlaceholder"))return NO;
    return (folders&&ABFlag(icon,@"isFolderIcon"))||ABFlag(icon,@"isApplicationIcon")||ABFlag(icon,@"isBookmarkIcon");
}
static ABEntry *ABEntryForIcon(id icon,NSUInteger index) {
    ABEntry *entry=ABEntry.new;entry.icon=icon;entry.index=index;id title=ABGet(icon,@"displayName");
    entry.key=ABSortKey([title isKindOfClass:NSString.class]?title:@"",ABBool(ABOptions,@"ignoreEmoji",YES));entry.bucket=ABBucket(entry.key);entry.tier=ABFlag(icon,@"isFolderIcon")?1:0;
    if(ABFlag(icon,@"isBookmarkIcon")) {
        if(ABBool(ABOptions,@"placeBookmarksAtEnd",NO))entry.end=1;
        NSURL *url=ABGet(ABGet(icon,@"webClip"),@"pageURL");if([url isKindOfClass:NSURL.class]&&[url.scheme.lowercaseString isEqual:@"shortcuts"])entry.tier=2;
    }else if(ABFlag(icon,@"isApplicationIcon")&&ABBool(ABOptions,@"placeOffloadedAtEnd",YES)) {
        NSString *bid=ABGet(ABGet(icon,@"application"),@"bundleIdentifier");if([bid isKindOfClass:NSString.class]){id proxy=ABGet1(NSClassFromString(@"LSApplicationProxy"),@"applicationProxyForIdentifier:",bid);if(proxy&&[proxy respondsToSelector:NSSelectorFromString(@"isInstalled")]&&!ABFlag(proxy,@"isInstalled"))entry.end=2;}
    }return entry;
}
static NSComparisonResult ABCompare(ABEntry *a,ABEntry *b) {
    if(a.end!=b.end)return a.end<b.end?NSOrderedAscending:NSOrderedDescending;if(a.tier!=b.tier)return a.tier<b.tier?NSOrderedAscending:NSOrderedDescending;if(a.bucket!=b.bucket)return a.bucket<b.bucket?NSOrderedAscending:NSOrderedDescending;
    NSComparisonResult result=a.bucket==2?NSOrderedSame:[a.key compare:b.key options:NSCaseInsensitiveSearch|NSNumericSearch|NSDiacriticInsensitiveSearch];
    return result!=NSOrderedSame?result:a.index==b.index?NSOrderedSame:a.index<b.index?NSOrderedAscending:NSOrderedDescending;
}
// Each plan stays inside one container. Widgets and excluded folders have no
// destination slots, and the dock is planned independently of Home Screen pages.
static void ABPlan(id folder,NSArray *lists,BOOL allowFolders,NSMutableArray *plans,NSMutableSet *seen,NSUInteger depth) {
    if(!folder||depth>32||[seen containsObject:folder])return;[seen addObject:folder];NSMutableArray *entries=NSMutableArray.array,*paths=NSMutableArray.array;
    for(id list in lists)for(id icon in [ABGet(list,@"icons") copy]) {
        if(ABMovable(icon,allowFolders)){NSIndexPath *path=ABGet1(folder,@"indexPathForIcon:",icon);if(!path)@throw [NSException exceptionWithName:@"ABLayout" reason:@"Icon has no container position" userInfo:nil];[paths addObject:path];[entries addObject:ABEntryForIcon(icon,entries.count)];}
        if(ABFlag(icon,@"isFolderIcon")&&ABBool(ABOptions,@"sortInsideFolders",YES)){id child=ABGet(icon,@"folder");ABPlan(child,ABGet(child,@"lists"),NO,plans,seen,depth+1);}
    }
    NSArray *sorted=[entries sortedArrayUsingComparator:^NSComparisonResult(ABEntry *a,ABEntry *b){return ABCompare(a,b);}];
    if(entries.count)[plans addObject:@{@"folder":folder,@"entries":entries,@"sorted":sorted,@"paths":paths}];
}
static NSUInteger ABApplyPlans(NSArray *plans,NSMutableArray *undo) {
    NSUInteger moves=0;SEL swap=NSSelectorFromString(@"swapIconAtIndexPath:withIconAtIndexPath:options:");
    for(NSDictionary *plan in plans){id folder=plan[@"folder"];if(![folder respondsToSelector:swap])@throw [NSException exceptionWithName:@"ABLayout" reason:@"SpringBoard swap API unavailable" userInfo:nil];NSArray *sorted=plan[@"sorted"],*paths=plan[@"paths"];
        for(NSUInteger i=0;i<sorted.count;i++){NSIndexPath *from=ABGet1(folder,@"indexPathForIcon:",[sorted[i] icon]),*to=paths[i];if(!from)@throw [NSException exceptionWithName:@"ABLayout" reason:@"Icon disappeared during sorting" userInfo:nil];if([from isEqual:to])continue;
            [undo addObject:@{@"folder":folder,@"from":from,@"to":to}];((void(*)(id,SEL,id,id,NSUInteger))objc_msgSend)(folder,swap,from,to,0);
            if(![ABGet1(folder,@"indexPathForIcon:",[sorted[i] icon]) isEqual:to])@throw [NSException exceptionWithName:@"ABLayout" reason:@"SpringBoard rejected an icon swap" userInfo:nil];moves++;}}
    return moves;
}
static void ABUndo(NSArray *undo) {
    SEL swap=NSSelectorFromString(@"swapIconAtIndexPath:withIconAtIndexPath:options:");for(NSDictionary *step in undo.reverseObjectEnumerator)((void(*)(id,SEL,id,id,NSUInteger))objc_msgSend)(step[@"folder"],swap,step[@"from"],step[@"to"],0);
}
static void ABSort(NSDictionary *request) {
    if(!ABBool(ABOptions,@"enabled",YES)){ABRespond(request,NO,@"disabled",nil);return;}
    NSError *error=nil;NSDictionary *before=ABSnapshot(&error);if(!before||!ABBackup(before,&error)){ABRespond(request,NO,error.localizedDescription ?: @"Unable to snapshot layout",nil);return;}
    NSMutableArray *plans=NSMutableArray.array,*undo=NSMutableArray.array;
    @try {
        id root=ABGet(ABModel(),@"rootFolder");ABPlan(root,ABGet(root,@"lists"),ABBool(ABOptions,@"sortFolders",YES),plans,NSMutableSet.set,0);
        id dock=ABGet(ABGet(ABGet(ABController(),@"iconManager"),@"dockListView"),@"model");
        if(dock&&ABBool(ABOptions,@"includeDock",NO))ABPlan(root,@[dock],NO,plans,NSMutableSet.set,0);
        else if(dock&&ABBool(ABOptions,@"sortInsideFolders",YES))for(id icon in ABGet(dock,@"icons"))if(ABFlag(icon,@"isFolderIcon")){id folder=ABGet(icon,@"folder");ABPlan(folder,ABGet(folder,@"lists"),NO,plans,NSMutableSet.set,1);}
        NSUInteger moves=ABApplyPlans(plans,undo);NSDictionary *after=ABSnapshot(&error);
        if(!after||![ABInventory(before) isEqual:ABInventory(after)])@throw [NSException exceptionWithName:@"ABLayout" reason:@"Layout inventory validation failed" userInfo:nil];
        ABVoid(ABGet(ABController(),@"iconManager"),@"relayout");ABRespond(request,YES,moves?@"sorted":@"alreadySorted",@{@"swaps":@(moves)});
    }@catch(NSException *exception){@try{ABUndo(undo);ABSnapshot(NULL);}@catch(NSException *rollback){ABLog(@"Rollback error %@",rollback);}ABRespond(request,NO,exception.reason,nil);}
}
static NSDictionary *ABPresets(void){id value=[NSDictionary dictionaryWithContentsOfFile:ABPresetPath];return [value isKindOfClass:NSDictionary.class]?value:@{};}
static void ABCatalog(void){ABWritePreference(@"presetCatalog",[ABPresets().allKeys sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)]);}
static NSDictionary *ABCCPaths(void){return @{@"ccSupport":@"/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist",@"ccConfig":@"/var/mobile/Library/ControlCenter/ModuleConfiguration.plist"};}
static void ABSavePreset(NSDictionary *request) {
    NSString *name=request[@"name"];NSError *error=nil;NSDictionary *state=ABSnapshot(&error);if(!state){ABRespond(request,NO,error.localizedDescription ?: @"Cannot read layout",nil);return;}
    NSMutableDictionary *entry=[@{@"@appab_format":@3,@"iconState":state,@"created":NSDate.date} mutableCopy];
    if(ABBool(ABOptions,@"preserveCC",YES))for(NSString *key in ABCCPaths()){NSString *path=ABCCPaths()[key];if([NSFileManager.defaultManager fileExistsAtPath:path]){NSDictionary *cc=[NSDictionary dictionaryWithContentsOfFile:path];if(!cc){ABRespond(request,NO,@"Cannot read Control Center configuration",nil);return;}entry[key]=cc;}}
    NSMutableDictionary *presets=[ABPresets() mutableCopy];if(presets[name]&&![request[@"overwrite"] boolValue]){ABRespond(request,NO,@"exists",nil);return;}presets[name]=entry;
    if(!ABWritePlist(presets,ABPresetPath,&error)){ABRespond(request,NO,error.localizedDescription,nil);return;}ABCatalog();ABRespond(request,YES,@"saved",@{@"name":name});
}
static BOOL ABStoreState(NSDictionary *state,NSError **error) {
    id store=ABGet(NSClassFromString(@"SBDefaultIconModelStore"),@"sharedInstance");SEL s=NSSelectorFromString(@"saveCurrentIconState:error:");return [store respondsToSelector:s]&&((BOOL(*)(id,SEL,id,NSError **))objc_msgSend)(store,s,state,error);
}
static void ABRestorePreset(NSDictionary *request) {
    NSDictionary *entry=ABPresets()[request[@"name"]],*saved=[entry[@"iconState"] isKindOfClass:NSDictionary.class]?entry[@"iconState"]:entry;
    NSError *error=nil;NSDictionary *current=ABSnapshot(&error);if(!ABValidState(saved)||!current){ABRespond(request,NO,@"Invalid or missing layout preset",nil);return;}
    if(![ABInventory(current) isEqual:ABInventory(saved)]){ABRespond(request,NO,@"inventoryMismatch",nil);return;}if(!ABBackup(current,&error)){ABRespond(request,NO,error.localizedDescription,nil);return;}
    NSMutableDictionary *checkpoint=[@{@"request":request,@"expected":saved,@"previous":current,@"started":NSDate.date} mutableCopy],*ccBefore=NSMutableDictionary.dictionary,*ccAfter=NSMutableDictionary.dictionary;
    if(ABBool(ABOptions,@"preserveCC",YES))for(NSString *key in ABCCPaths()){id cc=entry[key];if(![cc isKindOfClass:NSDictionary.class])continue;NSString *path=ABCCPaths()[key];ccBefore[path]=[NSData dataWithContentsOfFile:path] ?: NSData.data;ccAfter[path]=cc;}
    checkpoint[@"ccBefore"]=ccBefore;checkpoint[@"ccExpected"]=ccAfter;
    if(!ABWritePlist(checkpoint,ABCheckpointPath,&error)){ABRespond(request,NO,error.localizedDescription,nil);return;}
    BOOL success=YES;for(NSString *path in ccAfter)if(!ABWritePlist(ccAfter[path],path,&error)){success=NO;break;}if(success)success=ABStoreState(saved,&error);
    if(!success){for(NSString *path in ccBefore){NSData *data=ccBefore[path];if(data.length)[data writeToFile:path options:NSDataWritingAtomic error:nil];else [NSFileManager.defaultManager removeItemAtPath:path error:nil];}ABStoreState(current,NULL);[NSFileManager.defaultManager removeItemAtPath:ABCheckpointPath error:nil];ABRespond(request,NO,error.localizedDescription ?: @"SpringBoard rejected layout",nil);return;}
    // Native store has completed its atomic write. A graceful relaunch would
    // allow the old live model to overwrite it. The NEXT process acknowledges
    // completion after verifying the restored layout; it skips autosort once.
    ABLog(@"Restore committed; restarting SpringBoard id=%@",request[@"id"]);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,250*NSEC_PER_MSEC),dispatch_get_main_queue(),^{_exit(0);});
}
static void ABFinishRestore(void) {
    NSDictionary *checkpoint=[NSDictionary dictionaryWithContentsOfFile:ABCheckpointPath];if(!checkpoint)return;NSDictionary *live=ABSnapshot(NULL),*expected=checkpoint[@"expected"];
    BOOL ok=live&&[live[@"iconLists"] isEqual:expected[@"iconLists"]]&&[live[@"buttonBar"] isEqual:expected[@"buttonBar"]]&&((!live[@"today"]&&!expected[@"today"])||[live[@"today"] isEqual:expected[@"today"]]);
    for(NSString *path in checkpoint[@"ccExpected"])if(![[NSDictionary dictionaryWithContentsOfFile:path] isEqual:checkpoint[@"ccExpected"][path]])ok=NO;
    ABRespond(checkpoint[@"request"],ok,ok?@"restored":@"Restored layout differs from preset; recovery snapshot retained",nil);[NSFileManager.defaultManager removeItemAtPath:ABCheckpointPath error:nil];
}
static void ABHandleCommand(void) {
    id raw=ABReadPreference(@"request");if(![raw isKindOfClass:NSDictionary.class])return;NSDictionary *request=raw;NSString *identifier=request[@"id"],*command=request[@"command"];
    if(![identifier isKindOfClass:NSString.class]||!identifier.length||![command isKindOfClass:NSString.class])return;
    id last=ABReadPreference(@"response");if([last isKindOfClass:NSDictionary.class]&&[last[@"id"] isEqual:identifier])return;
    if(!ABReady||ABBusy){ABRespond(request,NO,@"busy",nil);return;}ABBusy=YES;ABOptions=ABSettings();
    @try{if([command isEqual:@"sort"])ABSort(request);else if([command isEqual:@"catalog"]){ABCatalog();ABRespond(request,YES,@"catalog",nil);}
        else if([@[@"save",@"restore",@"delete"] containsObject:command]){NSString *name=request[@"name"];if(![name isKindOfClass:NSString.class]||!name.length||name.length>128)ABRespond(request,NO,@"Invalid preset name",nil);
            else if([command isEqual:@"save"])ABSavePreset(request);else if([command isEqual:@"restore"])ABRestorePreset(request);else {NSMutableDictionary *presets=[ABPresets() mutableCopy];[presets removeObjectForKey:name];NSError *error=nil;BOOL ok=ABWritePlist(presets,ABPresetPath,&error);if(ok)ABCatalog();ABRespond(request,ok,ok?@"deleted":error.localizedDescription,nil);}}
        else ABRespond(request,NO,@"Unknown command",nil);
    }@catch(NSException *exception){ABRespond(request,NO,exception.reason,nil);}ABBusy=NO;
}
static void ABStart(NSUInteger attempt) {
    id root=ABGet(ABModel(),@"rootFolder");if(!root||![ABGet(root,@"lists") count]){if(attempt<120)dispatch_after(dispatch_time(DISPATCH_TIME_NOW,500*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ABStart(attempt+1);});return;}
    ABReady=YES;ABOptions=ABSettings();ABCatalog();BOOL restoring=[NSFileManager.defaultManager fileExistsAtPath:ABCheckpointPath];
    if(restoring)ABFinishRestore();else if(ABBool(ABOptions,@"enabled",YES)&&ABBool(ABOptions,@"autoSortOnRespring",YES)){ABBusy=YES;ABSort(@{@"id":@"automatic",@"command":@"sort"});ABBusy=NO;}ABLog(@"Appabetical 2 ready pid=%d",getpid());
}
__attribute__((constructor)) static void ABInitialize(void) {
    @autoreleasepool{static int commandToken,reloadToken;notify_register_dispatch(ABCommandNotification.UTF8String,&commandToken,dispatch_get_main_queue(),^(__unused int token){ABHandleCommand();});notify_register_dispatch(ABReloadNotification.UTF8String,&reloadToken,dispatch_get_main_queue(),^(__unused int token){ABOptions=ABSettings();});dispatch_after(dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC),dispatch_get_main_queue(),^{ABStart(0);});}
}
