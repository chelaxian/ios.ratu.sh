TARGET := iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

TOOL_NAME = appsplitvpnd
appsplitvpnd_FILES = appsplitvpnd.m PolicyEngine.m
appsplitvpnd_ARCHS = arm64
appsplitvpnd_CFLAGS = -fobjc-arc -Wall -Wextra
appsplitvpnd_FRAMEWORKS = Foundation
appsplitvpnd_CODESIGN_FLAGS = -Cadhoc -Sentitlements.plist
appsplitvpnd_INSTALL_PATH = /usr/libexec

BUNDLE_NAME = AppSplitVPNPrefs
AppSplitVPNPrefs_FILES = ASVRootController.m
AppSplitVPNPrefs_CFLAGS = -fobjc-arc -Wall -Wextra
AppSplitVPNPrefs_FRAMEWORKS = UIKit Foundation
AppSplitVPNPrefs_PRIVATE_FRAMEWORKS = Preferences
AppSplitVPNPrefs_CODESIGN_FLAGS = -Cadhoc -S
AppSplitVPNPrefs_INSTALL_PATH = /Library/PreferenceBundles
AppSplitVPNPrefs_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/bundle.mk
