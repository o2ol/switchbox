#import "SBVersionViewController.h"
#import "SBCopyUtil.h"

@interface SBVersionViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@end

@implementation SBVersionViewController

- (instancetype)init {
	return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"版本信息";
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 56;

	NSDictionary *info = NSBundle.mainBundle.infoDictionary ?: @{};
	NSString *ver = info[@"CFBundleShortVersionString"] ?: @"-";
	NSString *build = info[@"CFBundleVersion"] ?: @"-";
	NSString *name = info[@"CFBundleDisplayName"] ?: info[@"CFBundleName"] ?: @"切号箱";
	NSString *bid = info[@"CFBundleIdentifier"] ?: @"com.o2ol.switchbox";
	NSString *minOS = info[@"MinimumOSVersion"] ?: @"15.0";
	NSString *exec = info[@"CFBundleExecutable"] ?: @"SwitchBox";

	self.rows = @[
		@{ @"title": @"显示名称", @"value": name },
		@{ @"title": @"版本号", @"value": ver },
		@{ @"title": @"Build", @"value": build },
		@{ @"title": @"完整版本", @"value": [NSString stringWithFormat:@"%@ (%@)", ver, build] },
		@{ @"title": @"Bundle ID", @"value": bid },
		@{ @"title": @"可执行文件", @"value": exec },
		@{ @"title": @"最低系统", @"value": [NSString stringWithFormat:@"iOS %@", minOS] },
		@{ @"title": @"分发方式", @"value": @"TrollStore (tipa/ipa)" },
		@{ @"title": @"1.2.0 更新", @"value": @"设备识别码可编辑 / 重生成" },
	];

	self.navigationItem.rightBarButtonItem =
		[[UIBarButtonItem alloc] initWithTitle:@"全部复制"
										 style:UIBarButtonItemStylePlain
										target:self
										action:@selector(copyAll)];
}

- (void)copyAll {
	NSMutableString *s = [NSMutableString string];
	for (NSDictionary *r in self.rows) {
		[s appendFormat:@"%@: %@\n", r[@"title"], r[@"value"]];
	}
	SBCopyString(s);
	SBPresentCopiedToast(self, @"版本信息");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return @"点任意一行复制对应值；右上角可复制全部。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *r = self.rows[indexPath.row];
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
	cell.textLabel.text = r[@"title"];
	cell.detailTextLabel.text = r[@"value"];
	cell.detailTextLabel.numberOfLines = 2;
	cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
	[btn setImage:[UIImage systemImageNamed:@"doc.on.doc"] forState:UIControlStateNormal];
	btn.frame = CGRectMake(0, 0, 36, 36);
	btn.tag = indexPath.row;
	[btn addTarget:self action:@selector(copyRow:) forControlEvents:UIControlEventTouchUpInside];
	cell.accessoryView = btn;
	return cell;
}

- (void)copyRow:(UIButton *)btn {
	if (btn.tag < 0 || btn.tag >= (NSInteger)self.rows.count) return;
	NSDictionary *r = self.rows[btn.tag];
	SBCopyString(r[@"value"]);
	SBPresentCopiedToast(self, r[@"title"]);
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSDictionary *r = self.rows[indexPath.row];
	SBCopyString(r[@"value"]);
	SBPresentCopiedToast(self, r[@"title"]);
}
@end
