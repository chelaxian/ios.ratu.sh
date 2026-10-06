export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = EtcHosts17
EtcHosts17_FILES = Tweak.x
EtcHosts17_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
