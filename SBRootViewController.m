#import "SBRootViewController.h"
#import "SBContainerManager.h"
#import "SBProfilesViewController.h"
#import "SBSettings.h"

@interface SBRootViewController () <UISearchResultsUpdating>
@property (nonatomic, strong) NSArray<SBAppInfo *> *allApps;
@property (nonatomic, strong) NSArray<SBAppInfo *> *apps;
@property (nonatomic, strong) UISearchController *searchController;
@property (nonatomic, strong) UIAlertController *progressAlert;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *progressLabel;
@end

@implementation SBRootViewController

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"应用";
	self.navigationController.navigationBar.prefersLargeTitles = YES;
	self.tableView.rowHeight = 64;

	self.searchController = [[UISearchController alloc] initWithSearchResultsController:nil];
	self.searchController.searchResultsUpdater = self;
	self.searchController.obscuresBackgroundDuringPresentation = NO;
	self.searchController.searchBar.placeholder = @"搜索 App 名称或 Bundle ID";
	self.navigationItem.searchController = self.searchController;
	self.navigationItem.hidesSearchBarWhenScrolling = NO;
	self.definesPresentationContext = YES;

	self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(reload)];

	UIRefreshControl *rc = [UIRefreshControl new];
	[rc addTarget:self action:@selector(reload) forControlEvents:UIControlEventValueChanged];
	self.refreshControl = rc;

	// 兼容 iOS 15：长按手势（context menu 也会挂，双保险）
	UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
	lp.minimumPressDuration = 0.45;
	[self.tableView addGestureRecognizer:lp];

	[self reload];
}

- (void)viewWillAppear:(BOOL)animated {
	[super viewWillAppear:animated];
	[self reload];
}

- (void)reload {
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSArray *list = [SBContainerManager.shared listUserApps];
		dispatch_async(dispatch_get_main_queue(), ^{
			self.allApps = list;
			[self applyFilter:self.searchController.searchBar.text];
			[self.refreshControl endRefreshing];
			self.navigationItem.prompt = [NSString stringWithFormat:@"%lu 个可管理 App · 长按快速切号", (unsigned long)list.count];
		});
	});
}

- (void)applyFilter:(NSString *)text {
	NSString *q = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
	if (!q.length) {
		self.apps = self.allApps;
	} else {
		NSMutableArray *m = [NSMutableArray array];
		for (SBAppInfo *a in self.allApps) {
			if ([a.name.lowercaseString containsString:q] || [a.bundleID.lowercaseString containsString:q]) {
				[m addObject:a];
			}
		}
		self.apps = m;
	}
	[self.tableView reloadData];
}

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
	[self applyFilter:searchController.searchBar.text];
}

#pragma mark - Long press / menus

- (void)handleLongPress:(UILongPressGestureRecognizer *)gr {
	if (gr.state != UIGestureRecognizerStateBegan) return;
	CGPoint p = [gr locationInView:self.tableView];
	NSIndexPath *ip = [self.tableView indexPathForRowAtPoint:p];
	if (!ip || ip.row >= (NSInteger)self.apps.count) return;
	SBAppInfo *app = self.apps[ip.row];
	UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:ip];
	[self presentQuickMenuForApp:app sourceView:cell ?: self.tableView];
}

