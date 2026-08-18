export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = jetsamfixd jetsamfix

jetsamfixd_FILES = jetsamfixd.c jf_core.c
jetsamfixd_CFLAGS = -fobjc-arc -Wall -Wextra -O2
jetsamfixd_FRAMEWORKS = CoreFoundation
jetsamfixd_CODESIGN_FLAGS = -Sentitlements.plist

jetsamfix_FILES = jetsamfix.c jf_core.c
jetsamfix_CFLAGS = -fobjc-arc -Wall -Wextra -O2
jetsamfix_FRAMEWORKS = CoreFoundation
jetsamfix_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/tool.mk

# Stage the LaunchDaemon, the default-config template, and mark the
# maintainer scripts executable so dpkg runs them.
internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/LaunchDaemons"$(ECHO_END)
	$(ECHO_NOTHING)cp com.ratush.jetsamfixd.plist "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/usr/share/jetsamfix"$(ECHO_END)
	$(ECHO_NOTHING)cp com.ratush.jetsamfix.plist "$(THEOS_STAGING_DIR)/usr/share/jetsamfix/default-config.plist"$(ECHO_END)
