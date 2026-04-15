#import "CDVideoListViewController.h"
#import "CDCameraService.h"
#import <AVKit/AVKit.h>
#import <Photos/Photos.h>

@interface CDVideoListViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *videos;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *deleteAllButton;
@property (nonatomic, strong) UIButton *saveAllButton;
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

    CGFloat buttonWidth = (self.bottomBar.bounds.size.width - 50) / 2;
    self.saveAllButton.frame = CGRectMake(20, 12, buttonWidth, 46);
    self.deleteAllButton.frame = CGRectMake(CGRectGetMaxX(self.saveAllButton.frame) + 10, 12, buttonWidth, 46);
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

    self.saveAllButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.saveAllButton setTitle:@"保存所有到相册" forState:UIControlStateNormal];
    self.saveAllButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.saveAllButton setTitleColor:[UIColor systemBlueColor] forState:UIControlStateNormal];
    self.saveAllButton.layer.borderColor = [UIColor systemBlueColor].CGColor;
    self.saveAllButton.layer.borderWidth = 1.0;
    self.saveAllButton.layer.cornerRadius = 8.0;
    [self.saveAllButton addTarget:self action:@selector(saveAllToAlbum) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:self.saveAllButton];

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
    self.saveAllButton.enabled = self.videos.count > 0;
    self.saveAllButton.alpha = self.saveAllButton.enabled ? 1.0 : 0.4;
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

- (void)saveAllToAlbum {
    if (self.videos.count == 0) {
        return;
    }
    __weak typeof(self) weakSelf = self;
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }
        if (status != PHAuthorizationStatusAuthorized) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) strongSelf2 = weakSelf;
                if (!strongSelf2) return;
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"无法保存"
                                                                               message:@"请在设置中允许访问相册"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [strongSelf2 presentViewController:alert animated:YES completion:nil];
            });
            return;
        }
        NSInteger count = strongSelf.videos.count;
        __block NSInteger savedCount = 0;
        for (NSURL *url in strongSelf.videos) {
            NSString *path = url.path;
            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:[NSURL fileURLWithPath:path]];
            } completionHandler:^(BOOL success, NSError *error) {
                __strong typeof(weakSelf) strongSelf3 = weakSelf;
                if (!strongSelf3) return;
                savedCount++;
                if (savedCount == count) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        __strong typeof(weakSelf) strongSelf4 = weakSelf;
                        if (!strongSelf4) return;
                        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存完成"
                                                                                       message:[NSString stringWithFormat:@"已保存 %ld 个视频到相册", (long)count]
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                        [strongSelf4 presentViewController:alert animated:YES completion:nil];
                    });
                }
            }];
        }
    }];
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
