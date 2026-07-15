#import "SBSchemeViewController.h"
#import "SBCopyUtil.h"

@interface SBSchemeViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *items;
@end

@implementation SBSchemeViewController

- (instancetype)init {
	return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"URL Scheme";
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 72;

	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithTitle:@"全部复制"
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(copyAll)];

	self.items = @[
		@{ @"title": @"打开应用列表",
		   @"scheme": @"switchbox://list",
		   @"desc": @"回到切号箱应用列表" },
		@{ @"title": @"打开设置",
		   @"scheme": @"switchbox://settings",
		   @"desc": @"打开设置 Tab" },
		@{ @"title": @"管理某 App 配置",
		   @"scheme": @"switchbox://manage?bundle=com.xxx.app",
		   @"desc": @"进入指定 Bundle 的配置管理页，把 com.xxx.app 换成真实 Bundle ID" },
		@{ @"title": @"切换配置",
		   @"scheme": @"switchbox://switch?bundle=com.xxx.app&profile=工作号",
		   @"desc": @"按配置名或配置 ID 切换；profile 支持名称或 UUID" },
		@{ @"title": @"打开目标 App",
		   @"scheme": @"switchbox://open?bundle=com.xxx.app",
		   @"desc": @"直接拉起目标 App" },
	];
}

- (void)copyAll {
	NSMutableString *s = [NSMutableString string];
	for (NSDictionary *it in self.items) {
		[s appendFormat:@"%@\n%@\n%@\n\n", it[@"title"], it[@"scheme"], it[@"desc"]];
	}
	SBCopyString(s);
	SBPresentCopiedToast(self, @"全部 Scheme");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.items.count + 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	return section == 0 ? 1 : 2;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"说明";
	return self.items[section - 1][@"title"];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 0) return @"可用于快捷指令、书签或其他 App 唤起。点 Scheme 行或右侧按钮即可复制。";
	return self.items[section - 1][@"desc"];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 0) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
		cell.textLabel.numberOfLines = 0;
		cell.textLabel.text = @"URL Scheme 前缀：switchbox://\n\n参数：\n• bundle / id：目标 Bundle ID\n• profile / name：配置名称或配置 ID";
		cell.selectionStyle = UITableViewCellSelectionStyleNone;
		return cell;
	}
	NSDictionary *it = self.items[indexPath.section - 1];
	if (indexPath.row == 0) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		cell.textLabel.text = @"Scheme";
		cell.detailTextLabel.text = it[@"scheme"];
		cell.detailTextLabel.numberOfLines = 0;
		cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
		cell.detailTextLabel.textColor = UIColor.systemBlueColor;
		UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
		[btn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
		btn.frame = CGRectMake(0, 0, 36, 36);
		btn.tag = indexPath.section;
		[btn addTarget:self action:@selector(copySchemeFromButton:) forControlEvents:UIControlEventTouchUpInside];
		cell.accessoryView = btn;
		return cell;
	}
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.textLabel.text = @"复制本条";
	cell.textLabel.textColor = UIColor.systemBlueColor;
	cell.textLabel.textAlignment = NSTextAlignmentCenter;
	return cell;
}

- (void)copySchemeFromButton:(UIButton *)btn {
	NSInteger idx = btn.tag - 1;
	if (idx < 0 || idx >= (NSInteger)self.items.count) return;
	SBCopyString(self.items[idx][@"scheme"]);
	SBPresentCopiedToast(self, self.items[idx][@"title"]);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 0) return;
	NSDictionary *it = self.items[indexPath.section - 1];
	if (indexPath.row == 0 || indexPath.row == 1) {
		SBCopyString(it[@"scheme"]);
		SBPresentCopiedToast(self, it[@"title"]);
	}
}
@end
