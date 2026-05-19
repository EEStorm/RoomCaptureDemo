#import "CDRoomVideoReviewViewController.h"

#import "CDInsetLabel.h"
#import "CDRoomItem.h"
#import "../ThreeDGSCapture/CD3DGSCaptureViewController.h"
#import "../ThreeDGSCapture/CD3DGSTrainingResultSummary.h"
#import "../ThreeDGSCapture/CD3DGSTrainingResultViewController.h"

#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

@interface CDRoomVideoReviewViewController () {
    CDRoomItem *_room;
    NSURL *_remoteVideoURL;
    NSArray<NSURL *> *_videoURLs;
    NSInteger _selectedVideoIndex;
    BOOL _singleRoomDemoFlow;
    UIScrollView *_scrollView;
    UIView *_contentView;

    UILabel *_taskLabel;
    UILabel *_durLabel;

    UIView *_previewCard;
    UIView *_videoView;
    UIImageView *_coverImageView;
    UIButton *_playButton;
    UIStackView *_framesStack;
    NSMutableArray<UIControl *> *_frameControls;
    NSMutableArray<UIImageView *> *_frameImageViews;
    NSURLSessionDownloadTask *_downloadTask;

    AVPlayerItem *_currentPlayerItem;
    NSTimeInterval _pendingPlaySeconds;
    BOOL _shouldAutoPlayAfterDownload;
    NSInteger _thumbnailRequestID;
    NSInteger _selectedFrameIndex;
    NSTimeInterval _selectedSeconds;

    UIView *_backendCard;
    UILabel *_backendTitleLabel;
    CDInsetLabel *_backendStatusBadge;
    UILabel *_backendDimsLabel;
    UIView *_backendPendingView;
    UIActivityIndicatorView *_backendSpinner;
    UILabel *_backendPendingTitleLabel;
    UILabel *_backendPendingSubLabel;
    UILabel *_backendMessageLabel;

    UIView *_deviceCard;
    UILabel *_deviceTitleLabel;
    UILabel *_deviceSubtitleLabel;
    UILabel *_deviceSummaryLabel;
    UIStackView *_deviceTagStack;
    UIStackView *_deviceListStack;
    UIButton *_deviceExpandButton;
    BOOL _deviceExpandedAll;

    UIView *_bottomBar;
    UIButton *_leftBtn;
    UIButton *_rightBtn;
    NSLayoutConstraint *_bottomBarHeightConstraint;
}
@end

@implementation CDRoomVideoReviewViewController

- (instancetype)initWithRoom:(CDRoomItem *)room {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _room = room;
        _remoteVideoURL = [self.class demoVideoURLForRoom:room];
        _videoURLs = _remoteVideoURL ? @[_remoteVideoURL] : @[];
        _selectedVideoIndex = 0;
        _selectedFrameIndex = 1;
        _selectedSeconds = 12;
    }
    return self;
}

- (instancetype)initWithRoom:(CDRoomItem *)room videoURLs:(NSArray<NSURL *> *)videoURLs {
    return [self initWithRoom:room videoURLs:videoURLs singleRoomDemoFlow:NO];
}

- (instancetype)initWithRoom:(CDRoomItem *)room videoURLs:(NSArray<NSURL *> *)videoURLs singleRoomDemoFlow:(BOOL)singleRoomDemoFlow {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _room = room;
        _videoURLs = [videoURLs copy] ?: @[];
        _remoteVideoURL = _videoURLs.firstObject;
        _selectedVideoIndex = 0;
        _selectedFrameIndex = 0;
        _selectedSeconds = 0;
        _singleRoomDemoFlow = singleRoomDemoFlow;
    }
    return self;
}

+ (NSURL *)demoVideoURLForRoom:(CDRoomItem *)room {
    NSArray<NSString *> *urls = @[
        @"https://storage.lianjia.com/test/95c6cab4-4ca6-415b-ac4f-4356e8e8d9cb.MP4",
        @"https://storage.lianjia.com/test/3593d7af-e771-4f15-a1df-1608dbe8bded.MP4",
        @"https://storage.lianjia.com/test/525b8382-8852-4f1a-b2ed-2d591913bf45.MP4",
        @"https://storage.lianjia.com/test/6489177f-8412-4d1c-b548-afc35e00b21c.MP4",
        @"https://storage.lianjia.com/test/93258ff0-edf4-449e-9f40-1d369731844f.MP4",
        @"https://storage.lianjia.com/test/d7e8a4c5-96b0-4679-ba8b-171c75132451.MP4",
        @"https://storage.lianjia.com/test/63eca276-e762-42f5-8916-c549a921d3e1.MP4",
        @"https://storage.lianjia.com/test/526bc121-1243-4af0-9fc5-27ab4982350e.MP4",
        @"https://storage.lianjia.com/test/611fddd8-faf6-4298-ba98-b78a4272c2eb.MP4",
        @"https://storage.lianjia.com/test/2dadce15-e0dd-4467-b61f-cab68845bd3c.MP4",
        @"https://storage.lianjia.com/test/1c680a70-9b9e-4934-a637-57a9dec4ba47.MP4",
        @"https://storage.lianjia.com/test/651052b0-83e4-4a5a-bc4c-013a315cfa5a.MP4"
    ];

    NSInteger idx = 0;
    if ([room.roomId respondsToSelector:@selector(integerValue)]) {
        NSInteger value = room.roomId.integerValue;
        if (value > 0) {
            idx = (value - 1) % urls.count;
        }
    }
    return [NSURL URLWithString:urls[idx]];
}

- (NSURL *)localVideoURL {
    NSURL *selectedURL = [self selectedVideoURL];
    if (selectedURL.isFileURL) {
        return selectedURL;
    }

    NSString *cacheRoot = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DemoVideoCache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheRoot withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *roomKey = _room.roomId.length > 0 ? _room.roomId : @"unknown";
    NSString *fileName = [NSString stringWithFormat:@"room_%@_%ld.mp4", roomKey, (long)_selectedVideoIndex];
    return [NSURL fileURLWithPath:[cacheRoot stringByAppendingPathComponent:fileName]];
}

- (NSURL *)selectedVideoURL {
    if (_selectedVideoIndex >= 0 && _selectedVideoIndex < (NSInteger)_videoURLs.count) {
        return _videoURLs[(NSUInteger)_selectedVideoIndex];
    }
    return _remoteVideoURL;
}

- (BOOL)isVideoCached {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self localVideoURL].path];
}

- (void)startDownloadIfNeeded {
    NSURL *downloadURL = [self selectedVideoURL];
    if (!downloadURL || downloadURL.isFileURL || [self isVideoCached] || _downloadTask != nil) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    _downloadTask = [[NSURLSession sharedSession] downloadTaskWithURL:downloadURL completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) {
            return;
        }

        NSURL *destURL = [self localVideoURL];
        if (location && !error) {
            [[NSFileManager defaultManager] removeItemAtURL:destURL error:nil];
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:destURL error:nil];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self->_downloadTask = nil;
            if ([self isVideoCached]) {
                if (self->_shouldAutoPlayAfterDownload) {
                    self->_shouldAutoPlayAfterDownload = NO;
                    [self playLocalVideoWithSeekSeconds:self->_pendingPlaySeconds];
                }
                [self generateVideoThumbnailsIfNeeded];
            } else {
                self->_shouldAutoPlayAfterDownload = NO;
                (void)error;
            }
        });
        (void)response;
    }];
    [_downloadTask resume];
}

