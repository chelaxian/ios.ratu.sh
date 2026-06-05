TARGET := iphone:clang:16.5:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = OffloaderAntiOffloadFix

OffloaderAntiOffloadFix_FILES = Tweak.xm
OffloaderAntiOffloadFix_FRAMEWORKS = Foundation
OffloaderAntiOffloadFix_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
