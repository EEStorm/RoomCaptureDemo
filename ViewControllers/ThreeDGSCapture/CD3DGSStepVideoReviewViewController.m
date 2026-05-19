#import "CD3DGSStepVideoReviewViewController.h"
#import <AVKit/AVKit.h>

@interface CD3DGSStepVideoReviewViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, copy) NSArray<NSURL *> *videoURLs;
@property (nonatomic, copy) NSArray<NSString *> *stepTitles;
@property (nonatomic, strong) UITableView *tableView;

@end

@implementation CD3DGSStepVideoReviewViewController

- (instancetype)initWithVideoURLs:(NSArray<NSURL *> *)videoURLs {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _videoURLs = [videoURLs copy];
        _stepTitles = @[
            @"空间环绕扫描",
            @"全域推进拍摄",
            @"消除盲区拍摄",
            @"关键物品细节拍摄"
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"拍摄结果";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleInsetGrouped];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.tableView registerClass:UITableViewCell.class forCellReuseIdentifier:@"VideoCell"];
    [self.view addSubview:self.tableView];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.stepTitles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"VideoCell" forIndexPath:indexPath];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    UIListContentConfiguration *content = [cell defaultContentConfiguration];
    content.text = [NSString stringWithFormat:@"第%ld步：%@", (long)indexPath.row + 1, self.stepTitles[(NSUInteger)indexPath.row]];
    if ((NSUInteger)indexPath.row < self.videoURLs.count) {
        NSURL *url = self.videoURLs[(NSUInteger)indexPath.row];
        content.secondaryText = url.lastPathComponent;
        cell.userInteractionEnabled = YES;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else {
        content.secondaryText = @"未生成视频";
        cell.userInteractionEnabled = NO;
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    cell.contentConfiguration = content;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row >= self.videoURLs.count) {
        return;
    }

    AVPlayerViewController *playerVC = [[AVPlayerViewController alloc] init];
    playerVC.player = [AVPlayer playerWithURL:self.videoURLs[(NSUInteger)indexPath.row]];
    [self presentViewController:playerVC animated:YES completion:^{
        [playerVC.player play];
    }];
}

@end
