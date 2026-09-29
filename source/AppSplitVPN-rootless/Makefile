TARGET := iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk

TOOL_NAME = appsplitvpnd appsplitvpn-register
appsplitvpnd_FILES = appsplitvpnd.m PolicyEngine.m
appsplitvpnd_ARCHS = arm64
appsplitvpnd_CFLAGS = -fobjc-arc -Wall -Wextra
appsplitvpnd_FRAMEWORKS = Foundation
appsplitvpnd_CODESIGN_FLAGS = -Cadhoc -Sentitlements.plist
appsplitvpnd_INSTALL_PATH = /usr/libexec
appsplitvpn-register_FILES = ASVRegister.m
appsplitvpn-register_ARCHS = arm64
appsplitvpn-register_CFLAGS = -fobjc-arc -Wall -Wextra
appsplitvpn-register_FRAMEWORKS = Foundation
appsplitvpn-register_CODESIGN_FLAGS = -Cadhoc -S
appsplitvpn-register_INSTALL_PATH = /usr/libexec

BUNDLE_NAME = AppSplitVPNPrefs
AppSplitVPNPrefs_FILES = ASVRootController.m ASVAppListController.m
AppSplitVPNPrefs_CFLAGS = -fobjc-arc -Wall -Wextra
AppSplitVPNPrefs_FRAMEWORKS = UIKit Foundation UniformTypeIdentifiers
AppSplitVPNPrefs_PRIVATE_FRAMEWORKS = Preferences
AppSplitVPNPrefs_CODESIGN_FLAGS = -Cadhoc -S
AppSplitVPNPrefs_INSTALL_PATH = /Library/PreferenceBundles
AppSplitVPNPrefs_RESOURCE_DIRS = Resources

BUNDLE_NAME += AppSplitVPNCC
AppSplitVPNCC_FILES = ASVCCModule.m
AppSplitVPNCC_CFLAGS = -fobjc-arc -Wall -Wextra
AppSplitVPNCC_FRAMEWORKS = UIKit Foundation
AppSplitVPNCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit
AppSplitVPNCC_CODESIGN_FLAGS = -Cadhoc -S
AppSplitVPNCC_INSTALL_PATH = /Library/ControlCenter/Bundles
AppSplitVPNCC_RESOURCE_DIRS = CCResources

TWEAK_NAME = AppSplitVPNStatusBar
AppSplitVPNStatusBar_FILES = StatusBar.x
AppSplitVPNStatusBar_CFLAGS = -fobjc-arc
AppSplitVPNStatusBar_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/tweak.mk
