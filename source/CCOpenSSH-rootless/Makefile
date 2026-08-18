export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCOpenSSH
CCOpenSSH_FILES = CCOpenSSH.m
CCOpenSSH_INFO_PLIST = Info.plist
CCOpenSSH_FRAMEWORKS = UIKit Foundation
CCOpenSSH_PRIVATE_FRAMEWORKS = ControlCenterUIKit
CCOpenSSH_CFLAGS = -fobjc-arc
CCOpenSSH_INSTALL_PATH = /Library/ControlCenter/Bundles
CCOpenSSH_CODESIGN_FLAGS = -SEntitlements.plist
include $(THEOS_MAKE_PATH)/bundle.mk

BUNDLE_NAME += CCOpenSSHPrefs
CCOpenSSHPrefs_FILES = CCOpenSSHPrefs.m
CCOpenSSHPrefs_INFO_PLIST = PrefsInfo.plist
CCOpenSSHPrefs_FRAMEWORKS = UIKit Foundation
CCOpenSSHPrefs_PRIVATE_FRAMEWORKS = Preferences
CCOpenSSHPrefs_CFLAGS = -fobjc-arc
CCOpenSSHPrefs_INSTALL_PATH = /Library/PreferenceBundles
CCOpenSSHPrefs_CODESIGN_FLAGS = -SEntitlements.plist
include $(THEOS_MAKE_PATH)/bundle.mk

TOOL_NAME = ccopenssh
ccopenssh_FILES = ccopenssh.c
ccopenssh_FRAMEWORKS = CoreFoundation
ccopenssh_CFLAGS = -fobjc-arc
ccopenssh_CODESIGN_FLAGS = -SToolEntitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp entry.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CCOpenSSHPrefs.plist"$(ECHO_END)
