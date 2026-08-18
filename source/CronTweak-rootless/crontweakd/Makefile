export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
include $(THEOS)/makefiles/common.mk

.PHONY: clean
clean::
	$(ECHO_NOTHING)rm -rf $(THEOS_OBJ_DIR)$(ECHO_END)

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/usr/libexec$(ECHO_END)
	$(ECHO_NOTHING)cp crontweakd.py $(THEOS_STAGING_DIR)/usr/libexec/crontweakd.py$(ECHO_END)
	$(ECHO_NOTHING)chmod 0755 $(THEOS_STAGING_DIR)/usr/libexec/crontweakd.py$(ECHO_END)
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/LaunchDaemons$(ECHO_END)
	$(ECHO_NOTHING)cp com.ratush.crontweakd.plist $(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.ratush.crontweakd.plist$(ECHO_END)
	$(ECHO_NOTHING)chmod 0644 $(THEOS_STAGING_DIR)/Library/LaunchDaemons/com.ratush.crontweakd.plist$(ECHO_END)
