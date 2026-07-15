#import "SBDeviceIdentityViewController.h"
#import "SBCopyUtil.h"
#import "SBSettings.h"

@interface SBDeviceIdentityViewController ()
@property (nonatomic, strong) SBAppInfo *app;
@property (nonatomic, strong) SBProfileInfo *profile;
@property (nonatomic, strong) NSMutableDictionary *identity;
@property (nonatomic, strong) NSArray<NSDictionary *> *fields;
@property (nonatomic, assign) BOOL scrubExisting;
@property (nonatomic, assign) BOOL applyToLive;
@property (nonatomic, strong) UIAlertController *progressAlert;
@property (nonatomic, strong) UILabel *progressLabel;
@end

@implementation SBDeviceIdentityViewController

- (instancetype)initWithApp:(SBAppInfo *)app profile:(SBProfileInfo *)profile {
	self = [super initWithStyle:UITableViewStyleInsetGrouped];
	if (self) {
		_app = app;
		_profile = profile;
		_scrubExisting = YES;
		_applyToLive = profile.isActive;
	}
	return self;
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"设备识别码";
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
	self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 72;

	self.fields = @[
		@{ @"title": @"Device UUID", @"key": @"deviceUUID", @"ph": @"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" },
		@{ @"title": @"Vendor UUID (IDFV 种子)", @"key": @"vendorUUID", @"ph": @"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" },
		@{ @"title": @"Advertising UUID (IDFA 种子)", @"key": @"advertisingUUID", @"ph": @"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" },
		@{ @"title": @"Install UUID", @"key": @"installUUID", @"ph": @"xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" },
		@{ @"title": @"OpenUDID", @"key": @"openUDID", @"ph": @"32 位十六进制" },
		@{ @"title": @"Serial", @"key": @"serial", @"ph": @"8-20 位字母数字" },
	];

	NSDictionary *existing = [SBContainerManager.shared deviceIdentityForProfile:self.profile.profileID bundleID:self.app.bundleID];
	if (existing.count) {
		self.identity = [existing mutableCopy];
	} else {
		self.identity = [[SBContainerManager.shared generateDeviceIdentity] mutableCopy];
	}

	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithTitle:@"保存" style:UIBarButtonItemStyleDone target:self action:@selector(save)];
}

- (void)regenAll {
	NSDictionary *gen = [SBContainerManager.shared generateDeviceIdentity];
	[self.identity addEntriesFromDictionary:gen];
	[self.tableView reloadData];
	[self toast:@"已全部重生成（未保存）"];
}

- (void)regenKey:(NSString *)key {
	NSDictionary *gen = [SBContainerManager.shared generateDeviceIdentity];
	if (gen[key]) {
		self.identity[key] = gen[key];
		[self.tableView reloadData];
	}
}

- (void)fieldChanged:(UITextField *)tf {
	NSString *key = tf.accessibilityIdentifier;
	if (!key.length) return;
	self.identity[key] = tf.text ?: @"";
}

- (void)collectFields {
	[self.view endEditing:YES];
	for (NSInteger i = 0; i < (NSInteger)self.fields.count; i++) {
		UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:i inSection:0]];
		for (UIView *sub in cell.contentView.subviews) {
			if (![sub isKindOfClass:UITextField.class]) continue;
			UITextField *tf = (UITextField *)sub;
			if (tf.accessibilityIdentifier.length) self.identity[tf.accessibilityIdentifier] = tf.text ?: @"";
		}
	}
}

- (void)save {
	[self collectFields];
	NSDictionary *norm = [SBContainerManager.shared normalizedDeviceIdentity:self.identity];
	self.identity = [norm mutableCopy];
	[self.tableView reloadData];

	NSString *msg = self.applyToLive
		? @"将写入该配置，并应用到当前 App 容器（会先关闭 App）。"
		: @"将写入该配置。下次切换到此配置时生效。";
	UIAlertController *a = [UIAlertController alertControllerWithTitle:@"保存设备识别码？" message:msg preferredStyle:UIAlertControllerStyleAlert];
	__weak typeof(self) weakSelf = self;
	[a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
	[a addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction *_) {
		[weakSelf performSave];
	}]];
	[self presentViewController:a animated:YES completion:nil];
}

