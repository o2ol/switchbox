export THEOS ?= /Users/macmini/work/theos
ARCHS = arm64
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SwitchBox

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = SwitchBox

SwitchBox_FILES = main.m SBAppDelegate.m SBRootViewController.m SBProfilesViewController.m SBContainerManager.m SBHelpViewController.m SBSettingsViewController.m SBCopyUtil.m SBSchemeViewController.m SBVersionViewController.m SBAboutViewController.m SBPathsViewController.m SBDeviceIdentityViewController.m
SwitchBox_FRAMEWORKS = UIKit Foundation CoreGraphics CoreServices Security
SwitchBox_PRIVATE_FRAMEWORKS = MobileCoreServices
SwitchBox_CFLAGS = -fobjc-arc -Wno-unused-variable -Wno-deprecated-declarations -Wno-objc-method-access
SwitchBox_CODESIGN_FLAGS = -Sentitlements.plist
SwitchBox_INSTALL_PATH = /Applications

include $(THEOS_MAKE_PATH)/application.mk
