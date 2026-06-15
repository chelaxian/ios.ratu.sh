TARGET := iphone:clang:16.5:15.0
ARCHS ?= arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AOffloaderVanillaCapture

AOffloaderVanillaCapture_FILES = Tweak.m
AOffloaderVanillaCapture_FRAMEWORKS = Foundation UIKit
AOffloaderVanillaCapture_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