- (void)playLocalVideoWithSeekSeconds:(NSTimeInterval)seconds {
    NSURL *playURL = [self localVideoURL];
    if (!playURL || ![[NSFileManager defaultManager] fileExistsAtPath:playURL.path]) {
        [self showSimpleAlertWithTitle:@"未缓存完成" message:@"视频正在下载，稍后会自动播放"];
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:playURL];
    if (_currentPlayerItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_currentPlayerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:_currentPlayerItem];
    }
    _currentPlayerItem = item;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerStalled:) name:AVPlayerItemPlaybackStalledNotification object:item];

    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc] init];
    playerViewController.player = player;
    [self presentViewController:playerViewController animated:YES completion:^{
        if (seconds > 0) {
            CMTime time = CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC);
            [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                [player play];
                (void)finished;
            }];
        } else {
            [player play];
        }
    }];
}

- (void)playRemoteVideoWithSeekSeconds:(NSTimeInterval)seconds {
    NSURL *playURL = [self selectedVideoURL];
    if (!playURL) {
        [self showSimpleAlertWithTitle:@"无法播放" message:@"缺少视频地址"];
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:playURL];
    if (_currentPlayerItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_currentPlayerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:_currentPlayerItem];
    }
    _currentPlayerItem = item;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerStalled:) name:AVPlayerItemPlaybackStalledNotification object:item];

    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    AVPlayerViewController *playerViewController = [[AVPlayerViewController alloc] init];
    playerViewController.player = player;
    [self presentViewController:playerViewController animated:YES completion:^{
        if (seconds > 0) {
            CMTime time = CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC);
            [player seekToTime:time toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                [player play];
                (void)finished;
            }];
        } else {
            [player play];
        }
    }];
}

- (void)ensureDownloadAndPlaySeconds:(NSTimeInterval)seconds {
    _pendingPlaySeconds = seconds;
    if ([self isVideoCached]) {
        [self playLocalVideoWithSeekSeconds:seconds];
        return;
    }

    [self playRemoteVideoWithSeekSeconds:seconds];
    _shouldAutoPlayAfterDownload = NO;
    [self startDownloadIfNeeded];
}

- (void)playerFailed:(NSNotification *)note {
    NSError *error = _currentPlayerItem.error;
    NSString *message = error.localizedDescription.length > 0 ? error.localizedDescription : @"播放失败，请检查网络或稍后重试";
    [self showSimpleAlertWithTitle:@"播放失败" message:message];
    (void)note;
}

- (void)playerStalled:(NSNotification *)note {
    (void)note;
}

- (void)showSimpleAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
    self.title = [NSString stringWithFormat:@"%@ · 素材与校验", _room.roomName ?: @""];

    [self setupNavigationBarAppearance];
    [self setupBottomBar];
    [self setupScrollContent];
    [self applyRoomState];
}

- (void)dealloc {
    if (_currentPlayerItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_currentPlayerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:_currentPlayerItem];
    }
}

- (void)setupNavigationBarAppearance {
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor whiteColor];
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:17]
        };
        appearance.shadowColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
        self.navigationController.navigationBar.tintColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    }
}

- (void)setupBottomBar {
    _bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    _bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    _bottomBar.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:_bottomBar];

    _bottomBarHeightConstraint = [_bottomBar.heightAnchor constraintEqualToConstant:84];
    [NSLayoutConstraint activateConstraints:@[
        [_bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        _bottomBarHeightConstraint
    ]];

    UIView *topLine = [[UIView alloc] initWithFrame:CGRectZero];
    topLine.translatesAutoresizingMaskIntoConstraints = NO;
    topLine.backgroundColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
    [_bottomBar addSubview:topLine];
    [NSLayoutConstraint activateConstraints:@[
        [topLine.leadingAnchor constraintEqualToAnchor:_bottomBar.leadingAnchor],
        [topLine.trailingAnchor constraintEqualToAnchor:_bottomBar.trailingAnchor],
        [topLine.topAnchor constraintEqualToAnchor:_bottomBar.topAnchor],
        [topLine.heightAnchor constraintEqualToConstant:1]
    ]];

    _leftBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _leftBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _leftBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    _leftBtn.layer.cornerRadius = 10;
    _leftBtn.clipsToBounds = YES;
    _leftBtn.layer.borderWidth = 1;
    _leftBtn.layer.borderColor = [UIColor colorWithRed:216/255.0 green:216/255.0 blue:216/255.0 alpha:1.0].CGColor;
    [_leftBtn setTitleColor:[UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0] forState:UIControlStateNormal];
    _leftBtn.backgroundColor = [UIColor whiteColor];
    [_leftBtn setTitle:@"重录此房间" forState:UIControlStateNormal];
    [_leftBtn addTarget:self action:@selector(leftAction) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_leftBtn];

    _rightBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    _rightBtn.translatesAutoresizingMaskIntoConstraints = NO;
    _rightBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    _rightBtn.layer.cornerRadius = 10;
    _rightBtn.clipsToBounds = YES;
    _rightBtn.backgroundColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    [_rightBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [_rightBtn setTitle:@"补拍视频" forState:UIControlStateNormal];
    [_rightBtn addTarget:self action:@selector(rightAction) forControlEvents:UIControlEventTouchUpInside];
    [_bottomBar addSubview:_rightBtn];

    [NSLayoutConstraint activateConstraints:@[
        [_leftBtn.leadingAnchor constraintEqualToAnchor:_bottomBar.leadingAnchor constant:16],
        [_leftBtn.topAnchor constraintEqualToAnchor:_bottomBar.topAnchor constant:10],
        [_leftBtn.heightAnchor constraintEqualToConstant:48],

        [_rightBtn.trailingAnchor constraintEqualToAnchor:_bottomBar.trailingAnchor constant:-16],
        [_rightBtn.topAnchor constraintEqualToAnchor:_bottomBar.topAnchor constant:10],
        [_rightBtn.heightAnchor constraintEqualToConstant:48],

        [_leftBtn.trailingAnchor constraintEqualToAnchor:_rightBtn.leadingAnchor constant:-10],
        [_leftBtn.widthAnchor constraintEqualToAnchor:_rightBtn.widthAnchor]
    ]];

    [self updateBottomBarHeight];
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateBottomBarHeight];
}

- (void)updateBottomBarHeight {
    CGFloat bottomHeight = 84;
    if (@available(iOS 11.0, *)) {
        bottomHeight += self.view.safeAreaInsets.bottom;
    }
    _bottomBarHeightConstraint.constant = bottomHeight;
}

