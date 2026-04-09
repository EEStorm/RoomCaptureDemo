#import "CDVideoListViewController.h"
#import "CDCameraService.h"
#import <AVKit/AVKit.h>

@interface CDVideoListViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *videos;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *deleteAllButton;
@end

@implementation CDVideoListViewController

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat bottomBarHeight = 70.0;
    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;

    CGRect tableFrame = CGRectMake(0, 0, width, height - bottomBarHeight - insets.bottom);
    self.tableView.frame = tableFrame;
    self.bottomBar.frame = CGRectMake(0, CGRectGetMaxY(tableFrame), width, bottomBarHeight + insets.bottom);
    self.deleteAllButton.frame = CGRectMake(20, 12, self.bottomBar.bounds.size.width - 40, 46);
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.title = @"已录制视频";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                             target:self
                             action:@selector(dismissList)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    [self.view addSubview:self.tableView];

    self.bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.bottomBar.backgroundColor = [UIColor secondarySystemBackgroundColor];
    [self.view addSubview:self.bottomBar];

    self.deleteAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.deleteAllButton setTitle:@"一键删除所有" forState:UIControlStateNormal];
    self.deleteAllButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.deleteAllButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    self.deleteAllButton.layer.borderColor = [UIColor systemRedColor].CGColor;
    self.deleteAllButton.layer.borderWidth = 1.0;
    self.deleteAllButton.layer.cornerRadius = 8.0;
    [self.deleteAllButton addTarget:self action:@selector(confirmDeleteAll) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:self.deleteAllButton];

    [self loadVideos];
}

- (void)loadVideos {
    self.videos = [CDCameraService shared].recordedVideos;
    [self.tableView reloadData];
    self.deleteAllButton.enabled = self.videos.count > 0;
    self.deleteAllButton.alpha = self.deleteAllButton.enabled ? 1.0 : 0.4;
}

- (void)dismissList {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)confirmDeleteAll {
    if (self.videos.count == 0) {
        return;
    }
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"删除全部视频"
                                                                   message:@"此操作将删除所有已录制视频，无法恢复。确定要继续吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    __weak typeof(self) weakSelf = self;
    [alert addAction:[UIAlertAction actionWithTitle:@"删除" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[CDCameraService shared] deleteAllVideos];
        [weakSelf loadVideos];
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.videos.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *cellID = @"VideoCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
    }

    NSURL *url = self.videos[indexPath.row];
    cell.textLabel.text = url.lastPathComponent;
    cell.textLabel.font = [UIFont systemFontOfSize:14];

    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    NSNumber *size = attrs[NSFileSize];
    NSByteCountFormatter *formatter = [[NSByteCountFormatter alloc] init];
    cell.detailTextLabel.text = [formatter stringFromByteCount:size.longLongValue];
    cell.detailTextLabel.textColor = [UIColor grayColor];

    cell.imageView.image = [UIImage systemImageNamed:@"video.fill"];
    cell.imageView.tintColor = [UIColor systemBlueColor];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        NSURL *url = self.videos[indexPath.row];
        [[CDCameraService shared] deleteVideoAtURL:url];
        [self loadVideos];
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    NSURL *url = self.videos[indexPath.row];
    AVPlayerViewController *playerVC = [[AVPlayerViewController alloc] init];
    playerVC.player = [AVPlayer playerWithURL:url];
    [self presentViewController:playerVC animated:YES completion:^{
        [playerVC.player play];
    }];
}

@end
