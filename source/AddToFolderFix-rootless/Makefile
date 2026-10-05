THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk
TWEAK_NAME = AddToFolderFix
AddToFolderFix_FILES = AddToFolderFix.m
AddToFolderFix_CFLAGS = -fobjc-arc -Wall -Wextra
AddToFolderFix_FRAMEWORKS = UIKit Foundation CoreFoundation
AddToFolderFix_LIBRARIES = substrate
include $(THEOS_MAKE_PATH)/tweak.mk
