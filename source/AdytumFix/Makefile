export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = AdytumFix
AdytumFix_FILES = Tweak.m
AdytumFix_FRAMEWORKS = Foundation UIKit
AdytumFix_CFLAGS = -fno-objc-arc -Wno-unused-function
include $(THEOS_MAKE_PATH)/tweak.mk
