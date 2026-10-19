#define SERVICE_KIND 2
#define SERVICE_LABEL "re.frida.server"
#define SERVICE_NOTIFICATION "com.ratush.ccfrida.state"
#define SERVICE_CLASS CCFRIDAModule
#define SERVICE_NAME @"CCFRIDA"
#define SERVICE_TEXT @"FRIDA"
#define SERVICE_ACTIVE_TEXT_COLOR UIColor.systemRedColor
#define SERVICE_HELPER "/var/jb/usr/bin/ccfrida"
#import "../CCServiceCommon/CCServiceModule.m"
