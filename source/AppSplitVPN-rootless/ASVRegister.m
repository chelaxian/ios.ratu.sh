#import <Foundation/Foundation.h>
#import <sys/stat.h>
#import <unistd.h>
int main(int argc,char **argv) { @autoreleasepool {
    BOOL removing=argc>1 && strcmp(argv[1],"remove")==0;
    NSString *identifier=@"com.ratush.appsplitvpn.ccmodule";
    NSArray *paths=@[@"/var/jb/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist",
                     @"/var/mobile/Library/ControlCenter/ModuleConfiguration_CCSupport.plist"];
    for (NSString *path in paths) {
        NSMutableDictionary *configuration=[[NSDictionary dictionaryWithContentsOfFile:path] mutableCopy];
        if (!configuration) continue;
        NSMutableArray *modules=[configuration[@"module-identifiers"] mutableCopy];
        if (!modules) continue;
        BOOL exists=[modules containsObject:identifier];
        if (exists==!removing) continue;
        NSString *backup=[path stringByAppendingFormat:@".appsplitvpn.%ld.bak",(long)[NSDate date].timeIntervalSince1970];
        if (![[NSFileManager defaultManager] copyItemAtPath:path toPath:backup error:nil]) continue;
        if (removing) [modules removeObject:identifier]; else [modules addObject:identifier];
        configuration[@"module-identifiers"]=modules;
        if ([configuration writeToFile:path atomically:YES]) {
            chown(path.fileSystemRepresentation,501,501);
            chmod(path.fileSystemRepresentation,0644);
        } else {
            [[NSFileManager defaultManager] copyItemAtPath:backup toPath:path error:nil];
        }
    }
} return 0; }
