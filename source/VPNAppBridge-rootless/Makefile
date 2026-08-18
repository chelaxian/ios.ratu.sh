export THEOS_PACKAGE_SCHEME ?= roothide
export THEOS ?= /opt/theos
export TARGET = iphone:clang:16.5:15.0
export ARCHS = arm64 arm64e
export DEBUG = 0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RatuVPNBridge
RatuVPNBridge_FILES = Tweak.m
RatuVPNBridge_CFLAGS = -fobjc-arc -fno-modules -Wall -Wextra -Wno-deprecated-declarations
RatuVPNBridge_FRAMEWORKS = Foundation CoreFoundation UIKit QuartzCore
RatuVPNBridge_LIBRARIES =
RatuVPNBridge_LDFLAGS = -Wl,-init,_AVFStart
RatuVPNBridge_USE_MODULES = 0

TOOL_NAME = ratuvpnctl ratuvpnd
ratuvpnctl_FILES = autovpnctl.m
ratuvpnctl_CFLAGS = -fobjc-arc -fno-modules -Wall -Wextra -Wno-deprecated-declarations
ratuvpnctl_FRAMEWORKS = Foundation CoreFoundation
ratuvpnctl_CODESIGN_FLAGS = -Sentitlements.plist
ratuvpnctl_INSTALL_PATH = /usr/bin
ratuvpnctl_USE_MODULES = 0

ratuvpnd_FILES = autovpnd.m
ratuvpnd_CFLAGS = -fobjc-arc -fno-modules -Wall -Wextra -Wno-deprecated-declarations
ratuvpnd_FRAMEWORKS = Foundation CoreFoundation
ratuvpnd_CODESIGN_FLAGS = -Sentitlements.plist
ratuvpnd_INSTALL_PATH = /usr/bin
ratuvpnd_USE_MODULES = 0

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
	$(ECHO_NOTHING)ln -sf /usr/lib/DynamicPatches/AutoPatches.dylib $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/RatuVPNBridge.dylib.roothidepatch$(ECHO_END)
endif
