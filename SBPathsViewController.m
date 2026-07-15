#import "SBPathsViewController.h"
#import "SBContainerManager.h"
#import "SBCopyUtil.h"

@interface SBPathsViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *rows;
@end

@implementation SBPathsViewController

- (instancetype)init {
	return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"路径";
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 72;

	NSString *store = SBContainerManager.shared.storeRoot ?: @"-";
	NSString *home = NSHomeDirectory() ?: @"-";
	NSString *tmp = NSTemporaryDirectory() ?: @"-";
	NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject ?: @"-";

	self.rows = @[
		@{ @"title": @"备份根目录（SwitchBox）", @"value": store },
		@{ @"title": @"配置结构示例", @"value": [store stringByAppendingPathComponent:@"<BundleID>/profiles/<配置ID>/"] },
		@{ @"title": @"主容器数据", @"value": [store stringByAppendingPathComponent:@"<BundleID>/profiles/<配置ID>/Data/"] },
		@{ @"title": @"App Group 备份", @"value": [store stringByAppendingPathComponent:@"<BundleID>/profiles/<配置ID>/Groups/"] },
		@{ @"title": @"Keychain 备份文件", @"value": [store stringByAppendingPathComponent:@"<BundleID>/profiles/<配置ID>/keychain.plist"] },
		@{ @"title": @"本 App Home", @"value": home },
		@{ @"title": @"本 App Documents", @"value": docs },
		@{ @"title": @"临时目录", @"value": tmp },
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
		[s appendFormat:@"%@\n%@\n\n", r[@"title"], r[@"value"]];
	}
	SBCopyString(s);
	SBPresentCopiedToast(self, @"全部路径");
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 1; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return self.rows.count; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return @"常用路径";
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	return @"点路径文字或右侧复制按钮，即可复制到剪贴板。";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	NSDictionary *r = self.rows[indexPath.row];
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = r[@"title"];
	cell.detailTextLabel.text = r[@"value"];
	cell.detailTextLabel.numberOfLines = 0;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
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
