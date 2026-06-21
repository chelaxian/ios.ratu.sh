export THEOS_PACKAGE_SCHEME ?= roothide
export THEOS ?= /home/chelaxian/theos
export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e
export DEBUG = 0

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME = catmcp-touch-bridge
catmcp-touch-bridge_FILES = CatMCPBridge.c fishhook.c
catmcp-touch-bridge_CFLAGS = -fno-objc-arc -Wall -Wextra
catmcp-touch-bridge_LIBRARIES = substrate
catmcp-touch-bridge_INSTALL_PATH = /usr/lib

TWEAK_NAME = CatMCPSpringBoardTouchBridge
CatMCPSpringBoardTouchBridge_FILES = SpringBoardBridge.m
CatMCPSpringBoardTouchBridge_CFLAGS = -fobjc-arc -Wall -Wextra -Wno-deprecated-declarations
CatMCPSpringBoardTouchBridge_FRAMEWORKS = Foundation CoreFoundation IOKit CoreGraphics

TOOL_NAME = catmcp-inject catmcp-autoinjectd

catmcp-inject_FILES = CatMCPInject.m opainject/dyld.m opainject/shellcode_inject.m opainject/rop_inject.m opainject/thread_utils.m opainject/task_utils.m opainject/arm64.m
catmcp-inject_CFLAGS = -fobjc-arc -DTHEOS_LEAN_AND_MEAN -Iopainject
catmcp-inject_INSTALL_PATH = /usr/libexec
catmcp-inject_CODESIGN_FLAGS = -Sentitlements.plist
catmcp-inject_PRIVATE_FRAMEWORKS = CoreSymbolication

catmcp-autoinjectd_FILES = CatMCPAutoInjectDaemon.c
catmcp-autoinjectd_CFLAGS = -fno-objc-arc -Wall -Wextra
catmcp-autoinjectd_INSTALL_PATH = /usr/libexec
catmcp-autoinjectd_CODESIGN_FLAGS = -Sentitlements.plist
catmcp-autoinjectd_FRAMEWORKS = CoreFoundation

include $(THEOS_MAKE_PATH)/library.mk
include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/tool.mk

internal-stage::
ifeq ($(THEOS_PACKAGE_SCHEME),roothide)
	$(ECHO_NOTHING)ln -sf /usr/lib/DynamicPatches/AutoPatches.dylib $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/CatMCPSpringBoardTouchBridge.dylib.roothidepatch$(ECHO_END)
	$(ECHO_NOTHING)ln -sf /usr/lib/DynamicPatches/AutoPatches.dylib $(THEOS_STAGING_DIR)/Library/MobileSubstrate/DynamicLibraries/catmcp.dylib.roothidepatch$(ECHO_END)
endif