- (void)presentQuickMenuForApp:(SBAppInfo *)app sourceView:(UIView *)sourceView {
	NSArray<SBProfileInfo *> *profiles = [SBContainerManager.shared profilesForBundleID:app.bundleID];

	UIAlertController *sheet = [UIAlertController alertControllerWithTitle:app.name
																   message:profiles.count ? @"选择配置快速切换" : @"还没有配置，先从当前新建"
															preferredStyle:UIAlertControllerStyleActionSheet];

	__weak typeof(self) weakSelf = self;

	for (SBProfileInfo *profile in profiles) {
		NSString *title = profile.isActive
			? [NSString stringWithFormat:@"● %@（当前）", profile.name]
			: [NSString stringWithFormat:@"切换到「%@」", profile.name];
		UIAlertActionStyle style = profile.isActive ? UIAlertActionStyleDefault : UIAlertActionStyleDestructive;
		[sheet addAction:[UIAlertAction actionWithTitle:title style:style handler:^(UIAlertAction *_) {
			if (profile.isActive) {
				// 当前配置：提供打开 App
				[SBContainerManager.shared openApp:app.bundleID error:nil];
				return;
			}
			[weakSelf quickSwitchApp:app toProfile:profile];
		}]];
	}

	[sheet addAction:[UIAlertAction actionWithTitle:@"从当前新建配置…" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		[weakSelf quickCreateForApp:app];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"打开目标 App" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		NSError *err = nil;
		[SBContainerManager.shared openApp:app.bundleID error:&err];
		if (err) [weakSelf presentError:err];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"强制关闭目标 App" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		[SBContainerManager.shared terminateApp:app.bundleID error:nil];
		[weakSelf toast:@"已发送关闭指令"];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"管理全部配置" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		SBProfilesViewController *vc = [[SBProfilesViewController alloc] initWithApp:app];
		[weakSelf.navigationController pushViewController:vc animated:YES];
	}]];
	[sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];

	UIPopoverPresentationController *pop = sheet.popoverPresentationController;
	if (pop) {
		pop.sourceView = sourceView;
		pop.sourceRect = sourceView.bounds;
	}
	[self presentViewController:sheet animated:YES completion:nil];
}

- (void)quickCreateForApp:(SBAppInfo *)app {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"从当前新建配置"
															   message:[NSString stringWithFormat:@"备份「%@」当前完整数据（容器+Group+钥匙串）", app.name]
														preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		NSDateFormatter *f = [NSDateFormatter new];
		f.dateFormat = @"MMdd-HHmm";
		tf.text = [NSString stringWithFormat:@"配置 %@", [f stringFromDate:NSDate.date]];
		tf.placeholder = @"配置名称";
	}];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"创建" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		NSString *name = a.textFields.firstObject.text ?: @"未命名";
		[weakSelf showProgress:@"正在创建配置"];
		[SBContainerManager.shared createProfileFromCurrentForBundleID:app.bundleID
																  name:name
															 progress:^(NSString *message, double progress) {
			[weakSelf updateProgress:message value:progress];
		} completion:^(NSError *error) {
			[weakSelf hideProgress:^{
				if (error) [weakSelf presentError:error];
				else {
					[weakSelf reload];
					[weakSelf toast:@"创建成功"];
				}
			}];
		}];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}


