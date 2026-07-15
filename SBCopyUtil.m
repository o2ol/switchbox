#import "SBCopyUtil.h"

void SBCopyString(NSString *text) {
	if (!text.length) return;
	UIPasteboard.generalPasteboard.string = text;
}

void SBPresentCopiedToast(UIViewController *vc, NSString *label) {
	NSString *msg = label.length ? [NSString stringWithFormat:@"已复制：%@", label] : @"已复制到剪贴板";
	UIAlertController *a = [UIAlertController alertControllerWithTitle:nil message:msg preferredStyle:UIAlertControllerStyleAlert];
	[vc presentViewController:a animated:YES completion:^{
		dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.85 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
			[a dismissViewControllerAnimated:YES completion:nil];
		});
	}];
}

UITableViewCell *SBMakePathCell(UITableView *tableView, NSString *title, NSString *path) {
	UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
	cell.textLabel.text = title;
	cell.detailTextLabel.text = path.length ? path : @"-";
	cell.detailTextLabel.numberOfLines = 0;
	cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
	cell.detailTextLabel.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
	cell.accessoryType = UITableViewCellAccessoryNone;
	// copy button
	UIImage *img = [UIImage systemImageNamed:@"doc.on.doc"];
	UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
	[btn setImage:img forState:UIControlStateNormal];
	btn.frame = CGRectMake(0, 0, 36, 36);
	btn.accessibilityLabel = @"复制";
	cell.accessoryView = btn;
	return cell;
}