- (void)setupScrollContent {
    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    _scrollView.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0, *)) {
        _scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.view addSubview:_scrollView];

    _contentView = [[UIView alloc] initWithFrame:CGRectZero];
    _contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [_scrollView addSubview:_contentView];

    [NSLayoutConstraint activateConstraints:@[
        [_scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_scrollView.bottomAnchor constraintEqualToAnchor:_bottomBar.topAnchor],

        [_contentView.topAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.topAnchor],
        [_contentView.leadingAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.leadingAnchor],
        [_contentView.trailingAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.trailingAnchor],
        [_contentView.bottomAnchor constraintEqualToAnchor:_scrollView.contentLayoutGuide.bottomAnchor],
        [_contentView.widthAnchor constraintEqualToAnchor:_scrollView.frameLayoutGuide.widthAnchor]
    ]];

    UIView *metaRow = [[UIView alloc] initWithFrame:CGRectZero];
    metaRow.translatesAutoresizingMaskIntoConstraints = NO;
    [_contentView addSubview:metaRow];
    [NSLayoutConstraint activateConstraints:@[
        [metaRow.topAnchor constraintEqualToAnchor:_contentView.topAnchor constant:12],
        [metaRow.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:16],
        [metaRow.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-16],
        [metaRow.heightAnchor constraintEqualToConstant:22]
    ]];

    _taskLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _taskLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _taskLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightHeavy];
    _taskLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    _taskLabel.text = _room.roomName ?: @"";
    [metaRow addSubview:_taskLabel];

    _durLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _durLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _durLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightHeavy];
    _durLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    _durLabel.text = _videoURLs.count > 1 ? [NSString stringWithFormat:@"%ld段素材", (long)_videoURLs.count] : @"02:42";
    [metaRow addSubview:_durLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_taskLabel.leadingAnchor constraintEqualToAnchor:metaRow.leadingAnchor],
        [_taskLabel.centerYAnchor constraintEqualToAnchor:metaRow.centerYAnchor],
        [_durLabel.trailingAnchor constraintEqualToAnchor:metaRow.trailingAnchor],
        [_durLabel.centerYAnchor constraintEqualToAnchor:metaRow.centerYAnchor],
        [_taskLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_durLabel.leadingAnchor constant:-12]
    ]];

    _previewCard = [[UIView alloc] initWithFrame:CGRectZero];
    _previewCard.translatesAutoresizingMaskIntoConstraints = NO;
    _previewCard.backgroundColor = [UIColor whiteColor];
    _previewCard.layer.cornerRadius = 12;
    _previewCard.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1].CGColor;
    _previewCard.layer.shadowOpacity = 0.08;
    _previewCard.layer.shadowOffset = CGSizeMake(0, 1);
    _previewCard.layer.shadowRadius = 4;
    [_contentView addSubview:_previewCard];

    [NSLayoutConstraint activateConstraints:@[
        [_previewCard.topAnchor constraintEqualToAnchor:metaRow.bottomAnchor constant:12],
        [_previewCard.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:16],
        [_previewCard.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-16]
    ]];

    UIView *previewInner = [[UIView alloc] initWithFrame:CGRectZero];
    previewInner.translatesAutoresizingMaskIntoConstraints = NO;
    [_previewCard addSubview:previewInner];
    [NSLayoutConstraint activateConstraints:@[
        [previewInner.leadingAnchor constraintEqualToAnchor:_previewCard.leadingAnchor constant:12],
        [previewInner.trailingAnchor constraintEqualToAnchor:_previewCard.trailingAnchor constant:-12],
        [previewInner.topAnchor constraintEqualToAnchor:_previewCard.topAnchor constant:12],
        [previewInner.bottomAnchor constraintEqualToAnchor:_previewCard.bottomAnchor constant:-12]
    ]];

    _videoView = [[UIView alloc] initWithFrame:CGRectZero];
    _videoView.translatesAutoresizingMaskIntoConstraints = NO;
    _videoView.layer.cornerRadius = 12;
    _videoView.clipsToBounds = YES;
    _videoView.backgroundColor = [UIColor colorWithRed:74/255.0 green:79/255.0 blue:92/255.0 alpha:1.0];
    [previewInner addSubview:_videoView];
    [NSLayoutConstraint activateConstraints:@[
        [_videoView.leadingAnchor constraintEqualToAnchor:previewInner.leadingAnchor],
        [_videoView.trailingAnchor constraintEqualToAnchor:previewInner.trailingAnchor],
        [_videoView.topAnchor constraintEqualToAnchor:previewInner.topAnchor],
        [_videoView.heightAnchor constraintEqualToConstant:200]
    ]];

    _coverImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    _coverImageView.translatesAutoresizingMaskIntoConstraints = NO;
    _coverImageView.contentMode = UIViewContentModeScaleAspectFill;
    _coverImageView.clipsToBounds = YES;
    _coverImageView.backgroundColor = [UIColor clearColor];
    [_videoView addSubview:_coverImageView];
    [NSLayoutConstraint activateConstraints:@[
        [_coverImageView.leadingAnchor constraintEqualToAnchor:_videoView.leadingAnchor],
        [_coverImageView.trailingAnchor constraintEqualToAnchor:_videoView.trailingAnchor],
        [_coverImageView.topAnchor constraintEqualToAnchor:_videoView.topAnchor],
        [_coverImageView.bottomAnchor constraintEqualToAnchor:_videoView.bottomAnchor]
    ]];

    _playButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playButton.translatesAutoresizingMaskIntoConstraints = NO;
    _playButton.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    _playButton.layer.cornerRadius = 28;
    _playButton.layer.borderWidth = 1;
    _playButton.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    [_playButton setImage:[UIImage systemImageNamed:@"video"] forState:UIControlStateNormal];
    _playButton.tintColor = [UIColor whiteColor];
    [_playButton addTarget:self action:@selector(playTapped) forControlEvents:UIControlEventTouchUpInside];
    [_videoView addSubview:_playButton];
    [NSLayoutConstraint activateConstraints:@[
        [_playButton.centerXAnchor constraintEqualToAnchor:_videoView.centerXAnchor],
        [_playButton.centerYAnchor constraintEqualToAnchor:_videoView.centerYAnchor],
        [_playButton.widthAnchor constraintEqualToConstant:56],
        [_playButton.heightAnchor constraintEqualToConstant:56]
    ]];

    _framesStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    _framesStack.translatesAutoresizingMaskIntoConstraints = NO;
    _framesStack.axis = UILayoutConstraintAxisHorizontal;
    _framesStack.spacing = 8;
    _framesStack.distribution = UIStackViewDistributionFillEqually;
    [previewInner addSubview:_framesStack];
    [NSLayoutConstraint activateConstraints:@[
        [_framesStack.leadingAnchor constraintEqualToAnchor:previewInner.leadingAnchor],
        [_framesStack.trailingAnchor constraintEqualToAnchor:previewInner.trailingAnchor],
        [_framesStack.topAnchor constraintEqualToAnchor:_videoView.bottomAnchor constant:10],
        [_framesStack.heightAnchor constraintEqualToConstant:44],
        [_framesStack.bottomAnchor constraintEqualToAnchor:previewInner.bottomAnchor]
    ]];

    _frameControls = [NSMutableArray array];
    _frameImageViews = [NSMutableArray array];
    NSInteger frameCount = MAX((NSInteger)_videoURLs.count, 1);
    if (_videoURLs.count <= 1) {
        frameCount = 6;
    }
    for (NSInteger index = 0; index < frameCount; index++) {
        UIControl *frame = [[UIControl alloc] initWithFrame:CGRectZero];
        frame.backgroundColor = [UIColor colorWithRed:240/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
        frame.layer.cornerRadius = 8;
        frame.layer.borderWidth = 1;
        frame.layer.borderColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0].CGColor;
        frame.clipsToBounds = YES;
        frame.tag = index;
        [frame addTarget:self action:@selector(frameTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_frameControls addObject:frame];

        UIImageView *thumb = [[UIImageView alloc] initWithFrame:CGRectZero];
        thumb.translatesAutoresizingMaskIntoConstraints = NO;
        thumb.contentMode = UIViewContentModeScaleAspectFill;
        thumb.clipsToBounds = YES;
        thumb.backgroundColor = [UIColor colorWithRed:240/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
        [frame addSubview:thumb];
        [NSLayoutConstraint activateConstraints:@[
            [thumb.leadingAnchor constraintEqualToAnchor:frame.leadingAnchor],
            [thumb.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor],
            [thumb.topAnchor constraintEqualToAnchor:frame.topAnchor],
            [thumb.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor]
        ]];
        [_frameImageViews addObject:thumb];

        UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        timeLabel.translatesAutoresizingMaskIntoConstraints = NO;
        timeLabel.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
        timeLabel.textColor = [UIColor colorWithWhite:1 alpha:0.9];
        timeLabel.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        timeLabel.layer.cornerRadius = 2;
        timeLabel.clipsToBounds = YES;
        timeLabel.textAlignment = NSTextAlignmentCenter;
        timeLabel.text = _videoURLs.count > 1 ? [NSString stringWithFormat:@"第%ld步", (long)index + 1] : [NSString stringWithFormat:@"%lds", (long)(index * 12)];
        [frame addSubview:timeLabel];
        [NSLayoutConstraint activateConstraints:@[
            [timeLabel.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-3],
            [timeLabel.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor constant:-2],
            [timeLabel.heightAnchor constraintEqualToConstant:12]
        ]];

        [_framesStack addArrangedSubview:frame];
    }

    [self updateSelectedFrameUI];

    _backendCard = [[UIView alloc] initWithFrame:CGRectZero];
    _backendCard.translatesAutoresizingMaskIntoConstraints = NO;
    _backendCard.backgroundColor = [UIColor whiteColor];
    _backendCard.layer.cornerRadius = 12;
    _backendCard.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1].CGColor;
    _backendCard.layer.shadowOpacity = 0.08;
    _backendCard.layer.shadowOffset = CGSizeMake(0, 1);
    _backendCard.layer.shadowRadius = 4;
    [_contentView addSubview:_backendCard];

    [NSLayoutConstraint activateConstraints:@[
        [_backendCard.topAnchor constraintEqualToAnchor:_previewCard.bottomAnchor constant:12],
        [_backendCard.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:16],
        [_backendCard.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-16]
    ]];

    UIView *backendInner = [[UIView alloc] initWithFrame:CGRectZero];
    backendInner.translatesAutoresizingMaskIntoConstraints = NO;
    [_backendCard addSubview:backendInner];
    [NSLayoutConstraint activateConstraints:@[
        [backendInner.leadingAnchor constraintEqualToAnchor:_backendCard.leadingAnchor constant:12],
        [backendInner.trailingAnchor constraintEqualToAnchor:_backendCard.trailingAnchor constant:-12],
        [backendInner.topAnchor constraintEqualToAnchor:_backendCard.topAnchor constant:12],
        [_backendCard.bottomAnchor constraintEqualToAnchor:backendInner.bottomAnchor constant:12]
    ]];

    UIView *backendHead = [[UIView alloc] initWithFrame:CGRectZero];
    backendHead.translatesAutoresizingMaskIntoConstraints = NO;
    [backendInner addSubview:backendHead];
    [NSLayoutConstraint activateConstraints:@[
        [backendHead.leadingAnchor constraintEqualToAnchor:backendInner.leadingAnchor],
        [backendHead.trailingAnchor constraintEqualToAnchor:backendInner.trailingAnchor],
        [backendHead.topAnchor constraintEqualToAnchor:backendInner.topAnchor],
        [backendHead.heightAnchor constraintEqualToConstant:22]
    ]];

    _backendTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _backendTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _backendTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightHeavy];
    _backendTitleLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    _backendTitleLabel.text = @"质量检测结果（后端）";
    [backendHead addSubview:_backendTitleLabel];

    _backendStatusBadge = [[CDInsetLabel alloc] initWithFrame:CGRectZero];
    _backendStatusBadge.translatesAutoresizingMaskIntoConstraints = NO;
    _backendStatusBadge.font = [UIFont systemFontOfSize:12 weight:UIFontWeightHeavy];
    _backendStatusBadge.contentInsets = UIEdgeInsetsMake(4, 10, 4, 10);
    _backendStatusBadge.layer.cornerRadius = 11;
    _backendStatusBadge.clipsToBounds = YES;
    _backendStatusBadge.text = @"-";
    _backendStatusBadge.textAlignment = NSTextAlignmentCenter;
    [backendHead addSubview:_backendStatusBadge];

    [NSLayoutConstraint activateConstraints:@[
        [_backendTitleLabel.leadingAnchor constraintEqualToAnchor:backendHead.leadingAnchor],
        [_backendTitleLabel.centerYAnchor constraintEqualToAnchor:backendHead.centerYAnchor],
        [_backendStatusBadge.trailingAnchor constraintEqualToAnchor:backendHead.trailingAnchor],
        [_backendStatusBadge.centerYAnchor constraintEqualToAnchor:backendHead.centerYAnchor],
        [_backendTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_backendStatusBadge.leadingAnchor constant:-10],
        [_backendStatusBadge.heightAnchor constraintEqualToConstant:22]
    ]];

    _backendDimsLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _backendDimsLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _backendDimsLabel.font = [UIFont systemFontOfSize:12];
    _backendDimsLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    _backendDimsLabel.numberOfLines = 0;
    _backendDimsLabel.text = @"检查维度：空间可重建性 · 覆盖闭合 · 视差重叠 · 可跟踪性";

    UIStackView *backendPending = [[UIStackView alloc] initWithFrame:CGRectZero];
    backendPending.translatesAutoresizingMaskIntoConstraints = NO;
    backendPending.axis = UILayoutConstraintAxisHorizontal;
    backendPending.alignment = UIStackViewAlignmentCenter;
    backendPending.spacing = 10;
    _backendPendingView = backendPending;

    _backendSpinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _backendSpinner.translatesAutoresizingMaskIntoConstraints = NO;
    _backendSpinner.color = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    [_backendSpinner startAnimating];
    [backendPending addArrangedSubview:_backendSpinner];

    UIStackView *backendPendingInfo = [[UIStackView alloc] initWithFrame:CGRectZero];
    backendPendingInfo.translatesAutoresizingMaskIntoConstraints = NO;
    backendPendingInfo.axis = UILayoutConstraintAxisVertical;
    backendPendingInfo.spacing = 2;
    [backendPending addArrangedSubview:backendPendingInfo];

    _backendPendingTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _backendPendingTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _backendPendingTitleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightHeavy];
    _backendPendingTitleLabel.textColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    _backendPendingTitleLabel.text = @"质量检测中";
    [backendPendingInfo addArrangedSubview:_backendPendingTitleLabel];

    _backendPendingSubLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _backendPendingSubLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _backendPendingSubLabel.font = [UIFont systemFontOfSize:12];
    _backendPendingSubLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    _backendPendingSubLabel.text = @"预计 1 分钟内完成，请稍候…";
    [backendPendingInfo addArrangedSubview:_backendPendingSubLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_backendSpinner.widthAnchor constraintEqualToConstant:18],
        [_backendSpinner.heightAnchor constraintEqualToConstant:18]
    ]];

    _backendMessageLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _backendMessageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _backendMessageLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    _backendMessageLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    _backendMessageLabel.numberOfLines = 0;
    _backendMessageLabel.text = @"-";

    UIStackView *backendBodyStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    backendBodyStack.translatesAutoresizingMaskIntoConstraints = NO;
    backendBodyStack.axis = UILayoutConstraintAxisVertical;
    backendBodyStack.spacing = 10;
    [backendInner addSubview:backendBodyStack];
    [backendBodyStack addArrangedSubview:_backendDimsLabel];
    [backendBodyStack addArrangedSubview:backendPending];
    [backendBodyStack addArrangedSubview:_backendMessageLabel];

    [NSLayoutConstraint activateConstraints:@[
        [backendBodyStack.leadingAnchor constraintEqualToAnchor:backendInner.leadingAnchor],
        [backendBodyStack.trailingAnchor constraintEqualToAnchor:backendInner.trailingAnchor],
        [backendBodyStack.topAnchor constraintEqualToAnchor:backendHead.bottomAnchor constant:8],
        [backendBodyStack.bottomAnchor constraintEqualToAnchor:backendInner.bottomAnchor]
    ]];

    _deviceCard = [[UIView alloc] initWithFrame:CGRectZero];
    _deviceCard.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceCard.backgroundColor = [UIColor whiteColor];
    _deviceCard.layer.cornerRadius = 12;
    _deviceCard.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1].CGColor;
    _deviceCard.layer.shadowOpacity = 0.08;
    _deviceCard.layer.shadowOffset = CGSizeMake(0, 1);
    _deviceCard.layer.shadowRadius = 4;
    [_contentView addSubview:_deviceCard];

    [NSLayoutConstraint activateConstraints:@[
        [_deviceCard.topAnchor constraintEqualToAnchor:_backendCard.bottomAnchor constant:12],
        [_deviceCard.leadingAnchor constraintEqualToAnchor:_contentView.leadingAnchor constant:16],
        [_deviceCard.trailingAnchor constraintEqualToAnchor:_contentView.trailingAnchor constant:-16],
        [_deviceCard.bottomAnchor constraintEqualToAnchor:_contentView.bottomAnchor constant:-16]
    ]];

    UIView *deviceInner = [[UIView alloc] initWithFrame:CGRectZero];
    deviceInner.translatesAutoresizingMaskIntoConstraints = NO;
    [_deviceCard addSubview:deviceInner];
    [NSLayoutConstraint activateConstraints:@[
        [deviceInner.leadingAnchor constraintEqualToAnchor:_deviceCard.leadingAnchor constant:12],
        [deviceInner.trailingAnchor constraintEqualToAnchor:_deviceCard.trailingAnchor constant:-12],
        [deviceInner.topAnchor constraintEqualToAnchor:_deviceCard.topAnchor constant:12],
        [deviceInner.bottomAnchor constraintEqualToAnchor:_deviceCard.bottomAnchor constant:-12]
    ]];

    UIView *deviceHead = [[UIView alloc] initWithFrame:CGRectZero];
    deviceHead.translatesAutoresizingMaskIntoConstraints = NO;
    [deviceInner addSubview:deviceHead];
    [NSLayoutConstraint activateConstraints:@[
        [deviceHead.leadingAnchor constraintEqualToAnchor:deviceInner.leadingAnchor],
        [deviceHead.trailingAnchor constraintEqualToAnchor:deviceInner.trailingAnchor],
        [deviceHead.topAnchor constraintEqualToAnchor:deviceInner.topAnchor],
        [deviceHead.heightAnchor constraintEqualToConstant:22]
    ]];

    _deviceTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _deviceTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceTitleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightHeavy];
    _deviceTitleLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    _deviceTitleLabel.text = @"拍摄建议（参考）";
    [deviceHead addSubview:_deviceTitleLabel];

    _deviceSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _deviceSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceSubtitleLabel.font = [UIFont systemFontOfSize:12];
    _deviceSubtitleLabel.textColor = [UIColor colorWithRed:153/255.0 green:153/255.0 blue:153/255.0 alpha:1.0];
    _deviceSubtitleLabel.text = @"提高 3D 高斯重建成功率";
    [deviceHead addSubview:_deviceSubtitleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [_deviceTitleLabel.leadingAnchor constraintEqualToAnchor:deviceHead.leadingAnchor],
        [_deviceTitleLabel.centerYAnchor constraintEqualToAnchor:deviceHead.centerYAnchor],
        [_deviceSubtitleLabel.trailingAnchor constraintEqualToAnchor:deviceHead.trailingAnchor],
        [_deviceSubtitleLabel.centerYAnchor constraintEqualToAnchor:deviceHead.centerYAnchor],
        [_deviceTitleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:_deviceSubtitleLabel.leadingAnchor constant:-10]
    ]];

    _deviceSummaryLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    _deviceSummaryLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceSummaryLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    _deviceSummaryLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    _deviceSummaryLabel.numberOfLines = 0;
    _deviceSummaryLabel.text = @"-";
    [deviceInner addSubview:_deviceSummaryLabel];

    _deviceTagStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    _deviceTagStack.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceTagStack.axis = UILayoutConstraintAxisVertical;
    _deviceTagStack.spacing = 8;
    [deviceInner addSubview:_deviceTagStack];

    _deviceListStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    _deviceListStack.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceListStack.axis = UILayoutConstraintAxisVertical;
    _deviceListStack.spacing = 12;
    [deviceInner addSubview:_deviceListStack];

    _deviceExpandButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _deviceExpandButton.translatesAutoresizingMaskIntoConstraints = NO;
    _deviceExpandButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [_deviceExpandButton setTitleColor:[UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
    [_deviceExpandButton setTitle:@"展开查看更多建议 ›" forState:UIControlStateNormal];
    [_deviceExpandButton addTarget:self action:@selector(toggleDeviceExpanded:) forControlEvents:UIControlEventTouchUpInside];
    [deviceInner addSubview:_deviceExpandButton];

    [NSLayoutConstraint activateConstraints:@[
        [_deviceSummaryLabel.leadingAnchor constraintEqualToAnchor:deviceInner.leadingAnchor],
        [_deviceSummaryLabel.trailingAnchor constraintEqualToAnchor:deviceInner.trailingAnchor],
        [_deviceSummaryLabel.topAnchor constraintEqualToAnchor:deviceHead.bottomAnchor constant:10],

        [_deviceTagStack.leadingAnchor constraintEqualToAnchor:deviceInner.leadingAnchor],
        [_deviceTagStack.trailingAnchor constraintEqualToAnchor:deviceInner.trailingAnchor],
        [_deviceTagStack.topAnchor constraintEqualToAnchor:_deviceSummaryLabel.bottomAnchor constant:10],

        [_deviceListStack.leadingAnchor constraintEqualToAnchor:deviceInner.leadingAnchor],
        [_deviceListStack.trailingAnchor constraintEqualToAnchor:deviceInner.trailingAnchor],
        [_deviceListStack.topAnchor constraintEqualToAnchor:_deviceTagStack.bottomAnchor constant:10],

        [_deviceExpandButton.leadingAnchor constraintEqualToAnchor:deviceInner.leadingAnchor],
        [_deviceExpandButton.topAnchor constraintEqualToAnchor:_deviceListStack.bottomAnchor constant:10],
        [_deviceExpandButton.bottomAnchor constraintEqualToAnchor:deviceInner.bottomAnchor]
    ]];
}

- (void)updateSelectedFrameUI {
    UIColor *normalBorder = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
    UIColor *activeBorder = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:0.55];

    for (NSInteger index = 0; index < _frameControls.count; index++) {
        UIControl *control = _frameControls[index];
        control.layer.borderColor = (index == _selectedFrameIndex ? activeBorder : normalBorder).CGColor;
    }

    if (_selectedFrameIndex >= 0 && _selectedFrameIndex < (NSInteger)_frameImageViews.count) {
        UIImage *image = _frameImageViews[_selectedFrameIndex].image;
        if (image) {
            _coverImageView.image = image;
        }
    }
}

