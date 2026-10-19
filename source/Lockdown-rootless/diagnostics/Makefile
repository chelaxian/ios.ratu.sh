TARGET := iphone:clang:latest:17.0
ARCHS = arm64
THEOS_PACKAGE_SCHEME = rootless
include $(THEOS)/makefiles/common.mk
TOOL_NAME = lockdown-jsc-probe
lockdown-jsc-probe_FILES = main.c
lockdown-jsc-probe_FRAMEWORKS = JavaScriptCore
lockdown-jsc-probe_CFLAGS = -Wall -Wextra
include $(THEOS_MAKE_PATH)/tool.mk