- (void)quickCreateFreshForApp:(SBAppInfo *)app resetDevice:(BOOL)reset {
	NSString *title = reset ? @"新建空配置并重置识别码" : @"新建空配置";
	UIAlertController *a = [UIAlertController alertControllerWithTitle:title
															   message:reset
		? @"保存当前配置后，清空目标容器与 Keychain，并写入新的本地设备识别码种子。"
		: @"保存当前配置后，清空目标容器与 Keychain。"
														preferredStyle:UIAlertControllerStyleAlert];
	[a addTextFieldWithConfigurationHandler:^(UITextField *tf) {
		NSDateFormatter *f = [NSDateFormatter new];
		f.dateFormat = @"MMdd-HHmm";
		tf.placeholder = @"配置名称";
		tf.text = reset
			? [NSString stringWithFormat:@"新号 %@", [f stringFromDate:NSDate.date]]
			: [NSString stringWithFormat:@"空配置 %@", [f stringFromDate:NSDate.date]];
	}];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"创建并应用" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		NSString *name = a.textFields.firstObject.text ?: @"未命名";
		UIAlertController *prog = [UIAlertController alertControllerWithTitle:reset ? @"正在重置…" : @"正在创建…"
																	  message:@"请稍候"
															   preferredStyle:UIAlertControllerStyleAlert];
		[weakSelf presentViewController:prog animated:YES completion:nil];
		[SBContainerManager.shared createFreshProfileForBundleID:app.bundleID
															name:name
												 resetDeviceIDs:reset
													   progress:^(NSString *message, double progress) {
			dispatch_async(dispatch_get_main_queue(), ^{
				prog.message = message ?: @"";
			});
		} completion:^(NSError *error) {
			[prog dismissViewControllerAnimated:YES completion:^{
				if (error) {
					UIAlertController *e = [UIAlertController alertControllerWithTitle:@"失败"
																			   message:error.localizedDescription
																		preferredStyle:UIAlertControllerStyleAlert];
					[e addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
					[weakSelf presentViewController:e animated:YES completion:nil];
					return;
				}
				[weakSelf reload];
				if (SBSettingsBool(SBSettingAutoOpenAfterSwitch)) {
					[SBContainerManager.shared openApp:app.bundleID error:nil];
				}
				UIAlertController *ok = [UIAlertController alertControllerWithTitle:@"完成"
																			message:reset ? @"空配置已应用，识别码已重置" : @"空配置已应用"
																	 preferredStyle:UIAlertControllerStyleAlert];
				[ok addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
				[weakSelf presentViewController:ok animated:YES completion:nil];
			}];
		}];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}


- (void)quickSwitchApp:(SBAppInfo *)app toProfile:(SBProfileInfo *)profile {
	NSString *active = [SBContainerManager.shared activeProfileIDForBundleID:app.bundleID];
	__weak typeof(self) weakSelf = self;
	void (^doSwitch)(void) = ^{
		[weakSelf showProgress:@"正在切换"];
		[SBContainerManager.shared switchToProfile:profile.profileID
										  bundleID:app.bundleID
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
					[SBContainerManager.shared openApp:app.bundleID error:nil];
					[weakSelf toast:@"切换完成，已打开 App"];
					return;
				}
				UIAlertController *done = [UIAlertController alertControllerWithTitle:@"切换完成"
																			  message:@"是否打开目标 App？"
																	   preferredStyle:UIAlertControllerStyleAlert];
				[done addAction:[UIAlertAction actionWithTitle:@"不用" style:UIAlertActionStyleCancel handler:nil]];
				[done addAction:[UIAlertAction actionWithTitle:@"打开" style:UIAlertActionStyleDefault handler:^(UIAlertAction *__) {
					[SBContainerManager.shared openApp:app.bundleID error:nil];
				}]];
				[weakSelf presentViewController:done animated:YES completion:nil];
			}];
		}];
	};

	if (!SBSettingsBool(SBSettingConfirmBeforeSwitch)) {
		doSwitch();
		return;
	}
	UIAlertController *confirm = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"切换到「%@」？", profile.name]
																	 message:active.length ? @"会先保存当前配置，再写入目标配置并关闭 App。" : @"当前未绑定配置，会先自动保存现状再切换。"
															  preferredStyle:UIAlertControllerStyleAlert];
	[confirm addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[confirm addAction:[UIAlertAction actionWithTitle:@"切换" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
		doSwitch();
	}]];
	[self presentViewController:confirm animated:YES completion:nil];
}

#pragma mark - Progress helpers

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
	self.progressView.progress = p < 0 ? 0 : (float)MIN(MAX(p, 0), 1);
}

- (void)hideProgress:(void(^)(void))done {
	if (!self.progressAlert) { if (done) done(); return; }
	[self.progressAlert dismissViewControllerAnimated:YES completion:^{
		self.progressAlert = nil;
		if (done) done();
	}];
}

- (void)toast:(NSString *)msg {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:a animated:YES completion:^{
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[a dismissViewControllerAnimated:YES completion:nil];
		});
	}];
}

- (void)presentError:(NSError *)error {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"出错了"
															   message:error.localizedDescription
														preferredStyle:UIAlertControllerStyleAlert];
	[a addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleDefault handler:nil]];
	[self presentViewController:a animated:YES completion:nil];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return self.apps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return @"点击进入管理；长按快速切号。设置页可改切换行为与查看说明。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	static NSString *cid = @"app";
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cid];
	if (!cell) {
		cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cid];
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.imageView.clipsToBounds = YES;
		cell.imageView.contentMode = UIViewContentModeScaleAspectFit;
	}
	SBAppInfo *app = self.apps[indexPath.row];
	cell.textLabel.text = app.name;
	NSString *active = app.activeProfileID.length ? @" · 已绑定" : @"";
	cell.detailTextLabel.text = [NSString stringWithFormat:@"%@%@%@",
		app.bundleID,
		app.profileCount ? [NSString stringWithFormat:@" · %lu 套", (unsigned long)app.profileCount] : @"",
		active];
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	UIImage *icon = app.icon ?: [UIImage systemImageNamed:@"app.fill"];
	CGSize sz = CGSizeMake(40, 40);
	UIGraphicsBeginImageContextWithOptions(sz, NO, 0);
	[icon drawInRect:CGRectMake(0, 0, sz.width, sz.height)];
	cell.imageView.image = UIGraphicsGetImageFromCurrentImageContext();
	UIGraphicsEndImageContext();
	cell.imageView.layer.cornerRadius = 8;
	return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	SBAppInfo *app = self.apps[indexPath.row];
	SBProfilesViewController *vc = [[SBProfilesViewController alloc] initWithApp:app];
	[self.navigationController pushViewController:vc animated:YES];
}

