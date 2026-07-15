#import "SBHelpViewController.h"
#import "SBCopyUtil.h"

@interface SBHelpViewController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *sections;
@end

@implementation SBHelpViewController

- (instancetype)init {
	return [self initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
	[super viewDidLoad];
	self.title = @"帮助说明";
	self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
	self.tableView.rowHeight = UITableViewAutomaticDimension;
	self.tableView.estimatedRowHeight = 96;

	self.sections = @[
		@{ @"title": @"这是什么", @"body":
			@"切号箱是轻量「多配置切号」工具。\n"
			@"给已安装 App 做多套本地数据存档，并支持一键替换。\n\n"
			@"不是 Crane：不能真正双开，也不能在桌面图标长按弹菜单。" },
		@{ @"title": @"工作原理", @"body":
			@"1. 关闭目标 App\n"
			@"2. 备份/恢复：完整数据容器 + App Group + Keychain\n"
			@"3. 再打开目标 App\n\n"
			@"换的是本地数据，App 本体不变。类似多存档。" },
		@{ @"title": @"正确上手", @"body":
			@"① 登录账号 A → 退后台\n"
			@"② 切号箱进入该 App → 从当前新建 → 命名 A\n"
			@"③ 需要新号时：点「新建空配置并重置识别码」\n"
			@"④ 打开 App 登录账号 B → 再「从当前新建」命名 B\n"
			@"⑤ 之后在列表切换 A / B\n\n"
			@"关键：每新建一套配置，都会把「当前配置」标记为它。\n"
			@"若旧配置切号无效，请删除后按上面流程重建。" },
		@{ @"title": @"重置设备识别码", @"body":
			@"新建空配置时可选择重置识别码：\n"
			@"• 清空目标沙盒 / App Group / 相关 Keychain\n"
			@"• 生成新的本地 device / vendor / advertising UUID\n"
			@"• 写入 App Preferences 常见字段，并清理 Cookies/WebKit 等会话残留\n\n"
			@"说明：纯巨魔无法注入系统 API，系统级 IDFV/IDFA 仍可能不变；\n"
			@"对读取自有存储识别码的 App，新号冷启动更干净。" },

		@{ @"title": @"界面操作", @"body":
			@"• 应用 Tab：点击进入管理；长按快速切号\n"
			@"• 配置页：新建 / 切换 / 重命名 / 删除 / 路径信息\n"
			@"• 设置 Tab：切换行为、备份选项、文档与版本" },
		@{ @"title": @"注意事项", @"body":
			@"• 先用小号验证，再用于重要账号\n"
			@"• 切换前尽量强制关闭目标 App\n"
			@"• 大 App 首次备份可能较慢\n"
			@"• Keychain / 服务端会话可能导致仍需重新登录\n"
			@"• 删除配置不可恢复" },
	];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return self.sections.count; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return 1; }
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
	return self.sections[section][@"title"];
}
- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
	if (section == self.sections.count - 1) return @"点任意正文可复制该段内容。";
	return nil;
}
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
	cell.textLabel.numberOfLines = 0;
	cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
	cell.textLabel.text = self.sections[indexPath.section][@"body"];
	cell.selectionStyle = UITableViewCellSelectionStyleDefault;
	return cell;
}
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
	[tableView deselectRowAtIndexPath:indexPath animated:YES];
	NSString *body = self.sections[indexPath.section][@"body"];
	SBCopyString(body);
	SBPresentCopiedToast(self, self.sections[indexPath.section][@"title"]);
}
@end
