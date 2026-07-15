#import "SBAboutViewController.h"
#import "SBCopyUtil.h"

static NSString * const kSBOpenSourceURL = @"https://github.com/o2ol/switchbox";

@implementation SBAboutViewController

- (instancetype)init {
	return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"关于";
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 88;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 4; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	if (section == 3) return 2;
	return 1;
}
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	if (section == 0) return @"产品";
	if (section == 1) return @"定位";
	if (section == 2) return @"声明";
	return @"开源";
}

- (NSString *)bodyForSection:(NSInteger)section {
	if (section == 0) {
		return @"切号箱（SwitchBox）\n"
		@"轻量多配置容器切换工具\n"
		@"版本：1.2.0\n"
		@"Bundle：com.o2ol.switchbox\n"
		@"作者：o2ol";
	}
	if (section == 1) {
		return @"面向 TrollStore 环境。\n"
		@"通过备份/替换目标 App 的数据容器、App Group 与 Keychain 实现切号。\n"
		@"支持新建空配置并重置本地设备识别码种子。\n"
		@"不是越狱注入，也不是系统桌面菜单插件，不提供真正双开。";
	}
	if (section == 2) {
		return @"请仅在自有设备与合规场景使用。\n"
		@"不保证兼容所有 App，不保证绕过任何风控。\n"
		@"使用前建议先用测试账号验证。";
	}
	return @"";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	if (indexPath.section == 3) {
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
		if (indexPath.row == 0) {
			cell.textLabel.text = @"开源地址";
			cell.detailTextLabel.text = @"github.com/o2ol/switchbox";
			cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
			cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		} else {
			cell.textLabel.text = @"复制开源地址";
			cell.detailTextLabel.text = kSBOpenSourceURL;
			cell.detailTextLabel.numberOfLines = 2;
			cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
			cell.accessoryType = UITableViewCellAccessoryNone;
		}
		return cell;
	}
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.textLabel.numberOfLines = 0;
	cell.textLabel.text = [self bodyForSection:indexPath.section];
	return cell;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == 2) return @"点正文可复制该段。";
	if (section == 3) return @"源码托管于 GitHub，欢迎 Star / Issue / PR。";
	return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	if (indexPath.section == 3) {
		if (indexPath.row == 0) {
			NSURL *url = [NSURL URLWithString:kSBOpenSourceURL];
			if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
		} else {
			SBCopyString(kSBOpenSourceURL);
			SBPresentCopiedToast(self, @"开源地址");
		}
		return;
	}
	SBCopyString([self bodyForSection:indexPath.section]);
	SBPresentCopiedToast(self, @"关于");
}
@end
