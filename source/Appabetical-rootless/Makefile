export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

PROJECT = Appabetical

TWEAK_NAME = Appabetical
Appabetical_FILES = Tweak.x
Appabetical_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
Appabetical_FRAMEWORKS = Foundation CoreServices

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = AppabeticalPrefs
AppabeticalPrefs_FILES = AppabeticalPrefs/ABPRootListController.m
AppabeticalPrefs_CFLAGS = -fobjc-arc
AppabeticalPrefs_FRAMEWORKS = UIKit
AppabeticalPrefs_PRIVATE_FRAMEWORKS = Preferences
AppabeticalPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/AppabeticalPrefs.bundle"$(ECHO_END)
	$(ECHO_NOTHING)cp AppabeticalPrefs/Resources/Info.plist "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/AppabeticalPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)cp AppabeticalPrefs/Resources/icon.png "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/AppabeticalPrefs.bundle/icon.png"$(ECHO_END)
	$(ECHO_NOTHING)cp AppabeticalPrefs/Resources/icon@2x.png "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/AppabeticalPrefs.bundle/icon@2x.png"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/AppabeticalPrefs.bundle/en.lproj"$(ECHO_END)
	$(ECHO_NOTHING)cp AppabeticalPrefs/Resources/en.lproj/Localizable.strings "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/AppabeticalPrefs.bundle/en.lproj/Localizable.strings"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/AppabeticalPrefs.bundle/ru.lproj"$(ECHO_END)
	$(ECHO_NOTHING)cp AppabeticalPrefs/Resources/ru.lproj/Localizable.strings "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/AppabeticalPrefs.bundle/ru.lproj/Localizable.strings"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp AppabeticalPrefs/entry.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/AppabeticalPrefs.plist"$(ECHO_END)
