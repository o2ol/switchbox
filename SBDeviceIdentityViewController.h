#import <UIKit/UIKit.h>
#import "SBContainerManager.h"

NS_ASSUME_NONNULL_BEGIN

@interface SBDeviceIdentityViewController : UITableViewController
- (instancetype)initWithApp:(SBAppInfo *)app profile:(SBProfileInfo *)profile;
@end

NS_ASSUME_NONNULL_END
