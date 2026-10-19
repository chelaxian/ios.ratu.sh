#define SERVICE_KIND 1
#define SERVICE_LABEL "com.openssh.sshd"
#define SERVICE_NOTIFICATION "com.ratush.ccopenssh.state"
#define SERVICE_CLASS CCSSHModule
#define SERVICE_NAME @"CCSSH"
#define SERVICE_TEXT @"SSH"
#define SERVICE_ACTIVE_TEXT_COLOR UIColor.systemOrangeColor
#define SERVICE_HELPER "/var/jb/usr/bin/ccopenssh"
#import "../CCServiceCommon/CCServiceModule.m"
