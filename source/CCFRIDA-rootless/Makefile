export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = CCFRIDA
CCFRIDA_FILES = Module.m
CCFRIDA_INFO_PLIST = Info.plist
CCFRIDA_FRAMEWORKS = UIKit Foundation
CCFRIDA_PRIVATE_FRAMEWORKS = ControlCenterUIKit
CCFRIDA_CFLAGS = -fobjc-arc -I../CCServiceCommon
CCFRIDA_INSTALL_PATH = /Library/ControlCenter/Bundles
include $(THEOS_MAKE_PATH)/bundle.mk
TOOL_NAME = ccfrida
ccfrida_FILES = Helper.m
ccfrida_FRAMEWORKS = Foundation
ccfrida_CFLAGS = -fobjc-arc -Wno-unused-function
ccfrida_CODESIGN_FLAGS = -SToolEntitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk
