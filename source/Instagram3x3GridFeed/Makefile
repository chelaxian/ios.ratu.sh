export THEOS_PACKAGE_SCHEME = roothide
TARGET := iphone:clang:16.5:14.0
ARCHS = arm64e
INSTALL_TARGET_PROCESSES = Instagram

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = IGGridFeed

IGGridFeed_FILES = Tweak.x
IGGridFeed_FRAMEWORKS = UIKit Foundation CoreGraphics
IGGridFeed_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
IGGridFeed_LDFLAGS = -Wl,-install_name,/Library/MobileSubstrate/DynamicLibraries/IGGridFeed.dylib

include $(THEOS_MAKE_PATH)/tweak.mk
