export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

# Injected into mDNSResponder only (see EtcHosts17.plist).
TWEAK_NAME = EtcHosts17
EtcHosts17_FILES = Tweak.x

BUNDLE_NAME = EtcHosts17Prefs
EtcHosts17Prefs_FILES = EtcHosts17RootListController.m
EtcHosts17Prefs_INSTALL_PATH = /Library/PreferenceBundles
EtcHosts17Prefs_FRAMEWORKS = UIKit
EtcHosts17Prefs_PRIVATE_FRAMEWORKS = Preferences
EtcHosts17Prefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/bundle.mk