// iOS 13+ 原生长按菜单（比手势更跟手）
- (UIContextMenuConfiguration *)tableView:(UITableView *)tableView
contextMenuConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath
									point:(CGPoint)point API_AVAILABLE(ios(13.0)) {
	if (indexPath.row >= (NSInteger)self.apps.count) return nil;
	SBAppInfo *app = self.apps[indexPath.row];
	__weak typeof(self) weakSelf = self;
	return [UIContextMenuConfiguration configurationWithIdentifier:app.bundleID
												   previewProvider:nil
													actionProvider:^UIMenu *(NSArray<UIMenuElement *> *suggestedActions) {
		NSArray<SBProfileInfo *> *profiles = [SBContainerManager.shared profilesForBundleID:app.bundleID];
		NSMutableArray *items = [NSMutableArray array];

		for (SBProfileInfo *profile in profiles) {
			NSString *title = profile.isActive
				? [NSString stringWithFormat:@"● %@（当前）", profile.name]
				: [NSString stringWithFormat:@"切换到 %@", profile.name];
			UIAction *act = [UIAction actionWithTitle:title
												image:[UIImage systemImageNamed:profile.isActive ? @"checkmark.circle.fill" : @"arrow.triangle.2.circlepath"]
										   identifier:nil
											  handler:^(__kindof UIAction *action) {
				if (profile.isActive) {
					[SBContainerManager.shared openApp:app.bundleID error:nil];
				} else {
					[weakSelf quickSwitchApp:app toProfile:profile];
				}
			}];
			if (!profile.isActive) {
				act.attributes = UIMenuElementAttributesDestructive;
			}
			[items addObject:act];
		}

		UIAction *create = [UIAction actionWithTitle:@"从当前新建配置"
											   image:[UIImage systemImageNamed:@"plus.circle"]
										  identifier:nil
											 handler:^(__kindof UIAction *action) {
			[weakSelf quickCreateForApp:app];
		}];
		UIAction *createFresh = [UIAction actionWithTitle:@"新建空配置并重置识别码"
											   image:[UIImage systemImageNamed:@"arrow.triangle.2.circlepath.circle"]
										  identifier:nil
											 handler:^(__kindof UIAction *action) {
			[weakSelf quickCreateFreshForApp:app resetDevice:YES];
		}];
		UIAction *openApp = [UIAction actionWithTitle:@"打开目标 App"
												image:[UIImage systemImageNamed:@"arrow.up.forward.app"]
										   identifier:nil
											  handler:^(__kindof UIAction *action) {
			[SBContainerManager.shared openApp:app.bundleID error:nil];
		}];
		UIAction *killApp = [UIAction actionWithTitle:@"强制关闭"
												image:[UIImage systemImageNamed:@"xmark.circle"]
										   identifier:nil
											  handler:^(__kindof UIAction *action) {
			[SBContainerManager.shared terminateApp:app.bundleID error:nil];
		}];
		UIAction *manage = [UIAction actionWithTitle:@"管理全部配置"
											   image:[UIImage systemImageNamed:@"folder"]
										  identifier:nil
											 handler:^(__kindof UIAction *action) {
			SBProfilesViewController *vc = [[SBProfilesViewController alloc] initWithApp:app];
			[weakSelf.navigationController pushViewController:vc animated:YES];
		}];

		UIMenu *switchMenu = profiles.count
			? [UIMenu menuWithTitle:@"切换配置" image:nil identifier:nil options:0 children:items]
			: nil;

		NSMutableArray *root = [NSMutableArray array];
		if (switchMenu) [root addObject:switchMenu];
		[root addObjectsFromArray:@[create, createFresh, openApp, killApp, manage]];
		return [UIMenu menuWithTitle:app.name children:root];
	}];
}

@end