- (void)performSave {
	[self showProgress:@"正在保存识别码"];
	__weak typeof(self) weakSelf = self;
	[SBContainerManager.shared updateDeviceIdentity:self.identity
										 forProfile:self.profile.profileID
										   bundleID:self.app.bundleID
										applyToLive:self.applyToLive
									   scrubExisting:self.scrubExisting
										   progress:^(NSString *message, double progress) {
		[weakSelf updateProgress:message];
	} completion:^(NSError *error) {
		[weakSelf hideProgress:^{
			if (error) {
				UIAlertController *e = [UIAlertController alertControllerWithTitle:@"保存失败" message:error.localizedDescription preferredStyle:UIAlertControllerStyleAlert];
				[e addAction:[UIAlertAction actionWithTitle:@"好" style:UIAlertActionStyleCancel handler:nil]];
				[weakSelf presentViewController:e animated:YES completion:nil];
				return;
			}
			[weakSelf toast:@"已保存"];
			if (SBSettingsBool(SBSettingAutoOpenAfterSwitch) && weakSelf.applyToLive) {
				[SBContainerManager.shared openApp:weakSelf.app.bundleID error:nil];
			}
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.4 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				[weakSelf.navigationController popViewControllerAnimated:YES];
			});
		}];
	}];
}

- (void)showProgress:(NSString *)title {
	self.progressAlert = [UIAlertController alertControllerWithTitle:title message:@"请稍候" preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:self.progressAlert animated:YES completion:nil];
}

- (void)updateProgress:(NSString *)message {
	self.progressAlert.message = message.length ? message : @"请稍候";
}

- (void)hideProgress:(void (^)(void))done {
	if (!self.progressAlert) { if (done) done(); return; }
	[self.progressAlert dismissViewControllerAnimated:YES completion:^{
		self.progressAlert = nil;
		if (done) done();
	}];
}

- (void)toast:(NSString *)msg {
	UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
	[self presentViewController:a animated:YES completion:^{
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[a dismissViewControllerAnimated:YES completion:nil];
		});
	}];
}

