export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = safeguardd safeguard

safeguardd_FILES = safeguardd.c sg_core.c
safeguardd_CFLAGS = -Wall -Wextra -O2
safeguardd_CODESIGN_FLAGS = -Sentitlements.plist

safeguard_FILES = safeguard.c sg_core.c
safeguard_CFLAGS = -Wall -Wextra -O2
safeguard_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/tool.mk

# Stage the LaunchDaemon and the default-config template (documentation /
# future override; the daemon uses built-in defaults because of the
# data-container namespace isolation).
internal-stage::
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/Library/LaunchDaemons"$(ECHO_END)
	$(ECHO_NOTHING)cp com.ratush.safeguardd.plist "$(THEOS_STAGING_DIR)/Library/LaunchDaemons/"$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p "$(THEOS_STAGING_DIR)/usr/share/safeguard"$(ECHO_END)
	$(ECHO_NOTHING)cp com.ratush.safeguard.plist "$(THEOS_STAGING_DIR)/usr/share/safeguard/default-config.plist"$(ECHO_END)
