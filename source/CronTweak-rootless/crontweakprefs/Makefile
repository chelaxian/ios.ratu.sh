export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:16.5:14.0
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CronTweakPrefs
CronTweakPrefs_FILES = CronTweakListController.m
CronTweakPrefs_INSTALL_PATH = /Library/PreferenceBundles
CronTweakPrefs_FRAMEWORKS = UIKit WebKit
CronTweakPrefs_PRIVATE_FRAMEWORKS = Preferences
CronTweakPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceBundles/CronTweakPrefs.bundle$(ECHO_END)
	$(ECHO_NOTHING)cp -R Resources/Info.plist Resources/icon.png Resources/icon@2x.png Resources/icon@3x.png $(THEOS_STAGING_DIR)/Library/PreferenceBundles/CronTweakPrefs.bundle/$(ECHO_END)
	$(ECHO_NOTHING)chmod 0644 $(THEOS_STAGING_DIR)/Library/PreferenceBundles/CronTweakPrefs.bundle/Info.plist $(THEOS_STAGING_DIR)/Library/PreferenceBundles/CronTweakPrefs.bundle/icon*.png$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp Resources/entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CronTweak.plist$(ECHO_END)
	$(ECHO_NOTHING)chmod 0644 $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CronTweak.plist$(ECHO_END)