- (void)toggleScrub:(UISwitch *)sw { self.scrubExisting = sw.on; }
- (void)toggleApply:(UISwitch *)sw { self.applyToLive = sw.on; }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 0) return self.fields.count;
	if (section == 1) return 2;
	return 3;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return [NSString stringWithFormat:@"配置：%@", self.profile.name ?: @""];
	if (section == 1) return @"应用选项";
	return @"操作";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) {
		return @"可手动修改任意字段，或点右侧骰子单独重生成。保存时自动规范化格式。\n纯巨魔写入本地种子，系统级 IDFV/IDFA 可能不变。";
	}
	if (section == 1) {
		return self.profile.isActive
			? @"当前为活动配置：建议开启「应用到当前容器」。"
			: @"非活动配置：默认只写入存档，切换过去时再生效。";
	}
	return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		NSDictionary *f = self.fields[indexPath.row];
		NSString *key = f[@"key"];
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		cell.textLabel.text = f[@"title"];
		cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
		cell.detailTextLabel.text = @" ";

		UITextField *tf = [UITextField new];
		tf.translatesAutoresizingMaskIntoConstraints = NO;
		tf.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
		tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
		tf.autocorrectionType = UITextAutocorrectionTypeNo;
		tf.clearButtonMode = UITextFieldViewModeWhileEditing;
		tf.placeholder = f[@"ph"];
		tf.text = [NSString stringWithFormat:@"%@", self.identity[key] ?: @""];
		tf.accessibilityIdentifier = key;
		tf.returnKeyType = UIReturnKeyDone;
		[tf addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
		[tf addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingDidEnd];
		[cell.contentView addSubview:tf];

		UIButton *dice = [UIButton buttonWithType:UIButtonTypeSystem];
		dice.translatesAutoresizingMaskIntoConstraints = NO;
		[dice setImage:[UIImage systemImageNamed:@"dice"] forState:UIControlStateNormal];
		dice.tag = indexPath.row;
		[dice addTarget:self action:@selector(diceTapped:) forControlEvents:UIControlEventTouchUpInside];
		[cell.contentView addSubview:dice];

		UIButton *copyBtn = [UIButton buttonWithType:UIButtonTypeSystem];
		copyBtn.translatesAutoresizingMaskIntoConstraints = NO;
		[copyBtn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
		copyBtn.tag = indexPath.row;
		[copyBtn addTarget:self action:@selector(copyTapped:) forControlEvents:UIControlEventTouchUpInside];
		[cell.contentView addSubview:copyBtn];

		[NSLayoutConstraint activateConstraints:@[
			[tf.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
			[tf.trailingAnchor constraintEqualToAnchor:copyBtn.leadingAnchor constant:-8],
			[tf.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-10],
			[tf.topAnchor constraintEqualToAnchor:cell.textLabel.bottomAnchor constant:4],
			[copyBtn.centerYAnchor constraintEqualToAnchor:tf.centerYAnchor],
			[copyBtn.trailingAnchor constraintEqualToAnchor:dice.leadingAnchor constant:-4],
			[copyBtn.widthAnchor constraintEqualToConstant:28],
			[dice.centerYAnchor constraintEqualToAnchor:tf.centerYAnchor],
			[dice.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
			[dice.widthAnchor constraintEqualToConstant:28],
			[cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:72],
		]];
		return cell;
	}

	if (indexPath.section == 1) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		UISwitch *sw = [UISwitch new];
		if (indexPath.row == 0) {
			cell.textLabel.text = @"清洗已有识别字段";
			cell.detailTextLabel.text = @"替换沙盒内常见 ID 键值";
			sw.on = self.scrubExisting;
			[sw addTarget:self action:@selector(toggleScrub:) forControlEvents:UIControlEventValueChanged];
		} else {
			cell.textLabel.text = @"应用到当前容器";
			cell.detailTextLabel.text = self.profile.isActive ? @"活动配置，建议开启" : @"即使未激活也立刻写入 live";
			sw.on = self.applyToLive;
			[sw addTarget:self action:@selector(toggleApply:) forControlEvents:UIControlEventValueChanged];
		}
		cell.accessoryView = sw;
		return cell;
	}

	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	if (indexPath.row == 0) {
		cell.textLabel.text = @"全部重生成";
		cell.textLabel.textColor = UIColor.systemBlueColor;
	} else if (indexPath.row == 1) {
		cell.textLabel.text = @"复制全部";
		cell.textLabel.textColor = UIColor.systemBlueColor;
	} else {
		cell.textLabel.text = @"保存并应用";
		cell.textLabel.textColor = UIColor.systemGreenColor;
	}
	return cell;
}

- (void)diceTapped:(UIButton *)btn {
	if (btn.tag < 0 || btn.tag >= (NSInteger)self.fields.count) return;
	[self regenKey:self.fields[btn.tag][@"key"]];
}

- (void)copyTapped:(UIButton *)btn {
	if (btn.tag < 0 || btn.tag >= (NSInteger)self.fields.count) return;
	NSString *key = self.fields[btn.tag][@"key"];
	SBCopyString([NSString stringWithFormat:@"%@", self.identity[key] ?: @""]);
	SBPresentCopiedToast(self, key);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section != 2) return;
	if (indexPath.row == 0) {
		[self regenAll];
	} else if (indexPath.row == 1) {
		NSDictionary *norm = [SBContainerManager.shared normalizedDeviceIdentity:self.identity];
		NSMutableString *msg = [NSMutableString string];
		[msg appendFormat:@"Device: %@\n", norm[@"deviceUUID"] ?: @"-"];
		[msg appendFormat:@"Vendor: %@\n", norm[@"vendorUUID"] ?: @"-"];
		[msg appendFormat:@"Advertising: %@\n", norm[@"advertisingUUID"] ?: @"-"];
		[msg appendFormat:@"Install: %@\n", norm[@"installUUID"] ?: @"-"];
		[msg appendFormat:@"OpenUDID: %@\n", norm[@"openUDID"] ?: @"-"];
		[msg appendFormat:@"Serial: %@", norm[@"serial"] ?: @"-"];
		SBCopyString(msg);
		SBPresentCopiedToast(self, @"全部识别码");
	} else {
		[self save];
	}
}

@end