- (void)generateVideoThumbnailsIfNeeded {
    if (!_room.captureComplete) {
        return;
    }

    if (_videoURLs.count > 1) {
        [self generateCapturedVideoThumbnailsIfNeeded];
        return;
    }

    NSURL *assetURL = [self isVideoCached] ? [self localVideoURL] : [self selectedVideoURL];
    if (!assetURL) {
        return;
    }

    _thumbnailRequestID += 1;
    NSInteger requestID = _thumbnailRequestID;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(720, 720);
    generator.requestedTimeToleranceBefore = kCMTimeZero;
    generator.requestedTimeToleranceAfter = kCMTimeZero;

    NSMutableArray<NSValue *> *times = [NSMutableArray array];
    for (NSInteger index = 0; index < 6; index++) {
        CMTime time = CMTimeMakeWithSeconds(index * 12.0, NSEC_PER_SEC);
        [times addObject:[NSValue valueWithCMTime:time]];
    }

    __weak typeof(self) weakSelf = self;
    [generator generateCGImagesAsynchronouslyForTimes:times completionHandler:^(CMTime requestedTime, CGImageRef  _Nullable cgImage, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || self->_thumbnailRequestID != requestID || result != AVAssetImageGeneratorSucceeded || !cgImage) {
            return;
        }

        UIImage *image = [UIImage imageWithCGImage:cgImage];
        NSInteger index = (NSInteger)llround(CMTimeGetSeconds(requestedTime) / 12.0);
        if (index < 0) {
            index = 0;
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_thumbnailRequestID != requestID) {
                return;
            }
            if (index >= 0 && index < (NSInteger)self->_frameImageViews.count) {
                self->_frameImageViews[index].image = image;
            }
            if (index == self->_selectedFrameIndex) {
                self->_coverImageView.image = image;
            } else if (!self->_coverImageView.image && index == 0) {
                self->_coverImageView.image = image;
            }
        });
        (void)actualTime;
        (void)error;
    }];
}

