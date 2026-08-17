ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = CCGapCloser
CCGapCloser_FILES = Tweak.x
CCGapCloser_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
CCGapCloser_FRAMEWORKS = UIKit Foundation CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk

BUNDLE_NAME = CCGapCloserPrefs
CCGapCloserPrefs_FILES = CCGapCloserPrefs/CCGRootListController.m
CCGapCloserPrefs_CFLAGS = -fobjc-arc
CCGapCloserPrefs_FRAMEWORKS = UIKit
# Preferences classes are resolved by the iOS runtime; the macOS SDK has no
# link stub for this private framework.
CCGapCloserPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/CCGapCloserPrefs.bundle"$(ECHO_END)
	$(ECHO_NOTHING)cp CCGapCloserPrefs/Resources/Info.plist "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/CCGapCloserPrefs.bundle/Info.plist"$(ECHO_END)
	$(ECHO_NOTHING)cp CCGapCloserPrefs/Resources/icon.png "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/CCGapCloserPrefs.bundle/icon.png"$(ECHO_END)
	$(ECHO_NOTHING)cp CCGapCloserPrefs/Resources/icon@2x.png "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/CCGapCloserPrefs.bundle/icon@2x.png"$(ECHO_END)
	$(ECHO_NOTHING)cp CCGapCloserPrefs/Resources/icon@3x.png "$(THEOS_STAGING_DIR)/Library/PreferenceBundles/CCGapCloserPrefs.bundle/icon@3x.png"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences"$(ECHO_END)
	$(ECHO_NOTHING)cp CCGapCloserPrefs/entry.plist "$(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/CCGapCloserPrefs.plist"$(ECHO_END)
