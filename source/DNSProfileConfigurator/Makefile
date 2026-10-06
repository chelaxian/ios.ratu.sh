export THEOS_PACKAGE_SCHEME = rootless
ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = DNSProfileConfiguratorPrefs
DNSProfileConfiguratorPrefs_FILES = DPCRootListController.m
DNSProfileConfiguratorPrefs_INSTALL_PATH = /Library/PreferenceBundles
DNSProfileConfiguratorPrefs_FRAMEWORKS = UIKit
DNSProfileConfiguratorPrefs_PRIVATE_FRAMEWORKS = Preferences
DNSProfileConfiguratorPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