- (void)generateCapturedVideoThumbnailsIfNeeded {
    _thumbnailRequestID += 1;
    NSInteger requestID = _thumbnailRequestID;

    for (NSInteger index = 0; index < (NSInteger)_videoURLs.count; index++) {
        NSURL *assetURL = _videoURLs[(NSUInteger)index];
        if (!assetURL) {
            continue;
        }

        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
        AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
        generator.appliesPreferredTrackTransform = YES;
        generator.maximumSize = CGSizeMake(720, 720);
        generator.requestedTimeToleranceBefore = kCMTimeZero;
        generator.requestedTimeToleranceAfter = kCMTimeZero;
        NSArray<NSValue *> *times = @[[NSValue valueWithCMTime:CMTimeMakeWithSeconds(0.1, NSEC_PER_SEC)]];

        __weak typeof(self) weakSelf = self;
        [generator generateCGImagesAsynchronouslyForTimes:times completionHandler:^(CMTime requestedTime, CGImageRef  _Nullable cgImage, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * _Nullable error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || self->_thumbnailRequestID != requestID || result != AVAssetImageGeneratorSucceeded || !cgImage) {
                return;
            }

            UIImage *image = [UIImage imageWithCGImage:cgImage];
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self->_thumbnailRequestID != requestID || index >= (NSInteger)self->_frameImageViews.count) {
                    return;
                }
                self->_frameImageViews[(NSUInteger)index].image = image;
                if (index == self->_selectedVideoIndex) {
                    self->_coverImageView.image = image;
                }
            });
            (void)requestedTime;
            (void)actualTime;
            (void)error;
        }];
    }
}

