export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = CCOpenSSH
CCOpenSSH_FILES = Module.m
CCOpenSSH_INFO_PLIST = Info.plist
CCOpenSSH_FRAMEWORKS = UIKit Foundation
CCOpenSSH_PRIVATE_FRAMEWORKS = ControlCenterUIKit
CCOpenSSH_CFLAGS = -fobjc-arc -I../CCServiceCommon
CCOpenSSH_INSTALL_PATH = /Library/ControlCenter/Bundles
include $(THEOS_MAKE_PATH)/bundle.mk
TOOL_NAME = ccopenssh
ccopenssh_FILES = Helper.m
ccopenssh_FRAMEWORKS = Foundation
ccopenssh_CFLAGS = -fobjc-arc -Wno-unused-function
ccopenssh_CODESIGN_FLAGS = -SToolEntitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk
