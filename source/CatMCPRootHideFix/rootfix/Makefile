TARGET := iphone:clang:latest:14.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

LIBRARY_NAME := catmcp-rootfix
catmcp-rootfix_FILES := catmcp-rootfix.c fishhook.c
catmcp-rootfix_CFLAGS := -O2 -Wall -Wextra
catmcp-rootfix_INSTALL_PATH := /usr/lib

include $(THEOS_MAKE_PATH)/library.mk