- (NSInteger)nearestFrameIndexForSeconds:(NSTimeInterval)seconds {
    if (_videoURLs.count > 1) {
        return _selectedVideoIndex;
    }

    NSInteger index = (NSInteger)llround(seconds / 12.0);
    if (index < 0) {
        index = 0;
    }
    if (index > 5) {
        index = 5;
    }
    return index;
}

- (NSString *)mmssForSeconds:(NSInteger)seconds {
    NSInteger safeSeconds = MAX(0, seconds);
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(safeSeconds / 60), (long)(safeSeconds % 60)];
}

- (CDInsetLabel *)pillForLevel:(NSString *)level {
    UIColor *success = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
    UIColor *successBackground = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
    UIColor *warning = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:1.0];
    UIColor *warningBackground = [UIColor colorWithRed:255/255.0 green:243/255.0 blue:224/255.0 alpha:1.0];
    UIColor *error = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    UIColor *errorBackground = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];

    CDInsetLabel *pill = [[CDInsetLabel alloc] initWithFrame:CGRectZero];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.font = [UIFont systemFontOfSize:12 weight:UIFontWeightHeavy];
    pill.contentInsets = UIEdgeInsetsMake(4, 10, 4, 10);
    pill.layer.cornerRadius = 11;
    pill.clipsToBounds = YES;
    pill.textAlignment = NSTextAlignmentCenter;

    if ([level isEqualToString:@"risk"]) {
        pill.text = @"建议处理";
        pill.textColor = error;
        pill.backgroundColor = errorBackground;
    } else if ([level isEqualToString:@"warn"]) {
        pill.text = @"可优化";
        pill.textColor = warning;
        pill.backgroundColor = warningBackground;
    } else {
        pill.text = @"正常";
        pill.textColor = success;
        pill.backgroundColor = successBackground;
    }
    return pill;
}

- (CDInsetLabel *)tagForText:(NSString *)text level:(NSString *)level {
    UIColor *brand = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    UIColor *brandBackground = [UIColor colorWithRed:224/255.0 green:237/255.0 blue:255/255.0 alpha:1.0];
    UIColor *success = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
    UIColor *successBackground = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
    UIColor *warning = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:1.0];
    UIColor *warningBackground = [UIColor colorWithRed:255/255.0 green:243/255.0 blue:224/255.0 alpha:1.0];
    UIColor *error = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    UIColor *errorBackground = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];

    CDInsetLabel *tag = [[CDInsetLabel alloc] initWithFrame:CGRectZero];
    tag.translatesAutoresizingMaskIntoConstraints = NO;
    tag.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    tag.contentInsets = UIEdgeInsetsMake(4, 10, 4, 10);
    tag.layer.cornerRadius = 11;
    tag.clipsToBounds = YES;
    tag.text = text ?: @"";

    if ([level isEqualToString:@"risk"]) {
        tag.textColor = error;
        tag.backgroundColor = errorBackground;
    } else if ([level isEqualToString:@"warn"]) {
        tag.textColor = warning;
        tag.backgroundColor = warningBackground;
    } else if ([level isEqualToString:@"brand"]) {
        tag.textColor = brand;
        tag.backgroundColor = brandBackground;
    } else {
        tag.textColor = success;
        tag.backgroundColor = successBackground;
    }
    return tag;
}

- (UIView *)deviceRowForItem:(NSDictionary *)item {
    UIColor *brand = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];

    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *verticalStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    verticalStack.translatesAutoresizingMaskIntoConstraints = NO;
    verticalStack.axis = UILayoutConstraintAxisVertical;
    verticalStack.spacing = 4;
    [row addSubview:verticalStack];
    [NSLayoutConstraint activateConstraints:@[
        [verticalStack.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [verticalStack.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [verticalStack.topAnchor constraintEqualToAnchor:row.topAnchor],
        [verticalStack.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]
    ]];

    UIStackView *topRow = [[UIStackView alloc] initWithFrame:CGRectZero];
    topRow.axis = UILayoutConstraintAxisHorizontal;
    topRow.alignment = UIStackViewAlignmentCenter;
    topRow.spacing = 8;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    titleLabel.text = item[@"title"] ?: @"";
    [topRow addArrangedSubview:titleLabel];

    UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
    [topRow addArrangedSubview:spacer];

    NSString *level = item[@"level"] ?: @"ok";
    [topRow addArrangedSubview:[self pillForLevel:level]];

    NSNumber *time = item[@"time"];
    if ([time isKindOfClass:[NSNumber class]]) {
        UIButton *locateButton = [UIButton buttonWithType:UIButtonTypeSystem];
        locateButton.translatesAutoresizingMaskIntoConstraints = NO;
        locateButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        [locateButton setTitleColor:brand forState:UIControlStateNormal];
        locateButton.contentEdgeInsets = UIEdgeInsetsMake(4, 6, 4, 6);
        locateButton.layer.cornerRadius = 8;
        locateButton.backgroundColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:0.08];
        locateButton.tag = time.integerValue;
        [locateButton setTitle:[NSString stringWithFormat:@"定位 %@", [self mmssForSeconds:time.integerValue]] forState:UIControlStateNormal];
        [locateButton addTarget:self action:@selector(locateTapped:) forControlEvents:UIControlEventTouchUpInside];
        [topRow addArrangedSubview:locateButton];
    }

    [verticalStack addArrangedSubview:topRow];

    NSString *impact = item[@"impact"];
    if (impact.length > 0) {
        UILabel *impactLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        impactLabel.font = [UIFont systemFontOfSize:12];
        impactLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
        impactLabel.numberOfLines = 0;
        impactLabel.text = impact;
        [verticalStack addArrangedSubview:impactLabel];
    }

    NSString *howTo = item[@"howto"];
    if (howTo.length > 0) {
        UILabel *howToLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        howToLabel.font = [UIFont systemFontOfSize:12];
        howToLabel.textColor = [UIColor colorWithRed:153/255.0 green:153/255.0 blue:153/255.0 alpha:1.0];
        howToLabel.numberOfLines = 0;
        howToLabel.text = howTo;
        [verticalStack addArrangedSubview:howToLabel];
    }

    return row;
}

