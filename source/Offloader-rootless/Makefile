export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = Offloader OffloaderGuard
Offloader_FILES = OFSpringBoard.m OFBridge.m
Offloader_FRAMEWORKS = Foundation UIKit CoreServices
Offloader_CFLAGS = -fobjc-arc -Wno-unused-function
OffloaderGuard_FILES = OFGuard.m
OffloaderGuard_FRAMEWORKS = Foundation
OffloaderGuard_CFLAGS = -fobjc-arc -Wno-unused-function
include $(THEOS_MAKE_PATH)/tweak.mk
BUNDLE_NAME = OffloaderPrefs
OffloaderPrefs_FILES = Preferences/OFPreferences.m
OffloaderPrefs_FRAMEWORKS = Foundation UIKit CoreServices
OffloaderPrefs_PRIVATE_FRAMEWORKS = Preferences
OffloaderPrefs_CFLAGS = -fobjc-arc -Wno-unused-function
OffloaderPrefs_INSTALL_PATH = /Library/PreferenceBundles
OffloaderPrefs_RESOURCE_DIRS = Preferences/Resources
include $(THEOS_MAKE_PATH)/bundle.mk
