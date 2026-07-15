#import "SBAppDelegate.h"
#import "SBRootViewController.h"
#import "SBSettingsViewController.h"
#import "SBContainerManager.h"
#import "SBProfilesViewController.h"
#import "SBSettings.h"

@implementation SBAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
	// warm settings defaults
	(void)SBSettingsDefaults();

	self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

	SBRootViewController *apps = [[SBRootViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
	self.appsNav = [[UINavigationController alloc] initWithRootViewController:apps];
	self.appsNav.navigationBar.prefersLargeTitles = YES;
	self.appsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"应用"
															image:[UIImage systemImageNamed:@"square.grid.2x2.fill"]
															  tag:0];

	SBSettingsViewController *settings = [[SBSettingsViewController alloc] initWithStyle:UITableViewStyleInsetGrouped];
	self.settingsNav = [[UINavigationController alloc] initWithRootViewController:settings];
	self.settingsNav.navigationBar.prefersLargeTitles = YES;
	self.settingsNav.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"设置"
																image:[UIImage systemImageNamed:@"gearshape.fill"]
																  tag:1];

	self.tabBar = [[UITabBarController alloc] init];
	self.tabBar.viewControllers = @[self.appsNav, self.settingsNav];
	if (@available(iOS 15.0, *)) {
		UITabBarAppearance *app = [UITabBarAppearance new];
		[app configureWithDefaultBackground];
		self.tabBar.tabBar.standardAppearance = app;
		self.tabBar.tabBar.scrollEdgeAppearance = app;
	}

	self.window.rootViewController = self.tabBar;
	[self.window makeKeyAndVisible];
	SBApplyAppearance();

	// Navigation / Tab bar follow system dynamic colors (light & dark)
	if (@available(iOS 15.0, *)) {
		UINavigationBarAppearance *nav = [UINavigationBarAppearance new];
		[nav configureWithDefaultBackground];
		UINavigationBar.appearance.standardAppearance = nav;
		UINavigationBar.appearance.scrollEdgeAppearance = nav;
		UINavigationBar.appearance.compactAppearance = nav;
	}


	NSURL *url = launchOptions[UIApplicationLaunchOptionsURLKey];
	if (url) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[self handleURL:url];
		});
	}
	return YES;
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options {
	return [self handleURL:url];
}

- (UIViewController *)topPresenter {
	UIViewController *top = self.tabBar.selectedViewController;
	if ([top isKindOfClass:UINavigationController.class]) {
		top = ((UINavigationController *)top).visibleViewController;
	}
	while (top.presentedViewController) top = top.presentedViewController;
	return top ?: self.tabBar;
}

- (BOOL)handleURL:(NSURL *)url {
	if (!url) return NO;
	NSString *scheme = url.scheme.lowercaseString;
	if (![scheme isEqualToString:@"switchbox"]) return NO;

	NSURLComponents *c = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
	NSMutableDictionary *q = [NSMutableDictionary dictionary];
	for (NSURLQueryItem *item in c.queryItems) {
		if (item.name && item.value) q[item.name] = item.value;
	}
	NSString *host = (url.host ?: @"").lowercaseString;
	NSString *bundle = q[@"bundle"] ?: q[@"id"];
	NSString *profileName = q[@"profile"] ?: q[@"name"];

	if ([host isEqualToString:@"list"] || [url.path isEqualToString:@"/list"]) {
		self.tabBar.selectedIndex = 0;
		[self.appsNav popToRootViewControllerAnimated:YES];
		return YES;
	}

	if ([host isEqualToString:@"settings"]) {
		self.tabBar.selectedIndex = 1;
		[self.settingsNav popToRootViewControllerAnimated:YES];
		return YES;
	}

	if ([host isEqualToString:@"open"]) {
		if (bundle.length) {
			[SBContainerManager.shared openApp:bundle error:nil];
			return YES;
		}
	}

	if ([host isEqualToString:@"manage"] || [host isEqualToString:@"app"]) {
		if (bundle.length) {
			SBAppInfo *info = [SBContainerManager.shared appInfoForBundleID:bundle];
			if (info) {
				self.tabBar.selectedIndex = 0;
				[self.appsNav popToRootViewControllerAnimated:NO];
				SBProfilesViewController *vc = [[SBProfilesViewController alloc] initWithApp:info];
				[self.appsNav pushViewController:vc animated:YES];
				return YES;
			}
		}
	}

	if ([host isEqualToString:@"switch"] && bundle.length && profileName.length) {
		NSArray<SBProfileInfo *> *profiles = [SBContainerManager.shared profilesForBundleID:bundle];
		SBProfileInfo *target = nil;
		for (SBProfileInfo *p in profiles) {
			if ([p.profileID isEqualToString:profileName] || [p.name isEqualToString:profileName]) {
				target = p;
				break;
			}
		}
		UIViewController *top = [self topPresenter];
		if (!target) {
			UIAlertController *a = [UIAlertController alertControllerWithTitle:@"找不到配置"
																	   message:[NSString stringWithFormat:@"%@ / %@", bundle, profileName]
																preferredStyle:UIAlertControllerStyleAlert];
			[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
			[top presentViewController:a animated:YES completion:nil];
			return YES;
		}
		if (target.isActive) {
			[SBContainerManager.shared openApp:bundle error:nil];
			return YES;
		}
		UIAlertController *busy = [UIAlertController alertControllerWithTitle:@"正在切换…" message:target.name preferredStyle:UIAlertControllerStyleAlert];
		[top presentViewController:busy animated:YES completion:nil];
		NSString *active = [SBContainerManager.shared activeProfileIDForBundleID:bundle];
		[SBContainerManager.shared switchToProfile:target.profileID
										  bundleID:bundle
								 saveCurrentAsName:active.length ? nil : @"切换前自动保存"
										  progress:nil
										completion:^(NSError *error) {
			[busy dismissViewControllerAnimated:YES completion:^{
				if (error) {
					UIAlertController *e = [UIAlertController alertControllerWithTitle:@"切换失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
					[e addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
					[top presentViewController:e animated:YES completion:nil];
					return;
				}
				if (SBSettingsBool(SBSettingAutoOpenAfterSwitch)) {
					[SBContainerManager.shared openApp:bundle error:nil];
					return;
				}
				UIAlertController *done = [UIAlertController alertControllerWithTitle:@"切换完成" message:@"是否打开 App？" preferredStyle:UIAlertControllerStyleAlert];
				[done addAction:[UIAlertAction actionWithTitle:@"不用" style:UIAlertActionStyleCancel handler:nil]];
				[done addAction:[UIAlertAction actionWithTitle:@"打开" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
					[SBContainerManager.shared openApp:bundle error:nil];
				}]];
				[top presentViewController:done animated:YES completion:nil];
			}];
		}];
		return YES;
	}

	return YES;
}

@end
