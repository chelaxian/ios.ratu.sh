TARGET := iphone:clang:16.5:14.0
ARCHS = arm64
INSTALL_TARGET_PROCESSES = Instagram
include $(THEOS)/makefiles/common.mk
TWEAK_NAME = IGGridFeed
IGGridFeed_FILES = Tweak.x
IGGridFeed_FRAMEWORKS = Foundation
IGGridFeed_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function
include $(THEOS_MAKE_PATH)/tweak.mk
