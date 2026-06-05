TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OffloaderRuntimeFix

OffloaderRuntimeFix_FILES = Tweak.xm
OffloaderRuntimeFix_FRAMEWORKS = Foundation UIKit
OffloaderRuntimeFix_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
