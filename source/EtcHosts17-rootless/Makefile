export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = etchosts17ctl etchosts17dns etchosts17resolv
etchosts17ctl_FILES = EtcHosts17Ctl.c
etchosts17ctl_INSTALL_PATH = /usr/libexec

etchosts17dns_FILES = EtcHosts17DNS.m
etchosts17dns_INSTALL_PATH = /usr/libexec
etchosts17dns_FRAMEWORKS = Foundation NetworkExtension CoreFoundation
etchosts17dns_CFLAGS = -fobjc-arc
etchosts17dns_CODESIGN_FLAGS = -Sdns-entitlements.plist

etchosts17resolv_FILES = EtcHosts17Resolv.m
etchosts17resolv_INSTALL_PATH = /usr/libexec
etchosts17resolv_FRAMEWORKS = Foundation SystemConfiguration CoreFoundation
etchosts17resolv_CFLAGS = -fobjc-arc
etchosts17resolv_CODESIGN_FLAGS = -Sresolv-entitlements.plist

BUNDLE_NAME = EtcHosts17Prefs
EtcHosts17Prefs_FILES = EtcHosts17RootListController.m
EtcHosts17Prefs_INSTALL_PATH = /Library/PreferenceBundles
EtcHosts17Prefs_FRAMEWORKS = UIKit
EtcHosts17Prefs_PRIVATE_FRAMEWORKS = Preferences
EtcHosts17Prefs_CFLAGS = -fobjc-arc -DPACKAGE_VERSION='@"$(THEOS_PACKAGE_BASE_VERSION)"'

include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceBundles/EtcHosts17Prefs.bundle$(ECHO_END)
	$(ECHO_NOTHING)cp -R Resources/* $(THEOS_STAGING_DIR)/Library/PreferenceBundles/EtcHosts17Prefs.bundle/$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp layout/Library/PreferenceLoader/Preferences/EtcHosts17.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/EtcHosts17.plist$(ECHO_END)
	$(ECHO_NOTHING)cp layout/Library/PreferenceLoader/Preferences/EtcHosts17.png $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/EtcHosts17.png$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons$(ECHO_END)
	$(ECHO_NOTHING)cp layout/Library/LaunchDaemons/com.ratush.etchosts17d.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.ratush.etchosts17d.plist$(ECHO_END)
	$(ECHO_NOTHING)cp layout/Library/LaunchDaemons/com.ratush.etchosts17resolv.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.ratush.etchosts17resolv.plist$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/usr/libexec$(ECHO_END)
	$(ECHO_NOTHING)cp scripts/etchosts17.py $(THEOS_STAGING_DIR)/usr/libexec/etchosts17.py$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 $(THEOS_STAGING_DIR)/usr/libexec/etchosts17.py$(ECHO_END)
