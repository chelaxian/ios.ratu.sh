export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
include $(THEOS)/makefiles/common.mk
BUNDLE_NAME = CatMCPCC
CatMCPCC_FILES = Module.m
CatMCPCC_INFO_PLIST = Info.plist
CatMCPCC_FRAMEWORKS = UIKit Foundation
CatMCPCC_PRIVATE_FRAMEWORKS = ControlCenterUIKit
CatMCPCC_CFLAGS = -fobjc-arc -I../CCServiceCommon
CatMCPCC_INSTALL_PATH = /Library/ControlCenter/Bundles
include $(THEOS_MAKE_PATH)/bundle.mk
TOOL_NAME = catmcpcchelper
catmcpcchelper_FILES = Helper.m
catmcpcchelper_FRAMEWORKS = Foundation
catmcpcchelper_CFLAGS = -fobjc-arc -Wno-unused-function
catmcpcchelper_CODESIGN_FLAGS = -SToolEntitlements.plist
include $(THEOS_MAKE_PATH)/tool.mk