- (NSArray<NSDictionary *> *)actionableItemsFromItems:(NSArray<NSDictionary *> *)items {
    NSMutableArray<NSDictionary *> *result = [NSMutableArray array];
    for (NSDictionary *item in items) {
        NSString *level = item[@"level"];
        if ([level isEqualToString:@"risk"] || [level isEqualToString:@"warn"]) {
            [result addObject:item];
        }
    }
    return result;
}

- (NSArray<NSDictionary *> *)topIssueTagsFromItems:(NSArray<NSDictionary *> *)items maxCount:(NSInteger)maxCount {
    NSArray<NSDictionary *> *actionableItems = [self actionableItemsFromItems:items];
    NSMutableArray<NSDictionary *> *tags = [NSMutableArray array];

    for (NSString *level in @[@"risk", @"warn"]) {
        for (NSDictionary *item in actionableItems) {
            if (tags.count >= maxCount) {
                break;
            }
            if (![item[@"level"] isEqualToString:level]) {
                continue;
            }
            NSString *title = item[@"title"];
            if (title.length == 0) {
                continue;
            }
            [tags addObject:@{@"text": title, @"level": level}];
        }
        if (tags.count >= maxCount) {
            break;
        }
    }
    return tags;
}

- (NSArray<NSDictionary *> *)demoDeviceCheckItemsForRoom {
    if (!_room.captureComplete) {
        return @[
            @{
                @"title": @"未采集",
                @"level": @"warn",
                @"impact": @"未采集｜请先完成采集后再查看拍摄建议",
                @"howto": @"怎么做：按引导完成该房间采集后再提交审核"
            }
        ];
    }

    if (_room.auditStatus == 2) {
        return @[
            @{@"title": @"走得偏快", @"level": @"warn", @"impact": @"可能影响：重建有断层/漂移", @"howto": @"怎么做：放慢移动，每段停 0.5 秒再继续", @"time": @(8)}
        ];
    }

    if (_room.auditStatus == 1) {
        return @[
            @{@"title": @"走得偏快", @"level": @"warn", @"impact": @"可能影响：重建有断层/漂移", @"howto": @"怎么做：放慢移动，每段停 0.5 秒再继续", @"time": @(8)},
            @{@"title": @"手有点抖", @"level": @"warn", @"impact": @"可能影响：画面跟不住，重建会“飘”", @"howto": @"怎么做：双手握持，贴近身体慢走；必要时靠墙借力", @"time": @(24)}
        ];
    }

    return @[
        @{@"title": @"手抖明显", @"level": @"risk", @"impact": @"可能影响：画面跟不住，重建会“飘”", @"howto": @"怎么做：双手握持，贴近身体慢走；必要时靠墙借力", @"time": @(24)},
        @{@"title": @"光线偏暗", @"level": @"risk", @"impact": @"可能影响：细节看不清，训练不稳定", @"howto": @"怎么做：开灯/拉窗帘/靠近光源；避免背光", @"time": @(12)},
        @{@"title": @"走得偏快", @"level": @"warn", @"impact": @"可能影响：重建有断层/漂移", @"howto": @"怎么做：放慢移动，每段停 0.5 秒再继续", @"time": @(8)},
        @{@"title": @"墙面太白不好识别", @"level": @"warn", @"impact": @"可能影响：细节少，重建不稳定", @"howto": @"怎么做：尽量带上门框/家具等特征一起拍，别只拍白墙"}
    ];
}

