#import "SBProfilesViewController.h"
#import "SBSettings.h"
#import "SBCopyUtil.h"

@interface SBProfilesViewController ()
@property (nonatomic, strong) SBAppInfo *app;
@property (nonatomic, strong) NSArray<SBProfileInfo *> *profiles;
@property (nonatomic, strong) UIAlertController *progressAlert;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *progressLabel;
@end

@implementation SBProfilesViewController

- (instancetype)initWithApp:(SBAppInfo *)app {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_app = app;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = self.app.name;
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;

	self.navigationItem.rightBarButtonItems = @[
		[[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd target:self action:@selector(showCreateMenu)],
		[[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"info.circle"] style:UIBarButtonItemStylePlain target:self action:@selector(showPathInfo)],
	];

	UIRefreshControl *rc = [UIRefreshControl new];
	[rc addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = rc;

	[self reload];
}

- (void)showPathInfo {
	NSString *bundle = self.app.bundleID ?: @"";
	NSString *data = self.app.dataPath ?: @"";
	NSString *appPath = self.app.bundlePath ?: @"";
	NSString *backup = [SBContainerManager.shared.storeRoot stringByAppendingPathComponent:bundle] ?: @"";
	NSString *msg = [NSString stringWithFormat:
		@"Bundle ID:\n%@\n\n数据容器:\n%@\n\nApp 路径:\n%@\n\n备份目录:\n%@",
		bundle, data.length ? data : @"(无)", appPath.length ? appPath : @"(无)", backup];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"路径信息" message:msg preferredStyle:UIAlertControllerStyleAlert];
	void (^copyOne)(NSString *, NSString *) = ^(NSString *title, NSString *val) {
		if (!val.length) return;
		SBCopyString(val);
	};
	[a addAction:[UIAlertAction actionWithTitle:@"复制 Bundle ID" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		SBCopyString(bundle);
		SBPresentCopiedToast(self, @"Bundle ID");
	}]];
	[a addAction:[UIAlertAction actionWithTitle:@"复制数据容器" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		SBCopyString(data);
		SBPresentCopiedToast(self, @"数据容器");
	}]];
	[a addAction:[UIAlertAction actionWithTitle:@"复制备份目录" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		SBCopyString(backup);
		SBPresentCopiedToast(self, @"备份目录");
	}]];
	[a addAction:[UIAlertAction actionWithTitle:@"复制全部" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		SBCopyString(msg);
		SBPresentCopiedToast(self, @"路径信息");
	}]];
	[a addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)reload {
	self.profiles = [SBContainerManager.shared profilesForBundleID:self.app.bundleID];
	// refresh data path
	SBAppInfo *fresh = [SBContainerManager.shared appInfoForBundleID:self.app.bundleID];
	if (fresh.dataPath) self.app.dataPath = fresh.dataPath;
	[self.tableView reloadData];
	[self.refreshControl endRefreshing];
}

#pragma mark - Progress UI

- (void)showProgress:(NSString *)title {
	self.progressAlert = [UIAlertController alertControllerWithTitle:title message:@"\n\n\n" preferredStyle:UIAlertControllerStyleAlert];
	self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
	self.progressView.translatesAutoresizingMaskIntoConstraints = NO;
	self.progressLabel = [UILabel new];
	self.progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
	self.progressLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
	self.progressLabel.textAlignment = NSTextAlignmentCenter;
	self.progressLabel.numberOfLines = 2;
	self.progressLabel.text = @"准备中…";

	[self.progressAlert.view addSubview:self.progressView];
	[self.progressAlert.view addSubview:self.progressLabel];
	[NSLayoutConstraint activateConstraints:@[
		[self.progressView.leadingAnchor constraintEqualToAnchor:self.progressAlert.view.leadingAnchor constant:20],
		[self.progressView.trailingAnchor constraintEqualToAnchor:self.progressAlert.view.trailingAnchor constant:-20],
		[self.progressView.bottomAnchor constraintEqualToAnchor:self.progressAlert.view.bottomAnchor constant:-50],
		[self.progressLabel.leadingAnchor constraintEqualToAnchor:self.progressAlert.view.leadingAnchor constant:16],
		[self.progressLabel.trailingAnchor constraintEqualToAnchor:self.progressAlert.view.trailingAnchor constant:-16],
		[self.progressLabel.bottomAnchor constraintEqualToAnchor:self.progressView.topAnchor constant:-10],
	]];
	[self presentViewController:self.progressAlert animated:YES completion:nil];
}

