#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

FOUNDATION_EXPORT NSString * const SBSettingAutoOpenAfterSwitch;
FOUNDATION_EXPORT NSString * const SBSettingConfirmBeforeSwitch;
FOUNDATION_EXPORT NSString * const SBSettingSkipCaches;
/// @"system" | @"light" | @"dark"
FOUNDATION_EXPORT NSString * const SBSettingAppearance;

FOUNDATION_EXPORT NSUserDefaults *SBSettingsDefaults(void);
FOUNDATION_EXPORT BOOL SBSettingsBool(NSString *key);
FOUNDATION_EXPORT NSString *SBSettingsString(NSString *key);
FOUNDATION_EXPORT void SBApplyAppearance(void);
