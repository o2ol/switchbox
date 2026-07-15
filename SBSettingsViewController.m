#import "SBSettingsViewController.h"
#import "SBHelpViewController.h"
#import "SBSchemeViewController.h"
#import "SBVersionViewController.h"
#import "SBAboutViewController.h"
#import "SBPathsViewController.h"
#import "SBContainerManager.h"
#import "SBCopyUtil.h"
#import "SBSettings.h"

NSString * const SBSettingAutoOpenAfterSwitch = @"autoOpenAfterSwitch";
NSString * const SBSettingConfirmBeforeSwitch = @"confirmBeforeSwitch";
NSString * const SBSettingSkipCaches = @"skipCaches";
NSString * const SBSettingAppearance = @"appearance";

@interface SBSettingsViewController ()
@property (nonatomic, strong) NSUserDefaults *defaults;
@end

@implementation SBSettingsViewController

+ (NSUserDefaults *)sharedDefaults {
	static NSUserDefaults *d;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		d = NSUserDefaults.standardUserDefaults;
		[d registerDefaults:@{
			SBSettingAutoOpenAfterSwitch: @YES,
			SBSettingConfirmBeforeSwitch: @YES,
			SBSettingSkipCaches: @YES,
			SBSettingAppearance: @"system",
		}];
	});
	return d;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"设置";
	self.navigationController.navigationBar.prefersLargeTitles = YES;
	self.defaults = [SBSettingsViewController sharedDefaults];
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 52;
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self.tableView reloadData];
}

- (void)toggleChanged:(UISwitch *)sw {
	NSString *key = nil;
	if (sw.tag == 1) key = SBSettingAutoOpenAfterSwitch;
	else if (sw.tag == 2) key = SBSettingConfirmBeforeSwitch;
	else if (sw.tag == 3) key = SBSettingSkipCaches;
	if (!key) return;
	[self.defaults setBool:sw.on forKey:key];
	[self.defaults synchronize];
}

#pragma mark - Table

// 0 外观 / 1 切换行为 / 2 备份 / 3 文档与信息
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 1;
	if (section == 1) return 3;
	if (section == 2) return 2;
	return 4;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"外观";
	if (section == 1) return @"切换行为";
	if (section == 2) return @"备份";
	return @"文档与信息";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) return @"支持跟随系统、浅色、深色。更改后立即生效。";
	if (section == 1) return @"控制切换时的确认与是否自动打开目标 App。";
	if (section == 2) return @"默认跳过 tmp 与 Library/Caches。点「路径」可查看并快速复制。";
	return @"帮助说明、URL Scheme、版本信息、关于 为独立页面。";
}

- (UITableViewCell *)switchCellTitle:(NSString *)title detail:(NSString *)detail tag:(NSInteger)tag on:(BOOL)on enabled:(BOOL)enabled {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.selectionStyle = UITableViewCellSelectionStyleNone;
	cell.textLabel.text = title;
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	UISwitch *sw = [UISwitch new];
	sw.tag = tag;
	sw.on = on;
	sw.enabled = enabled;
	if (enabled) [sw addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
	cell.accessoryView = sw;
	return cell;
}

- (NSString *)appearanceTitle {
	NSString *mode = [self.defaults stringForKey:SBSettingAppearance] ?: @"system";
	if ([mode isEqualToString:@"light"]) return @"浅色";
	if ([mode isEqualToString:@"dark"]) return @"深色";
	return @"跟随系统";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
		cell.textLabel.text = @"外观模式";
		cell.detailTextLabel.text = [self appearanceTitle];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		return cell;
	}

	if (indexPath.section == 1) {
		if (indexPath.row == 0) {
			return [self switchCellTitle:@"切换后自动打开 App"
								 detail:@"切换完成不再二次询问"
									tag:1
									 on:[self.defaults boolForKey:SBSettingAutoOpenAfterSwitch]
								enabled:YES];
		}
		if (indexPath.row == 1) {
			return [self switchCellTitle:@"切换前二次确认"
								 detail:@"防止误触切换"
									tag:2
									 on:[self.defaults boolForKey:SBSettingConfirmBeforeSwitch]
								enabled:YES];
		}
		return [self switchCellTitle:@"操作前强制关闭目标 App"
							 detail:@"始终开启，保证数据一致"
								tag:0
								 on:YES
							enabled:NO];
	}

	if (indexPath.section == 2) {
		if (indexPath.row == 0) {
			return [self switchCellTitle:@"跳过 Caches / tmp"
								 detail:@"减小体积，加快备份"
									tag:3
									 on:[self.defaults boolForKey:SBSettingSkipCaches]
								enabled:YES];
		}
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.textLabel.text = @"路径";
		cell.detailTextLabel.text = SBContainerManager.shared.storeRoot ?: @"-";
		cell.detailTextLabel.numberOfLines = 2;
		cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
		cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
		UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
		[btn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
		btn.frame = CGRectMake(0, 0, 34, 34);
		[btn addTarget:self action:@selector(quickCopyStoreRoot) forControlEvents:UIControlEventTouchUpInside];
		UIView *box = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 70, 34)];
		UIImageView *chev = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"chevron.right"]];
		chev.tintColor = UIColor.tertiaryLabelColor;
		chev.frame = CGRectMake(42, 8, 12, 18);
		chev.contentMode = UIViewContentModeScaleAspectFit;
		[box addSubview:btn];
		[box addSubview:chev];
		cell.accessoryView = box;
		return cell;
	}

	NSArray *titles = @[@"帮助说明", @"URL Scheme", @"版本信息", @"关于"];
	NSArray *subs = @[
		@"原理、上手步骤、注意事项",
		@"switchbox:// 快捷唤起",
		@"版本号 / Build / Bundle",
		@"产品定位与声明",
	];
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = titles[indexPath.row];
	cell.detailTextLabel.text = subs[indexPath.row];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
	if (indexPath.row == 2) {
		NSString *ver = NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] ?: @"-";
		NSString *build = NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"] ?: @"-";
		cell.detailTextLabel.text = [NSString stringWithFormat:@"当前 %@（%@）", ver, build];
	}
	return cell;
}