- (void)updateProgress:(NSString *)msg value:(double)p {
	self.progressLabel.text = msg ?: @"";
	if (p < 0) {
		self.progressView.progress = 0;
	} else {
		self.progressView.progress = (float)MIN(MAX(p, 0), 1);
	}
}

- (void)hideProgress:(void(^)(void))done {
	if (!self.progressAlert) {
		if (done) done();
		return;
	}
	[self.progressAlert dismissViewControllerAnimated:YES completion:^{
		self.progressAlert = nil;
		if (done) done();
	}];
}

- (void)toast:(NSString *)msg {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:a animated:YES completion:^{
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[a dismissViewControllerAnimated:YES completion:nil];
		});
	}];
}

#pragma mark - Actions

- (void)showCreateMenu {
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"新建配置"
																   message:@"选择创建方式"
															preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:@"从当前新建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		[weakSelf createProfileFromCurrent];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"新建空配置并重置识别码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		[weakSelf createFreshProfileResettingDevice:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"新建空配置（不重置识别码）" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		[weakSelf createFreshProfileResettingDevice:NO];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	UIPopoverPresentationController *pop = sheet.popoverPresentationController;
	if (pop) {
		pop.barButtonItem = self.navigationItem.rightBarButtonItems.firstObject;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)createProfileFromCurrent {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"从当前新建配置"
															   message:@"会关闭目标 App，备份：完整沙盒 + App Group + Keychain。\n\n重要：每新建一套配置都会把「当前配置」标记为它。\n正确流程：登录A→新建A；登录B→新建B；再切换。\n\n若以前创建的配置切号无效，请全部删除后按上面流程重建。"
														preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = @"配置名称，如：工作号";
		NSDateFormatter *f = [NSDateFormatter new];
		f.dateFormat = @"MMdd-HHmm";
		tf.text = [NSString stringWithFormat:@"配置 %@", [f stringFromDate:NSDate.date]];
	}];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		NSString *name = a.textFields.firstObject.text ?: @"未命名";
		[weakSelf showProgress:@"正在创建配置"];
		[SBContainerManager.shared createProfileFromCurrentForBundleID:weakSelf.app.bundleID
																  name:name
															 progress:^(NSString *message, double progress) {
			[weakSelf updateProgress:message value:progress];
		} completion:^(NSError *error) {
			[weakSelf hideProgress:^{
				if (error) {
					[weakSelf presentError:error];
				} else {
					[weakSelf reload];
					[weakSelf toast:@"创建成功"];
				}
			}];
		}];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)createFreshProfileResettingDevice:(BOOL)reset {
	NSString *title = reset ? @"新建空配置并重置识别码" : @"新建空配置";
	NSString *msg = reset
		? @"会先保存当前已绑定配置，再清空目标 App 容器与相关 Keychain，并写入新的本地设备识别码种子。\n\n注意：系统级 IDFV/IDFA 需注入才能伪装；这里重置的是 App 沙盒内常见识别字段，便于新号冷启动。\n\n完成后请打开 App 登录新账号，再「从当前新建」固化该号。"
		: @"会先保存当前已绑定配置，再清空目标 App 容器与相关 Keychain（不改写识别码种子）。\n\n完成后打开 App 登录新账号。";
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title
															   message:msg
														preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.placeholder = reset ? @"如：新号-重置识别码" : @"如：新号";
		NSDateFormatter *f = [NSDateFormatter new];
		f.dateFormat = @"MMdd-HHmm";
		tf.text = reset
			? [NSString stringWithFormat:@"新号 %@", [f stringFromDate:NSDate.date]]
			: [NSString stringWithFormat:@"空配置 %@", [f stringFromDate:NSDate.date]];
	}];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"创建并应用" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		NSString *name = a.textFields.firstObject.text ?: @"未命名";
		[weakSelf showProgress:reset ? @"正在重置并创建" : @"正在创建空配置"];
		[SBContainerManager.shared createFreshProfileForBundleID:weakSelf.app.bundleID
															name:name
												 resetDeviceIDs:reset
													   progress:^(NSString *message, double progress) {
			[weakSelf updateProgress:message value:progress];
		} completion:^(NSError *error) {
			[weakSelf hideProgress:^{
				if (error) {
					[weakSelf presentError:error];
					return;
				}
				[weakSelf reload];
				NSString *ok = reset ? @"空配置已应用，识别码已重置" : @"空配置已应用";
				if (SBSettingsBool(SBSettingAutoOpenAfterSwitch)) {
					[SBContainerManager.shared openApp:weakSelf.app.bundleID error:nil];
					[weakSelf toast:[ok stringByAppendingString:@"，已打开 App"]];
				} else {
					[weakSelf toast:ok];
				}
			}];
		}];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)switchTo:(SBProfileInfo *)profile {
	NSString *active = [SBContainerManager.shared activeProfileIDForBundleID:self.app.bundleID];
	__weak typeof(self) weakSelf = self;
	void (^doSwitch)(void) = ^{
		[weakSelf showProgress:@"正在切换"];
		[SBContainerManager.shared switchToProfile:profile.profileID
										  bundleID:weakSelf.app.bundleID
								 saveCurrentAsName:active.length ? nil : @"切换前自动保存"
										  progress:^(NSString *message, double progress) {
			[weakSelf updateProgress:message value:progress];
		} completion:^(NSError *error) {
			[weakSelf hideProgress:^{
				if (error) {
					[weakSelf presentError:error];
					return;
				}
				[weakSelf reload];
				if (SBSettingsBool(SBSettingAutoOpenAfterSwitch)) {
					[SBContainerManager.shared openApp:weakSelf.app.bundleID error:nil];
					[weakSelf toast:@"切换完成，已打开 App"];
					return;
				}
				UIAlertController *done = [UIAlertController alertControllerWithTitle:@"切换完成"
																			  message:@"是否立即打开目标 App？"
																	   preferredStyle:UIAlertControllerStyleAlert];
				[done addAction:[UIAlertAction actionWithTitle:@"不用" style:UIAlertActionStyleCancel handler:nil]];
				[done addAction:[UIAlertAction actionWithTitle:@"打开" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__) {
					NSError *oerr = nil;
					[SBContainerManager.shared openApp:weakSelf.app.bundleID error:&oerr];
					if (oerr) [weakSelf presentError:oerr];
				}]];
				[weakSelf presentViewController:done animated:YES completion:nil];
			}];
		}];
	};

	if (!SBSettingsBool(SBSettingConfirmBeforeSwitch)) {
		doSwitch();
		return;
	}
	NSString *extra = active.length
		? @"切换前会自动把当前容器写回已绑定的配置。"
		: @"当前还没有绑定配置，切换前会先把现状另存为「切换前自动保存」。";
	NSString *msg = [NSString stringWithFormat:@"%@\n\n目标 App 会被关闭，数据会被替换。", extra];
	UIAlertController *a = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"切换到「%@」？", profile.name]
															   message:msg
														preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"切换" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		doSwitch();
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)presentError:(NSError *)error {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"出错了"
															   message:error.localizedDescription
														preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)showDeviceIdentityForProfile:(SBProfileInfo *)profile {
	NSDictionary *dev = [SBContainerManager.shared deviceIdentityForProfile:profile.profileID bundleID:self.app.bundleID];
	NSString *msg;
	if (!dev.count) {
		msg = profile.resetDeviceIDs
			? @"该配置标记为已重置，但未找到 device.plist。"
			: @"该配置未重置设备识别码（从当前现场备份）。";
	} else {
		msg = [NSString stringWithFormat:
			  @"Device: %@\nVendor: %@\nAdvertising: %@\nInstall: %@\nOpenUDID: %@\nSerial: %@\n\n以上为本地写入的识别码种子，供 App 读取自有字段；系统 IDFV/IDFA 无法在纯巨魔下全局伪装。",
			  dev[@"deviceUUID"] ?: @"-",
			  dev[@"vendorUUID"] ?: @"-",
			  dev[@"advertisingUUID"] ?: @"-",
			  dev[@"installUUID"] ?: @"-",
			  dev[@"openUDID"] ?: @"-",
			  dev[@"serial"] ?: @"-"];
	}
	UIAlertController *a = [UIAlertController alertControllerWithTitle:profile.name message:msg preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		SBCopyString(msg);
		SBPresentCopiedToast(weakSelf, @"识别码");
	}]];
	[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)renameProfileNamed:(SBProfileInfo *)profile {

	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"重命名" message:nil preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		tf.text = profile.name;
	}];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		NSError *err = nil;
		[SBContainerManager.shared renameProfile:profile.profileID bundleID:weakSelf.app.bundleID toName:a.textFields.firstObject.text error:&err];
		if (err) [weakSelf presentError:err];
		else [weakSelf reload];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)deleteProfile:(SBProfileInfo *)profile {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"删除配置？"
															   message:[NSString stringWithFormat:@"将删除「%@」的备份数据，不可恢复。", profile.name]
														preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		NSError *err = nil;
		[SBContainerManager.shared deleteProfile:profile.profileID bundleID:weakSelf.app.bundleID error:&err];
		if (err) [weakSelf presentError:err];
		else [weakSelf reload];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return 4;
	return MAX(self.profiles.count, (NSUInteger)1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return section == 0 ? @"操作" : @"配置列表";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return [NSString stringWithFormat:@"目标：%@\n%@", self.app.bundleID, self.app.dataPath ?: @"数据路径未知"];
	}
	return @"绿点 = 当前绑定配置。切换时会自动回写当前数据到绑定配置。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.textAlignment = NSTextAlignmentCenter;
		if (indexPath.row == 0) {
			cell.textLabel.text = @"从当前新建配置";
			cell.textLabel.textColor = UIColor.systemBlueColor;
		} else if (indexPath.row == 1) {
			cell.textLabel.text = @"新建空配置并重置识别码";
			cell.textLabel.textColor = UIColor.systemPurpleColor;
		} else if (indexPath.row == 2) {
			cell.textLabel.text = @"打开目标 App";
			cell.textLabel.textColor = UIColor.systemBlueColor;
		} else {
			cell.textLabel.text = @"强制关闭目标 App";
			cell.textLabel.textColor = UIColor.systemOrangeColor;
		}
		return cell;
	}

	if (!self.profiles.count) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.text = @"暂无配置，点上方新建";
		cell.textLabel.textColor = UIColor.secondaryLabelColor;
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}

	SBProfileInfo *p = self.profiles[indexPath.row];
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = [NSString stringWithFormat:@"%@%@", p.isActive ? @"● " : @"", p.name];
	cell.textLabel.textColor = p.isActive ? UIColor.systemGreenColor : UIColor.labelColor;
	NSDateFormatter *f = [NSDateFormatter new];
	f.dateFormat = @"yyyy-MM-dd HH:mm";
	NSString *size = [SBContainerManager.shared humanSize:p.sizeBytes];
	NSMutableString *detail = [NSMutableString stringWithFormat:@"%@ · %@", size, [f stringFromDate:p.createdAt]];
	if (p.resetDeviceIDs) {
		[detail appendString:@" · 识别码已重置"];
		if (p.deviceUUIDShort.length) [detail appendFormat:@"(%@)", p.deviceUUIDShort];
	}
	cell.detailTextLabel.text = detail;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0) {
		if (indexPath.row == 0) {
			[self createProfileFromCurrent];
		} else if (indexPath.row == 1) {
			[self createFreshProfileResettingDevice:YES];
		} else if (indexPath.row == 2) {
			NSError *err = nil;
			[SBContainerManager.shared openApp:self.app.bundleID error:&err];
			if (err) [self presentError:err];
		} else {
			[SBContainerManager.shared terminateApp:self.app.bundleID error:nil];
			[self toast:@"已发送关闭指令"];
		}
		return;
	}
	if (!self.profiles.count) return;
	SBProfileInfo *p = self.profiles[indexPath.row];
	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:p.name message:nil preferredStyle:UIAlertControllerStyleActionSheet];
	__weak typeof(self) weakSelf = self;
	[sheet addAction:[UIAlertAction actionWithTitle:@"切换到此配置" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		[weakSelf switchTo:p];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"查看设备识别码" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		[weakSelf showDeviceIdentityForProfile:p];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"重命名" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		[weakSelf renameProfileNamed:p];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		[weakSelf deleteProfile:p];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	UIPopoverPresentationController *pop = sheet.popoverPresentationController;
	if (pop) {
		pop.sourceView = tableView;
		pop.sourceRect = [tableView rectForRowAtIndexPath:indexPath];
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)tableView:(UITableView *)tableView accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section != 1 || !self.profiles.count) return;
	SBProfileInfo *p = self.profiles[indexPath.row];
	[self tableView:tableView didSelectRowAtIndexPath:indexPath];
	(void)p;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section != 1 || !self.profiles.count) return nil;
	SBProfileInfo *p = self.profiles[indexPath.row];
	__weak typeof(self) weakSelf = self;
	UIContextualAction *del = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive title:@"删除" handler:^(__kindof UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
		[weakSelf deleteProfile:p];
		completionHandler(YES);
	}];
	UIContextualAction *sw = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleNormal title:@"切换" handler:^(__kindof UIContextualAction *action, __kindof UIView *sourceView, void (^completionHandler)(BOOL)) {
		[weakSelf switchTo:p];
		completionHandler(YES);
	}];
	sw.backgroundColor = UIColor.systemBlueColor;
	return [UISwipeActionsConfiguration configurationWithActions:@[del, sw]];
}

@end
