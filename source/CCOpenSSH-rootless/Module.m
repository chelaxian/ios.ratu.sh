#define SERVICE_KIND 1
#define SERVICE_LABEL "com.openssh.sshd"
#define SERVICE_NOTIFICATION "com.ratush.ccopenssh.state"
#define SERVICE_CLASS CCSSHModule
#define SERVICE_NAME @"CCSSH"
#define SERVICE_TEXT @"SSH"
#define SERVICE_TEXT_COLOR UIColor.whiteColor
#define SERVICE_COLOR [UIColor colorWithRed:.15 green:.5 blue:.9 alpha:1]
#define SERVICE_HELPER "/var/jb/usr/bin/ccopenssh"
#import "../CCServiceCommon/CCServiceModule.m"