- (void)quickCopyStoreRoot {
	NSString *store = SBContainerManager.shared.storeRoot ?: @"";
	SBCopyString(store);
	SBPresentCopiedToast(self, @"备份根目录");
}

- (void)pickAppearance {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"外观模式"
																   message:@"选择界面颜色风格"
															preferredStyle:UIAlertControllerStyleActionSheet];
	NSArray *opts = @[
		@[@"system", @"跟随系统"],
		@[@"light", @"浅色"],
		@[@"dark", @"深色"],
	];
	NSString *cur = [self.defaults stringForKey:SBSettingAppearance] ?: @"system";
	__weak typeof(self) weakSelf = self;
	for (NSArray *o in opts) {
		NSString *key = o[0], *title = o[1];
		NSString *label = [key isEqualToString:cur] ? [NSString stringWithFormat:@"✓ %@", title] : title;
		[sheet addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
			[weakSelf.defaults setObject:key forKey:SBSettingAppearance];
			[weakSelf.defaults synchronize];
			SBApplyAppearance();
			[weakSelf.tableView reloadData];
		}]];
	}
	[sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	UIPopoverPresentationController *pop = sheet.popoverPresentationController;
	if (pop) {
		pop.sourceView = self.view;
		pop.sourceRect = CGRectMake(self.view.bounds.size.width/2, 120, 1, 1);
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0) {
		[self pickAppearance];
		return;
	}
	if (indexPath.section == 2 && indexPath.row == 1) {
		SBPathsViewController *vc = [[SBPathsViewController alloc] init];
		[self.navigationController pushViewController:vc animated:YES];
		return;
	}
	if (indexPath.section != 3) return;

	UIViewController *vc = nil;
	if (indexPath.row == 0) vc = [[SBHelpViewController alloc] init];
	else if (indexPath.row == 1) vc = [[SBSchemeViewController alloc] init];
	else if (indexPath.row == 2) vc = [[SBVersionViewController alloc] init];
	else vc = [[SBAboutViewController alloc] init];
	[self.navigationController pushViewController:vc animated:YES];
}


@end

NSUserDefaults *SBSettingsDefaults(void) {
	return [SBSettingsViewController sharedDefaults];
}
BOOL SBSettingsBool(NSString *key) {
	return [[SBSettingsViewController sharedDefaults] boolForKey:key];
}

NSString *SBSettingsString(NSString *key) {
	return [[SBSettingsViewController sharedDefaults] stringForKey:key] ?: @"";
}

void SBApplyAppearance(void) {
	if (@available(iOS 13.0, *)) {
		NSString *mode = SBSettingsString(SBSettingAppearance);
		UIUserInterfaceStyle style = UIUserInterfaceStyleUnspecified;
		if ([mode isEqualToString:@"light"]) style = UIUserInterfaceStyleLight;
		else if ([mode isEqualToString:@"dark"]) style = UIUserInterfaceStyleDark;
		else style = UIUserInterfaceStyleUnspecified; // follow system

		UIApplication *app = UIApplication.sharedApplication;
		for (UIScene *scene in app.connectedScenes) {
			if (![scene isKindOfClass:UIWindowScene.class]) continue;
			for (UIWindow *w in ((UIWindowScene *)scene).windows) {
				w.overrideUserInterfaceStyle = style;
			}
		}
		// legacy single window
		id del = app.delegate;
		if ([del respondsToSelector:@selector(window)]) {
			UIWindow *w = [del window];
			w.overrideUserInterfaceStyle = style;
		}
	}
}
