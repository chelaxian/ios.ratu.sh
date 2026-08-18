export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
include $(THEOS)/makefiles/common.mk

SUBPROJECTS = crontweakd crontweakprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
