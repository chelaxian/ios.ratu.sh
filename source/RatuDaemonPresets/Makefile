THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
include $(THEOS)/makefiles/common.mk
TOOL_NAME = ratu-daemonpresetsd
ratu-daemonpresetsd_FILES = daemon.m
ratu-daemonpresetsd_ARCHS = arm64
ratu-daemonpresetsd_CFLAGS = -fobjc-arc
ratu-daemonpresetsd_FRAMEWORKS = Foundation
ratu-daemonpresetsd_CODESIGN_FLAGS = -Sentitlements.plist
ratu-daemonpresetsd_INSTALL_PATH = /usr/libexec
BUNDLE_NAME = RatuDaemonPrefs RatuDaemonCC
RatuDaemonPrefs_FILES = Prefs.m
RatuDaemonPrefs_CFLAGS = -fobjc-arc
RatuDaemonPrefs_FRAMEWORKS = Foundation UIKit UniformTypeIdentifiers
RatuDaemonPrefs_PRIVATE_FRAMEWORKS = Preferences
RatuDaemonPrefs_INSTALL_PATH = /Library/PreferenceBundles
RatuDaemonPrefs_RESOURCE_DIRS = prefs-resources
RatuDaemonCC_FILES = Module.m
RatuDaemonCC_CFLAGS = -fobjc-arc
RatuDaemonCC_FRAMEWORKS = Foundation UIKit QuartzCore
RatuDaemonCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit
RatuDaemonCC_INSTALL_PATH = /Library/ControlCenter/Bundles
RatuDaemonCC_RESOURCE_DIRS = cc-resources
include $(THEOS_MAKE_PATH)/tool.mk
include $(THEOS_MAKE_PATH)/bundle.mk
before-package::
	mkdir -p $(THEOS_STAGING_DIR)/usr/share/ratu-daemon-presets
	cp catalog.plist $(THEOS_STAGING_DIR)/usr/share/ratu-daemon-presets/catalog.plist
	chmod -R go-w $(THEOS_STAGING_DIR)
	find $(THEOS_STAGING_DIR) -type d -exec chmod 755 {} \;
	find $(THEOS_STAGING_DIR) -name '*.plist' -exec chmod 644 {} \;
