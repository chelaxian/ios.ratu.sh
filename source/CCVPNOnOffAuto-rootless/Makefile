TARGET := iphone:clang:latest:14.0
THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e

BUNDLE_NAME = CCVPNOnOffAuto
TOOL_NAME = ccvpnd

# ---- CC tile bundle (no entitlement) ----
CCVPNOnOffAuto_FILES = CCVPNOnOffAutoModule.m
CCVPNOnOffAuto_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable
CCVPNOnOffAuto_PRIVATE_FRAMEWORKS = ControlCenterUIKit ControlCenterUI ControlCenterServices
CCVPNOnOffAuto_FRAMEWORKS = UIKit Foundation
CCVPNOnOffAuto_INSTALL_PATH = /Library/ControlCenter/Bundles
CCVPNOnOffAuto_BUNDLE_RESOURCES = Info.plist SettingsIcon.png SettingsIcon@2x.png SettingsIcon@3x.png

# ---- privileged daemon ----
ccvpnd_FILES = ccvpnd.m
ccvpnd_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-function -Wno-unused-variable
ccvpnd_FRAMEWORKS = Foundation

include $(THEOS)/makefiles/common.mk
include $(THEOS_MAKE_PATH)/bundle.mk
include $(THEOS_MAKE_PATH)/tool.mk

ccvpnd_CODESIGN_FLAGS = -Sccvpnd.ent.plist