- (void)renderDeviceCheckItems:(NSArray<NSDictionary *> *)items {
    for (UIView *view in _deviceListStack.arrangedSubviews) {
        [_deviceListStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    for (UIView *view in _deviceTagStack.arrangedSubviews) {
        [_deviceTagStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }

    NSArray<NSDictionary *> *actionableItems = [self actionableItemsFromItems:items];
    NSArray<NSDictionary *> *displayItems = items;
    if (!_deviceExpandedAll) {
        if (actionableItems.count > 0) {
            NSInteger count = MIN((NSInteger)actionableItems.count, 2);
            displayItems = [actionableItems subarrayWithRange:NSMakeRange(0, count)];
        } else {
            displayItems = items.count > 0 ? @[items.firstObject] : @[];
        }
    }

    for (NSDictionary *item in displayItems) {
        [_deviceListStack addArrangedSubview:[self deviceRowForItem:item]];
    }

    NSMutableArray<NSDictionary *> *tags = [NSMutableArray array];
    if (!_room.captureComplete) {
        [tags addObject:@{@"text": @"未采集", @"level": @"warn"}];
    } else if (_room.auditStatus == 2) {
        [tags addObject:@{@"text": @"整体不错", @"level": @"ok"}];
        if (actionableItems.count > 0) {
            [tags addObject:@{@"text": @"走慢一点更稳", @"level": @"brand"}];
        }
    } else {
        [tags addObjectsFromArray:[self topIssueTagsFromItems:items maxCount:4]];
    }

    NSInteger perRow = 3;
    for (NSInteger index = 0; index < (NSInteger)tags.count; index += perRow) {
        UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 8;

        NSInteger end = MIN(index + perRow, (NSInteger)tags.count);
        for (NSInteger tagIndex = index; tagIndex < end; tagIndex++) {
            NSDictionary *tag = tags[tagIndex];
            [row addArrangedSubview:[self tagForText:tag[@"text"] level:tag[@"level"]]];
        }

        UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
        [row addArrangedSubview:spacer];
        [_deviceTagStack addArrangedSubview:row];
    }

    _deviceTagStack.hidden = (tags.count == 0);

    NSInteger actionableCount = (NSInteger)actionableItems.count;
    _deviceExpandButton.hidden = (actionableCount <= 2);
    if (!_deviceExpandButton.hidden) {
        NSString *title = _deviceExpandedAll ? @"收起建议 ▲" : @"展开查看更多建议 ›";
        [_deviceExpandButton setTitle:title forState:UIControlStateNormal];
    }
}

- (void)applyRoomState {
    UIColor *brand = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    UIColor *success = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
    UIColor *successBackground = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
    UIColor *warning = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:1.0];
    UIColor *warningBackground = [UIColor colorWithRed:255/255.0 green:243/255.0 blue:224/255.0 alpha:1.0];
    UIColor *error = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    UIColor *errorBackground = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];

    if (!_room.captureComplete) {
        [_leftBtn setTitle:@"返回" forState:UIControlStateNormal];
        [_rightBtn setTitle:@"去采集" forState:UIControlStateNormal];
        _rightBtn.backgroundColor = brand;

        _backendCard.backgroundColor = [UIColor whiteColor];
        _backendCard.layer.borderWidth = 0;
        _backendStatusBadge.text = @"未采集";
        _backendStatusBadge.textColor = [UIColor colorWithRed:153/255.0 green:153/255.0 blue:153/255.0 alpha:1.0];
        _backendStatusBadge.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
        _backendPendingView.hidden = YES;
        [_backendSpinner stopAnimating];
        _backendMessageLabel.hidden = NO;
        _backendMessageLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
        _backendMessageLabel.text = @"请先完成采集后再查看后端质量检测结果";

        _deviceSummaryLabel.text = @"未采集｜请先完成采集后再查看拍摄建议";
        [self renderDeviceCheckItems:[self demoDeviceCheckItemsForRoom]];
        return;
    }

    [self generateVideoThumbnailsIfNeeded];

    if (_room.auditStatus == 1) {
        [_rightBtn setTitle:@"刷新状态" forState:UIControlStateNormal];
        _backendCard.backgroundColor = [UIColor whiteColor];
        _backendCard.layer.borderWidth = 0;
        _backendStatusBadge.text = @"审核中";
        _backendStatusBadge.textColor = warning;
        _backendStatusBadge.backgroundColor = warningBackground;
        _backendPendingView.hidden = NO;
        [_backendSpinner startAnimating];
        _backendMessageLabel.hidden = YES;
        _deviceSummaryLabel.text = @"审核中｜可先对照以下建议自查";
    } else if (_room.auditStatus == 2) {
        [_leftBtn setTitle:@"重录此房间" forState:UIControlStateNormal];
        [_rightBtn setTitle:(_singleRoomDemoFlow ? @"确认提交" : @"返回概览") forState:UIControlStateNormal];
        _backendCard.backgroundColor = successBackground;
        _backendCard.layer.borderWidth = 1;
        _backendCard.layer.borderColor = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:0.25].CGColor;
        _backendStatusBadge.text = @"通过";
        _backendStatusBadge.textColor = success;
        _backendStatusBadge.backgroundColor = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:0.12];
        _backendPendingView.hidden = YES;
        [_backendSpinner stopAnimating];
        _backendMessageLabel.hidden = NO;
        _backendMessageLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
        _backendMessageLabel.text = @"素材质量合格，可以用于高斯溅射重建";
        _deviceSummaryLabel.text = @"已通过审核｜如想更稳，可按以下建议优化";
    } else if (_room.auditStatus == 3) {
        [_rightBtn setTitle:@"补拍视频" forState:UIControlStateNormal];
        _backendCard.backgroundColor = errorBackground;
        _backendCard.layer.borderWidth = 1;
        _backendCard.layer.borderColor = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:0.25].CGColor;
        _backendStatusBadge.text = @"不通过";
        _backendStatusBadge.textColor = error;
        _backendStatusBadge.backgroundColor = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:0.12];
        _backendPendingView.hidden = YES;
        [_backendSpinner stopAnimating];
        _backendMessageLabel.hidden = NO;
        _backendMessageLabel.textColor = [UIColor colorWithRed:184/255.0 green:28/255.0 blue:28/255.0 alpha:1.0];
        _backendMessageLabel.text = _room.auditReason.length > 0 ? _room.auditReason : @"无法形成闭合空间完成重建，请重新拍摄";
        _deviceSummaryLabel.text = @"未通过审核｜建议补拍，重点处理以下问题";
    } else {
        [_rightBtn setTitle:@"刷新状态" forState:UIControlStateNormal];
        _backendCard.backgroundColor = [UIColor whiteColor];
        _backendCard.layer.borderWidth = 0;
        _backendStatusBadge.text = @"未进入审核";
        _backendStatusBadge.textColor = warning;
        _backendStatusBadge.backgroundColor = warningBackground;
        _backendPendingView.hidden = YES;
        [_backendSpinner stopAnimating];
        _backendMessageLabel.hidden = NO;
        _backendMessageLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
        _backendMessageLabel.text = @"该视频尚未进入后端审核队列";
        _deviceSummaryLabel.text = @"未进入审核｜可先对照以下建议自查";
    }

    [self renderDeviceCheckItems:[self demoDeviceCheckItemsForRoom]];
}

- (void)toggleDeviceExpanded:(UIButton *)sender {
    _deviceExpandedAll = !_deviceExpandedAll;
    [self applyRoomState];
    (void)sender;
}

- (void)leftAction {
    if (_singleRoomDemoFlow) {
        CD3DGSCaptureViewController *captureVC = [[CD3DGSCaptureViewController alloc] init];
        NSMutableArray<UIViewController *> *viewControllers = [self.navigationController.viewControllers mutableCopy];
        if (viewControllers.count > 0) {
            [viewControllers removeLastObject];
        }
        [viewControllers addObject:captureVC];
        [self.navigationController setViewControllers:viewControllers animated:YES];
        return;
    }
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)rightAction {
    if (!_room.captureComplete) {
        NSLog(@"去采集：%@", _room.roomName);
        return;
    }
    if (_room.auditStatus == 1) {
        NSLog(@"刷新状态：%@", _room.roomName);
        return;
    }
    if (_room.auditStatus == 2) {
        if (_singleRoomDemoFlow) {
            CD3DGSTrainingResultSummary *summary = [CD3DGSTrainingResultSummary demoSummary];
            CD3DGSTrainingResultViewController *trainingVC = [[CD3DGSTrainingResultViewController alloc] initWithSummary:summary
                                                                                                        singleRoomDemoFlow:YES];
            [self.navigationController pushViewController:trainingVC animated:YES];
            return;
        }
        [self.navigationController popViewControllerAnimated:YES];
        return;
    }
    NSLog(@"补拍/重拍：%@", _room.roomName);
}

- (void)playTapped {
    if (!_room.captureComplete) {
        [self showSimpleAlertWithTitle:@"未完成采集" message:@"请先完成该房间采集后再播放"];
        return;
    }
    [self ensureDownloadAndPlaySeconds:_selectedSeconds];
}

- (void)frameTapped:(UIControl *)sender {
    if (!_room.captureComplete) {
        [self showSimpleAlertWithTitle:@"未完成采集" message:@"请先完成该房间采集后再播放"];
        return;
    }
    if (_videoURLs.count > 1) {
        _selectedVideoIndex = sender.tag;
        _remoteVideoURL = [self selectedVideoURL];
        _selectedSeconds = 0;
        _selectedFrameIndex = _selectedVideoIndex;
        if (_selectedFrameIndex >= 0 && _selectedFrameIndex < (NSInteger)_frameImageViews.count) {
            _coverImageView.image = _frameImageViews[_selectedFrameIndex].image;
        }
        if (!_coverImageView.image) {
            [self generateVideoThumbnailsIfNeeded];
        }
    } else {
        _selectedSeconds = sender.tag * 12;
        _selectedFrameIndex = [self nearestFrameIndexForSeconds:_selectedSeconds];
    }
    [self updateSelectedFrameUI];
}

- (void)locateTapped:(UIButton *)sender {
    if (!_room.captureComplete) {
        return;
    }
    _selectedSeconds = sender.tag;
    _selectedFrameIndex = [self nearestFrameIndexForSeconds:_selectedSeconds];
    [self updateSelectedFrameUI];
}

- (void)jumpToIssue {
    NSLog(@"跳到问题片段：%@", _room.roomName);
}

@end
