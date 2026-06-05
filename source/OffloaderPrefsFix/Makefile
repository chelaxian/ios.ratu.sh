TARGET := iphone:clang:17.0:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = Preferences

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = OffloaderPrefs

OffloaderPrefs_FILES = OffloaderPrefs.m
OffloaderPrefs_PRIVATE_FRAMEWORKS = Preferences
OffloaderPrefs_FRAMEWORKS = Foundation UIKit
OffloaderPrefs_CFLAGS = -fobjc-arc -I$(THEOS_PROJECT_DIR)/vendor/AltList.framework/Headers
OffloaderPrefs_LDFLAGS = -F$(THEOS_PROJECT_DIR)/vendor -framework AltList
OffloaderPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
