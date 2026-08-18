export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = CCHPPE
CCHPPE_BUNDLE_EXTENSION = bundle
CCHPPE_FILES = CCHPPEToggle.m
CCHPPE_CFLAGS = -fobjc-arc
CCHPPE_FRAMEWORKS = UIKit
CCHPPE_PRIVATE_FRAMEWORKS = ControlCenterUIKit
CCHPPE_INSTALL_PATH = /Library/ControlCenter/Bundles/

include $(THEOS_MAKE_PATH)/bundle.mk
