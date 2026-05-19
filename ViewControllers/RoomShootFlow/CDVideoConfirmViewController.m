#import "CDVideoConfirmViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>
#import <WebKit/WebKit.h>

#pragma mark - Data Models

@interface CDRoomItem : NSObject
@property (nonatomic, copy) NSString *roomId;
@property (nonatomic, copy) NSString *roomName;
@property (nonatomic, assign) BOOL captureComplete; // 是否完成采集（完成后才会进入审核队列）
@property (nonatomic, assign) NSInteger auditStatus; // 0:未进入审核 1:审核中 2:通过 3:未通过
@property (nonatomic, copy) NSString *auditReason;
@end

@implementation CDRoomItem
@end

#pragma mark - Progress Donut View

@interface CDProgressDonutView : UIView
@property (nonatomic, assign) CGFloat progress; // 0.0 ~ 1.0
@property (nonatomic, strong) UIColor *trackColor;
@property (nonatomic, strong) UIColor *progressColor;
@property (nonatomic, copy) NSString *centerText; // e.g. 3/5
@end

@implementation CDProgressDonutView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _trackColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
        _progressColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
        self.backgroundColor = [UIColor clearColor];
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGFloat width = rect.size.width;
    CGFloat height = rect.size.height;
    CGFloat radius = MIN(width, height) / 2.0 - 3.0;
    CGPoint center = CGPointMake(width / 2.0, height / 2.0);

    UIBezierPath *trackPath = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:0 endAngle:M_PI * 2 clockwise:YES];
    [self.trackColor setStroke];
    trackPath.lineWidth = 6.0;
    [trackPath stroke];

    if (self.progress > 0) {
        CGFloat startAngle = -M_PI / 2.0;
        CGFloat endAngle = startAngle + (M_PI * 2.0 * self.progress);
        UIBezierPath *progressPath = [UIBezierPath bezierPathWithArcCenter:center radius:radius startAngle:startAngle endAngle:endAngle clockwise:YES];
        [self.progressColor setStroke];
        progressPath.lineWidth = 6.0;
        progressPath.lineCapStyle = kCGLineCapRound;
        [progressPath stroke];
    }

    NSString *percentText = self.centerText ?: [NSString stringWithFormat:@"%.0f%%", self.progress * 100];
    NSDictionary *attrs = @{
        NSFontAttributeName: [UIFont boldSystemFontOfSize:14],
        NSForegroundColorAttributeName: [UIColor blackColor]
    };
    CGSize textSize = [percentText sizeWithAttributes:attrs];
    CGPoint textPoint = CGPointMake((width - textSize.width) / 2.0, (height - textSize.height) / 2.0 + 1);
    [percentText drawAtPoint:textPoint withAttributes:attrs];
}

- (void)setProgress:(CGFloat)progress {
    _progress = MAX(0, MIN(1, progress));
    [self setNeedsDisplay];
}

@end

#pragma mark - Stacked Bar View

@interface CDInsetLabel : UILabel
@property (nonatomic, assign) UIEdgeInsets contentInsets;
@end

@implementation CDInsetLabel

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _contentInsets = UIEdgeInsetsZero;
    }
    return self;
}

- (void)drawTextInRect:(CGRect)rect {
    [super drawTextInRect:UIEdgeInsetsInsetRect(rect, self.contentInsets)];
}

- (CGSize)intrinsicContentSize {
    CGSize size = [super intrinsicContentSize];
    size.width += self.contentInsets.left + self.contentInsets.right;
    size.height += self.contentInsets.top + self.contentInsets.bottom;
    return size;
}

@end

@interface CDStackedBarView : UIView
@property (nonatomic, copy) NSArray<NSNumber *> *values;
@property (nonatomic, copy) NSArray<UIColor *> *colors;
@property (nonatomic, assign) CGFloat cornerRadius;
@end

@implementation CDStackedBarView {
    NSMutableArray<CALayer *> *_segmentLayers;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _segmentLayers = [NSMutableArray array];
        _cornerRadius = 4;
        self.backgroundColor = [UIColor clearColor];
        self.clipsToBounds = YES;
    }
    return self;
}

- (void)setValues:(NSArray<NSNumber *> *)values {
    _values = [values copy];
    [self setNeedsLayout];
}

- (void)setColors:(NSArray<UIColor *> *)colors {
    _colors = [colors copy];
    [self setNeedsLayout];
}

- (void)layoutSubviews {
    [super layoutSubviews];

    for (CALayer *layer in _segmentLayers) {
        [layer removeFromSuperlayer];
    }
    [_segmentLayers removeAllObjects];

    CGFloat total = 0;
    for (NSNumber *n in self.values) {
        total += n.doubleValue;
    }

    self.layer.cornerRadius = self.cornerRadius;

    if (total <= 0.0001 || self.values.count == 0) {
        return;
    }

    CGFloat x = 0;
    CGFloat h = self.bounds.size.height;
    CGFloat w = self.bounds.size.width;

    for (NSInteger i = 0; i < self.values.count; i++) {
        CGFloat v = self.values[i].doubleValue;
        if (v <= 0) continue;

        CGFloat segW = (v / total) * w;
        if (x + segW > w) segW = w - x;
        if (segW <= 0) continue;

        CALayer *seg = [CALayer layer];
        seg.backgroundColor = (i < self.colors.count ? self.colors[i].CGColor : [UIColor lightGrayColor].CGColor);
        seg.frame = CGRectMake(x, 0, segW, h);
        [self.layer addSublayer:seg];
        [_segmentLayers addObject:seg];

        x += segW;
        if (x >= w) break;
    }
}

@end

#pragma mark - Room Video Review (Detail)

@interface CDRoomVideoReviewViewController : UIViewController
- (instancetype)initWithRoom:(CDRoomItem *)room;
@end

@implementation CDRoomVideoReviewViewController {
    CDRoomItem *_room;
    NSURL *_remoteVideoURL;
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
    UILabel *_deviceNoteLabel;
    CDInsetLabel *_deviceSummaryBadge;
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

- (instancetype)initWithRoom:(CDRoomItem *)room {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _room = room;
        _remoteVideoURL = [self.class demoVideoURLForRoom:room];
        _selectedFrameIndex = 1;
        _selectedSeconds = 12;
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
        NSInteger v = room.roomId.integerValue;
        if (v > 0) idx = (v - 1) % urls.count;
    }
    return [NSURL URLWithString:urls[idx]];
}

- (NSURL *)localVideoURL {
    NSString *cacheRoot = [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"DemoVideoCache"];
    [[NSFileManager defaultManager] createDirectoryAtPath:cacheRoot withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *roomKey = _room.roomId.length > 0 ? _room.roomId : @"unknown";
    NSString *fileName = [NSString stringWithFormat:@"room_%@.mp4", roomKey];
    return [NSURL fileURLWithPath:[cacheRoot stringByAppendingPathComponent:fileName]];
}

- (BOOL)isVideoCached {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self localVideoURL].path];
}

- (void)startDownloadIfNeeded {
    if (!_remoteVideoURL || [self isVideoCached] || _downloadTask != nil) return;

    __weak typeof(self) weakSelf = self;
    _downloadTask = [[NSURLSession sharedSession] downloadTaskWithURL:_remoteVideoURL completionHandler:^(NSURL * _Nullable location, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;

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
    AVPlayerViewController *pvc = [[AVPlayerViewController alloc] init];
    pvc.player = player;
    [self presentViewController:pvc animated:YES completion:^{
        if (seconds > 0) {
            CMTime t = CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC);
            [player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                [player play];
            }];
        } else {
            [player play];
        }
    }];
}

- (void)playRemoteVideoWithSeekSeconds:(NSTimeInterval)seconds {
    if (!_remoteVideoURL) {
        [self showSimpleAlertWithTitle:@"无法播放" message:@"缺少视频地址"];
        return;
    }

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:_remoteVideoURL];
    if (_currentPlayerItem) {
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemFailedToPlayToEndTimeNotification object:_currentPlayerItem];
        [[NSNotificationCenter defaultCenter] removeObserver:self name:AVPlayerItemPlaybackStalledNotification object:_currentPlayerItem];
    }
    _currentPlayerItem = item;
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerFailed:) name:AVPlayerItemFailedToPlayToEndTimeNotification object:item];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(playerStalled:) name:AVPlayerItemPlaybackStalledNotification object:item];

    AVPlayer *player = [AVPlayer playerWithPlayerItem:item];
    AVPlayerViewController *pvc = [[AVPlayerViewController alloc] init];
    pvc.player = player;
    [self presentViewController:pvc animated:YES completion:^{
        if (seconds > 0) {
            CMTime t = CMTimeMakeWithSeconds(seconds, NSEC_PER_SEC);
            [player seekToTime:t toleranceBefore:kCMTimeZero toleranceAfter:kCMTimeZero completionHandler:^(BOOL finished) {
                [player play];
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
    NSError *err = _currentPlayerItem.error;
    NSString *msg = err.localizedDescription.length > 0 ? err.localizedDescription : @"播放失败，请检查网络或稍后重试";
    [self showSimpleAlertWithTitle:@"播放失败" message:msg];
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
    CGFloat bottomH = 84;
    if (@available(iOS 11.0, *)) {
        bottomH += self.view.safeAreaInsets.bottom;
    }
    _bottomBarHeightConstraint.constant = bottomH;
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
    _durLabel.text = @"02:42";
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
    for (NSInteger i = 0; i < 6; i++) {
        UIControl *frame = [[UIControl alloc] initWithFrame:CGRectZero];
        frame.backgroundColor = [UIColor colorWithRed:240/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
        frame.layer.cornerRadius = 8;
        frame.layer.borderWidth = 1;
        frame.layer.borderColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0].CGColor;
        frame.clipsToBounds = YES;
        frame.tag = i;
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

        UILabel *t = [[UILabel alloc] initWithFrame:CGRectZero];
        t.translatesAutoresizingMaskIntoConstraints = NO;
        t.font = [UIFont systemFontOfSize:9 weight:UIFontWeightBold];
        t.textColor = [UIColor colorWithWhite:1 alpha:0.9];
        t.backgroundColor = [UIColor colorWithWhite:0 alpha:0.5];
        t.layer.cornerRadius = 2;
        t.clipsToBounds = YES;
        t.textAlignment = NSTextAlignmentCenter;
        t.text = [NSString stringWithFormat:@"%lds", (long)(i * 12)];
        [frame addSubview:t];
        [NSLayoutConstraint activateConstraints:@[
            [t.trailingAnchor constraintEqualToAnchor:frame.trailingAnchor constant:-3],
            [t.bottomAnchor constraintEqualToAnchor:frame.bottomAnchor constant:-2],
            [t.heightAnchor constraintEqualToConstant:12]
        ]];

        [_framesStack addArrangedSubview:frame];
    }

    [self updateSelectedFrameUI];

    // Backend result card (authoritative)
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

    // Device assistive checklist card (secondary)
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

    for (NSInteger i = 0; i < _frameControls.count; i++) {
        UIControl *c = _frameControls[i];
        if (i == _selectedFrameIndex) {
            c.layer.borderColor = activeBorder.CGColor;
        } else {
            c.layer.borderColor = normalBorder.CGColor;
        }
    }

    if (_selectedFrameIndex >= 0 && _selectedFrameIndex < (NSInteger)_frameImageViews.count) {
        UIImage *img = _frameImageViews[_selectedFrameIndex].image;
        if (img) _coverImageView.image = img;
    }
}

- (void)generateVideoThumbnailsIfNeeded {
    if (!_room.captureComplete) return;

    NSURL *assetURL = [self isVideoCached] ? [self localVideoURL] : _remoteVideoURL;
    if (!assetURL) return;

    _thumbnailRequestID += 1;
    NSInteger requestID = _thumbnailRequestID;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:assetURL options:nil];
    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.maximumSize = CGSizeMake(720, 720);
    gen.requestedTimeToleranceBefore = kCMTimeZero;
    gen.requestedTimeToleranceAfter = kCMTimeZero;

    NSMutableArray<NSValue *> *times = [NSMutableArray array];
    for (NSInteger i = 0; i < 6; i++) {
        CMTime t = CMTimeMakeWithSeconds(i * 12.0, NSEC_PER_SEC);
        [times addObject:[NSValue valueWithCMTime:t]];
    }

    __weak typeof(self) weakSelf = self;
    [gen generateCGImagesAsynchronouslyForTimes:times completionHandler:^(CMTime requestedTime, CGImageRef  _Nullable cgImage, CMTime actualTime, AVAssetImageGeneratorResult result, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (self->_thumbnailRequestID != requestID) return;
        if (result != AVAssetImageGeneratorSucceeded || !cgImage) return;

        UIImage *image = [UIImage imageWithCGImage:cgImage];
        NSInteger idx = (NSInteger)llround(CMTimeGetSeconds(requestedTime) / 12.0);
        if (idx < 0) idx = 0;

        dispatch_async(dispatch_get_main_queue(), ^{
            if (self->_thumbnailRequestID != requestID) return;
            if (idx >= 0 && idx < (NSInteger)self->_frameImageViews.count) {
                self->_frameImageViews[idx].image = image;
            }
            if (idx == self->_selectedFrameIndex) {
                self->_coverImageView.image = image;
            } else if (!self->_coverImageView.image && idx == 0) {
                self->_coverImageView.image = image;
            }
        });
        (void)actualTime;
        (void)error;
    }];
}

- (NSInteger)nearestFrameIndexForSeconds:(NSTimeInterval)seconds {
    NSInteger idx = (NSInteger)llround(seconds / 12.0);
    if (idx < 0) idx = 0;
    if (idx > 5) idx = 5;
    return idx;
}

- (NSString *)mmssForSeconds:(NSInteger)seconds {
    NSInteger sec = MAX(0, seconds);
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(sec / 60), (long)(sec % 60)];
}

- (CDInsetLabel *)pillForLevel:(NSString *)level {
    UIColor *success = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
    UIColor *successBg = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
    UIColor *warn = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:1.0];
    UIColor *warnBg = [UIColor colorWithRed:255/255.0 green:243/255.0 blue:224/255.0 alpha:1.0];
    UIColor *error = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    UIColor *errorBg = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];

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
        pill.backgroundColor = errorBg;
    } else if ([level isEqualToString:@"warn"]) {
        pill.text = @"可优化";
        pill.textColor = warn;
        pill.backgroundColor = warnBg;
    } else {
        pill.text = @"正常";
        pill.textColor = success;
        pill.backgroundColor = successBg;
    }
    return pill;
}

- (CDInsetLabel *)tagForText:(NSString *)text level:(NSString *)level {
    UIColor *brand = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    UIColor *brandBg = [UIColor colorWithRed:224/255.0 green:237/255.0 blue:255/255.0 alpha:1.0]; // #E0EDFF
    UIColor *success = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
    UIColor *successBg = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
    UIColor *warn = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:1.0];
    UIColor *warnBg = [UIColor colorWithRed:255/255.0 green:243/255.0 blue:224/255.0 alpha:1.0];
    UIColor *error = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    UIColor *errorBg = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];

    CDInsetLabel *tag = [[CDInsetLabel alloc] initWithFrame:CGRectZero];
    tag.translatesAutoresizingMaskIntoConstraints = NO;
    tag.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    tag.contentInsets = UIEdgeInsetsMake(4, 10, 4, 10);
    tag.layer.cornerRadius = 11;
    tag.clipsToBounds = YES;
    tag.text = text ?: @"";

    if ([level isEqualToString:@"risk"]) {
        tag.textColor = error;
        tag.backgroundColor = errorBg;
    } else if ([level isEqualToString:@"warn"]) {
        tag.textColor = warn;
        tag.backgroundColor = warnBg;
    } else if ([level isEqualToString:@"brand"]) {
        tag.textColor = brand;
        tag.backgroundColor = brandBg;
    } else {
        tag.textColor = success;
        tag.backgroundColor = successBg;
    }
    return tag;
}

- (UIView *)deviceRowForItem:(NSDictionary *)item {
    UIColor *brand = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];

    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];
    row.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *v = [[UIStackView alloc] initWithFrame:CGRectZero];
    v.translatesAutoresizingMaskIntoConstraints = NO;
    v.axis = UILayoutConstraintAxisVertical;
    v.spacing = 4;
    [row addSubview:v];
    [NSLayoutConstraint activateConstraints:@[
        [v.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [v.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [v.topAnchor constraintEqualToAnchor:row.topAnchor],
        [v.bottomAnchor constraintEqualToAnchor:row.bottomAnchor]
    ]];

    UIStackView *top = [[UIStackView alloc] initWithFrame:CGRectZero];
    top.axis = UILayoutConstraintAxisHorizontal;
    top.alignment = UIStackViewAlignmentCenter;
    top.spacing = 8;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    title.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    title.text = item[@"title"] ?: @"";
    [top addArrangedSubview:title];

    UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
    [top addArrangedSubview:spacer];

    NSString *level = item[@"level"] ?: @"ok";
    CDInsetLabel *pill = [self pillForLevel:level];
    [top addArrangedSubview:pill];

    NSNumber *time = item[@"time"];
    if ([time isKindOfClass:[NSNumber class]]) {
        UIButton *locate = [UIButton buttonWithType:UIButtonTypeSystem];
        locate.translatesAutoresizingMaskIntoConstraints = NO;
        locate.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        [locate setTitleColor:brand forState:UIControlStateNormal];
        locate.contentEdgeInsets = UIEdgeInsetsMake(4, 6, 4, 6);
        locate.layer.cornerRadius = 8;
        locate.backgroundColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:0.08];
        locate.tag = time.integerValue;
        [locate setTitle:[NSString stringWithFormat:@"定位 %@", [self mmssForSeconds:time.integerValue]] forState:UIControlStateNormal];
        [locate addTarget:self action:@selector(locateTapped:) forControlEvents:UIControlEventTouchUpInside];
        [top addArrangedSubview:locate];
    }

    [v addArrangedSubview:top];

    NSString *impact = item[@"impact"];
    if (impact.length > 0) {
        UILabel *impactLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        impactLabel.font = [UIFont systemFontOfSize:12];
        impactLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
        impactLabel.numberOfLines = 0;
        impactLabel.text = impact;
        [v addArrangedSubview:impactLabel];
    }

    NSString *howto = item[@"howto"];
    if (howto.length > 0) {
        UILabel *howtoLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        howtoLabel.font = [UIFont systemFontOfSize:12];
        howtoLabel.textColor = [UIColor colorWithRed:153/255.0 green:153/255.0 blue:153/255.0 alpha:1.0];
        howtoLabel.numberOfLines = 0;
        howtoLabel.text = howto;
        [v addArrangedSubview:howtoLabel];
    }

    return row;
}

- (NSArray<NSDictionary *> *)actionableItemsFromItems:(NSArray<NSDictionary *> *)items {
    NSMutableArray<NSDictionary *> *res = [NSMutableArray array];
    for (NSDictionary *it in items) {
        NSString *level = it[@"level"];
        if ([level isEqualToString:@"risk"] || [level isEqualToString:@"warn"]) {
            [res addObject:it];
        }
    }
    return res;
}

- (NSArray<NSDictionary *> *)topIssueTagsFromItems:(NSArray<NSDictionary *> *)items maxCount:(NSInteger)maxCount {
    NSArray<NSDictionary *> *actionable = [self actionableItemsFromItems:items];
    NSMutableArray<NSDictionary *> *tags = [NSMutableArray array];

    // Prefer risk, then warn.
    for (NSString *lvl in @[@"risk", @"warn"]) {
        for (NSDictionary *it in actionable) {
            if (tags.count >= maxCount) break;
            if (![it[@"level"] isEqualToString:lvl]) continue;
            NSString *t = it[@"title"];
            if (t.length == 0) continue;
            [tags addObject:@{@"text": t, @"level": lvl}];
        }
        if (tags.count >= maxCount) break;
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

    if (_room.auditStatus == 2) { // pass
        return @[
            @{@"title": @"走得偏快", @"level": @"warn", @"impact": @"可能影响：重建有断层/漂移", @"howto": @"怎么做：放慢移动，每段停 0.5 秒再继续", @"time": @(8)}
        ];
    }

    if (_room.auditStatus == 1) { // reviewing
        return @[
            @{@"title": @"走得偏快", @"level": @"warn", @"impact": @"可能影响：重建有断层/漂移", @"howto": @"怎么做：放慢移动，每段停 0.5 秒再继续", @"time": @(8)},
            @{@"title": @"手有点抖", @"level": @"warn", @"impact": @"可能影响：画面跟不住，重建会“飘”", @"howto": @"怎么做：双手握持，贴近身体慢走；必要时靠墙借力", @"time": @(24)}
        ];
    }

    // fail / others
    return @[
        @{@"title": @"手抖明显", @"level": @"risk", @"impact": @"可能影响：画面跟不住，重建会“飘”", @"howto": @"怎么做：双手握持，贴近身体慢走；必要时靠墙借力", @"time": @(24)},
        @{@"title": @"光线偏暗", @"level": @"risk", @"impact": @"可能影响：细节看不清，训练不稳定", @"howto": @"怎么做：开灯/拉窗帘/靠近光源；避免背光", @"time": @(12)},
        @{@"title": @"走得偏快", @"level": @"warn", @"impact": @"可能影响：重建有断层/漂移", @"howto": @"怎么做：放慢移动，每段停 0.5 秒再继续", @"time": @(8)},
        @{@"title": @"墙面太白不好识别", @"level": @"warn", @"impact": @"可能影响：细节少，重建不稳定", @"howto": @"怎么做：尽量带上门框/家具等特征一起拍，别只拍白墙"}
    ];
}

- (void)renderDeviceCheckItems:(NSArray<NSDictionary *> *)items {
    for (UIView *v in _deviceListStack.arrangedSubviews) {
        [_deviceListStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    for (UIView *v in _deviceTagStack.arrangedSubviews) {
        [_deviceTagStack removeArrangedSubview:v];
        [v removeFromSuperview];
    }

    NSArray<NSDictionary *> *actionable = [self actionableItemsFromItems:items];
    NSArray<NSDictionary *> *displayItems = items;
    if (!_deviceExpandedAll) {
        if (actionable.count > 0) {
            NSInteger count = MIN((NSInteger)actionable.count, 2);
            displayItems = [actionable subarrayWithRange:NSMakeRange(0, count)];
        } else {
            displayItems = (items.count > 0) ? @[items.firstObject] : @[];
        }
    }

    for (NSDictionary *it in displayItems) {
        UIView *row = [self deviceRowForItem:it];
        [_deviceListStack addArrangedSubview:row];
    }

    // Tags (2–4)
    NSMutableArray<NSDictionary *> *tags = [NSMutableArray array];
    if (!_room.captureComplete) {
        [tags addObject:@{@"text": @"未采集", @"level": @"warn"}];
    } else if (_room.auditStatus == 2) { // pass
        [tags addObject:@{@"text": @"整体不错", @"level": @"ok"}];
        if (actionable.count > 0) {
            [tags addObject:@{@"text": @"走慢一点更稳", @"level": @"brand"}];
        }
    } else {
        [tags addObjectsFromArray:[self topIssueTagsFromItems:items maxCount:4]];
    }

    // Render tags into rows (wrap-ish)
    NSInteger perRow = 3;
    for (NSInteger i = 0; i < (NSInteger)tags.count; i += perRow) {
        UIStackView *row = [[UIStackView alloc] initWithFrame:CGRectZero];
        row.axis = UILayoutConstraintAxisHorizontal;
        row.alignment = UIStackViewAlignmentCenter;
        row.spacing = 8;

        NSInteger end = MIN(i + perRow, (NSInteger)tags.count);
        for (NSInteger j = i; j < end; j++) {
            NSDictionary *t = tags[j];
            CDInsetLabel *tag = [self tagForText:t[@"text"] level:t[@"level"]];
            [row addArrangedSubview:tag];
        }

        UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
        [row addArrangedSubview:spacer];
        [_deviceTagStack addArrangedSubview:row];
    }

    _deviceTagStack.hidden = (tags.count == 0);

    // Expand button
    NSInteger actionableCount = (NSInteger)actionable.count;
    _deviceExpandButton.hidden = (actionableCount <= 2);
    if (!_deviceExpandButton.hidden) {
        NSString *title = _deviceExpandedAll ? @"收起建议 ▲" : @"展开查看更多建议 ›";
        [_deviceExpandButton setTitle:title forState:UIControlStateNormal];
    }
}

- (void)applyRoomState {
    UIColor *brand = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    UIColor *success = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
    UIColor *successBg = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
    UIColor *warn = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:1.0];
    UIColor *warnBg = [UIColor colorWithRed:255/255.0 green:243/255.0 blue:224/255.0 alpha:1.0];
    UIColor *error = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    UIColor *errorBg = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];

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

    if (_room.auditStatus == 1) { // reviewing
        [_rightBtn setTitle:@"刷新状态" forState:UIControlStateNormal];
        _backendCard.backgroundColor = [UIColor whiteColor];
        _backendCard.layer.borderWidth = 0;
        _backendStatusBadge.text = @"审核中";
        _backendStatusBadge.textColor = warn;
        _backendStatusBadge.backgroundColor = warnBg;
        _backendPendingView.hidden = NO;
        [_backendSpinner startAnimating];
        _backendMessageLabel.hidden = YES;
        _deviceSummaryLabel.text = @"审核中｜可先对照以下建议自查";
    } else if (_room.auditStatus == 2) { // pass
        [_rightBtn setTitle:@"返回概览" forState:UIControlStateNormal];
        _backendCard.backgroundColor = successBg;
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
    } else if (_room.auditStatus == 3) { // fail
        [_rightBtn setTitle:@"补拍视频" forState:UIControlStateNormal];
        _backendCard.backgroundColor = errorBg;
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
    } else { // not in audit queue
        [_rightBtn setTitle:@"刷新状态" forState:UIControlStateNormal];
        _backendCard.backgroundColor = [UIColor whiteColor];
        _backendCard.layer.borderWidth = 0;
        _backendStatusBadge.text = @"未进入审核";
        _backendStatusBadge.textColor = warn;
        _backendStatusBadge.backgroundColor = warnBg;
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
}

- (void)leftAction {
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
    _selectedSeconds = sender.tag * 12;
    _selectedFrameIndex = [self nearestFrameIndexForSeconds:_selectedSeconds];
    [self updateSelectedFrameUI];
}

- (void)locateTapped:(UIButton *)sender {
    if (!_room.captureComplete) return;
    _selectedSeconds = sender.tag;
    _selectedFrameIndex = [self nearestFrameIndexForSeconds:_selectedSeconds];
    [self updateSelectedFrameUI];
}

- (void)jumpToIssue {
    NSLog(@"跳到问题片段：%@", _room.roomName);
}

@end

#pragma mark - Room Card Cell

@interface CDRoomCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) UILabel *stepBadge;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) CDInsetLabel *statusPill;
@property (nonatomic, strong) UILabel *auditReasonLabel;
@property (nonatomic, strong) UIImageView *chevronIcon;
@end

@implementation CDRoomCardCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        [self setupViews];
    }
    return self;
}

- (void)setupViews {
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.contentView.backgroundColor = [UIColor clearColor];
    self.accessoryType = UITableViewCellAccessoryNone;
    self.backgroundColor = [UIColor clearColor];

    self.cardView = [[UIView alloc] init];
    self.cardView.translatesAutoresizingMaskIntoConstraints = NO;
    self.cardView.backgroundColor = [UIColor whiteColor];
    self.cardView.layer.cornerRadius = 8;
    self.cardView.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1].CGColor;
    self.cardView.layer.shadowOpacity = 0.08;
    self.cardView.layer.shadowOffset = CGSizeMake(0, 1);
    self.cardView.layer.shadowRadius = 4;
    [self.contentView addSubview:self.cardView];

    [NSLayoutConstraint activateConstraints:@[
        [self.cardView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.cardView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.cardView.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:0],
        [self.cardView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-10]
    ]];

    // 缩略图区域
    self.thumbView = [[UIView alloc] init];
    self.thumbView.translatesAutoresizingMaskIntoConstraints = NO;
    self.thumbView.backgroundColor = [UIColor colorWithRed:74/255.0 green:79/255.0 blue:92/255.0 alpha:1.0];
    self.thumbView.layer.cornerRadius = 4;
    self.thumbView.clipsToBounds = YES;
    [self.cardView addSubview:self.thumbView];

    [NSLayoutConstraint activateConstraints:@[
        [self.thumbView.leadingAnchor constraintEqualToAnchor:self.cardView.leadingAnchor constant:12],
        [self.thumbView.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
        [self.thumbView.widthAnchor constraintEqualToConstant:56],
        [self.thumbView.heightAnchor constraintEqualToConstant:56]
    ]];

    self.stepBadge = [[UILabel alloc] init];
    self.stepBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.stepBadge.font = [UIFont boldSystemFontOfSize:10];
    self.stepBadge.textColor = [UIColor whiteColor];
    self.stepBadge.backgroundColor = [UIColor colorWithWhite:0 alpha:0.35];
    self.stepBadge.layer.cornerRadius = 3;
    self.stepBadge.clipsToBounds = YES;
    self.stepBadge.textAlignment = NSTextAlignmentCenter;
    [self.thumbView addSubview:self.stepBadge];
    [NSLayoutConstraint activateConstraints:@[
        [self.stepBadge.trailingAnchor constraintEqualToAnchor:self.thumbView.trailingAnchor constant:-4],
        [self.stepBadge.bottomAnchor constraintEqualToAnchor:self.thumbView.bottomAnchor constant:-4]
    ]];

    // 主内容区域
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.titleLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    [self.titleLabel setContentCompressionResistancePriority:UILayoutPriorityDefaultLow forAxis:UILayoutConstraintAxisHorizontal];
    [self.cardView addSubview:self.titleLabel];

    self.metaLabel = [[UILabel alloc] init];
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.metaLabel.font = [UIFont systemFontOfSize:12];
    self.metaLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    [self.cardView addSubview:self.metaLabel];

    self.statusPill = [[CDInsetLabel alloc] initWithFrame:CGRectZero];
    self.statusPill.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusPill.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.statusPill.contentInsets = UIEdgeInsetsMake(4, 10, 4, 10);
    self.statusPill.layer.cornerRadius = 10;
    self.statusPill.clipsToBounds = YES;
    self.statusPill.hidden = YES;
    [self.cardView addSubview:self.statusPill];

    self.auditReasonLabel = [[UILabel alloc] init];
    self.auditReasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditReasonLabel.font = [UIFont systemFontOfSize:11];
    self.auditReasonLabel.textColor = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    self.auditReasonLabel.hidden = YES;
    [self.cardView addSubview:self.auditReasonLabel];

    // 箭头
    self.chevronIcon = [[UIImageView alloc] init];
    self.chevronIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.chevronIcon.image = [UIImage systemImageNamed:@"chevron.right"];
    self.chevronIcon.tintColor = [UIColor colorWithRed:204/255.0 green:204/255.0 blue:204/255.0 alpha:1.0];
    [self.cardView addSubview:self.chevronIcon];

    [NSLayoutConstraint activateConstraints:@[
        [self.chevronIcon.trailingAnchor constraintEqualToAnchor:self.cardView.trailingAnchor constant:-12],
        [self.chevronIcon.centerYAnchor constraintEqualToAnchor:self.cardView.centerYAnchor],
        [self.chevronIcon.widthAnchor constraintEqualToConstant:16],
        [self.chevronIcon.heightAnchor constraintEqualToConstant:16],

        [self.titleLabel.leadingAnchor constraintEqualToAnchor:self.thumbView.trailingAnchor constant:10],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.cardView.topAnchor constant:12],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.chevronIcon.leadingAnchor constant:-8],

        [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.metaLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.metaLabel.trailingAnchor constraintEqualToAnchor:self.chevronIcon.leadingAnchor constant:-8],

        [self.statusPill.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],
        [self.statusPill.trailingAnchor constraintLessThanOrEqualToAnchor:self.chevronIcon.leadingAnchor constant:-8],
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusPill.leadingAnchor constant:-6],

        [self.auditReasonLabel.leadingAnchor constraintEqualToAnchor:self.metaLabel.leadingAnchor],
        [self.auditReasonLabel.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:6],
        [self.auditReasonLabel.trailingAnchor constraintEqualToAnchor:self.chevronIcon.leadingAnchor constant:-8],
        [self.auditReasonLabel.bottomAnchor constraintLessThanOrEqualToAnchor:self.cardView.bottomAnchor constant:-12]
    ]];
}

- (void)configWithRoom:(CDRoomItem *)room {
    self.titleLabel.text = room.roomName;

    self.stepBadge.hidden = YES;

    if (!room.captureComplete) {
        self.metaLabel.text = @"未完成采集，请先去采集";
    } else {
        self.metaLabel.text = @"已完成采集";
    }

    self.auditReasonLabel.text = @"";
    self.auditReasonLabel.hidden = YES;

    self.statusPill.hidden = NO;
    if (!room.captureComplete) {
        self.statusPill.text = @"未采集";
        self.statusPill.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
        self.statusPill.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
        return;
    }

    switch (room.auditStatus) {
        case 1: { // 审核中
            self.statusPill.text = @"审核中";
            self.statusPill.backgroundColor = [UIColor colorWithRed:232/255.0 green:240/255.0 blue:255/255.0 alpha:1.0];
            self.statusPill.textColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
            break;
        }
        case 2: { // 已通过
            self.statusPill.text = @"已通过";
            self.statusPill.backgroundColor = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
            self.statusPill.textColor = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
            break;
        }
        case 3: { // 未通过
            self.statusPill.text = @"未通过";
            self.statusPill.backgroundColor = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
            self.statusPill.textColor = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
            self.auditReasonLabel.text = room.auditReason;
            self.auditReasonLabel.hidden = NO;
            break;
        }
        default: {
            self.statusPill.text = @"待审核";
            self.statusPill.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
            self.statusPill.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
            break;
        }
    }
}

@end

#pragma mark - Main ViewController

@interface CDVideoConfirmViewController () <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// Header 区域
@property (nonatomic, strong) UIView *floorplanContainer;
@property (nonatomic, strong) UIView *floorplanView;
@property (nonatomic, strong) UIView *floorplanOverlayView;
@property (nonatomic, strong) CAGradientLayer *floorplanGradientLayer;
@property (nonatomic, strong) UIView *projectInfoView;
@property (nonatomic, strong) UILabel *projectNameLabel;
@property (nonatomic, strong) UILabel *projectAddrLabel;
@property (nonatomic, strong) UIView *roomTypeTag;
@property (nonatomic, strong) UILabel *roomTypeLabel;
@property (nonatomic, strong) CDProgressDonutView *progressDonut;
@property (nonatomic, strong) UIView *progressCard;
@property (nonatomic, strong) UILabel *progressTitleLabel;

// 审核总览
@property (nonatomic, strong) UIView *auditCard;
@property (nonatomic, strong) UILabel *auditStateLabel;
@property (nonatomic, strong) UILabel *auditSubtitleLabel;
@property (nonatomic, strong) CDStackedBarView *auditStackedBar;
@property (nonatomic, strong) UIStackView *auditPillsStack;
@property (nonatomic, strong) CDInsetLabel *pillIncompleteLabel;
@property (nonatomic, strong) CDInsetLabel *pillReviewingLabel;
@property (nonatomic, strong) CDInsetLabel *pillFailLabel;
@property (nonatomic, strong) CDInsetLabel *pillPassLabel;

// 房间列表
@property (nonatomic, strong) UILabel *sectionTitle;
@property (nonatomic, strong) UILabel *roomCountLabel;
@property (nonatomic, strong) UITableView *roomTableView;
@property (nonatomic, strong) NSLayoutConstraint *roomTableHeightConstraint;
@property (nonatomic, strong) NSMutableArray<CDRoomItem *> *roomList;

// 底部提交
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *submitBtn;
@property (nonatomic, strong) UILabel *submitHintLabel;
@property (nonatomic, strong) NSLayoutConstraint *bottomBarHeightConstraint;

@end

@implementation CDVideoConfirmViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
    self.title = @"分间采集";

    [self setupNavigationBar];
    [self setupMockData];
    [self setupViews];
    [self refreshOverviewUI];
}

- (void)setupNavigationBar {
    self.navigationController.navigationBar.prefersLargeTitles = NO;

    UIImage *backImage = [UIImage systemImageNamed:@"chevron.left"];
    UIBarButtonItem *backItem = [[UIBarButtonItem alloc] initWithImage:backImage style:UIBarButtonItemStylePlain target:self action:@selector(goBack)];
    self.navigationItem.leftBarButtonItem = backItem;

    UIImage *moreImage = [UIImage systemImageNamed:@"ellipsis"];
    UIBarButtonItem *moreItem = [[UIBarButtonItem alloc] initWithImage:moreImage style:UIBarButtonItemStylePlain target:self action:@selector(showMore)];
    self.navigationItem.rightBarButtonItem = moreItem;

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithTransparentBackground];
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:17]
        };
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
        self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    } else {
        self.navigationController.navigationBar.barStyle = UIBarStyleBlack;
        self.navigationController.navigationBar.tintColor = [UIColor whiteColor];
    }
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showMore {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"更多" message:@"功能开发中" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupMockData {
    // 模拟数据
    self.roomList = [NSMutableArray array];

    CDRoomItem *room1 = [[CDRoomItem alloc] init];
    room1.roomId = @"1";
    room1.roomName = @"主卧";
    room1.captureComplete = YES;
    room1.auditStatus = 3; // 未通过
    room1.auditReason = @"光线严重不足";
    [self.roomList addObject:room1];

    CDRoomItem *room2 = [[CDRoomItem alloc] init];
    room2.roomId = @"2";
    room2.roomName = @"次卧";
    room2.captureComplete = YES;
    room2.auditStatus = 1; // 审核中
    room2.auditReason = @"";
    [self.roomList addObject:room2];

    CDRoomItem *room3 = [[CDRoomItem alloc] init];
    room3.roomId = @"3";
    room3.roomName = @"客厅";
    room3.captureComplete = YES;
    room3.auditStatus = 2; // 已通过
    room3.auditReason = @"";
    [self.roomList addObject:room3];

    CDRoomItem *room4 = [[CDRoomItem alloc] init];
    room4.roomId = @"4";
    room4.roomName = @"厨房";
    room4.captureComplete = NO;
    room4.auditStatus = 0; // 未进入审核
    room4.auditReason = @"";
    [self.roomList addObject:room4];

    CDRoomItem *room5 = [[CDRoomItem alloc] init];
    room5.roomId = @"5";
    room5.roomName = @"卫生间";
    room5.captureComplete = NO;
    room5.auditStatus = 0; // 未进入审核
    room5.auditReason = @"";
    [self.roomList addObject:room5];
}

- (void)setupViews {
    [self setupBottomBar];

    // ScrollView
    self.scrollView = [[UIScrollView alloc] init];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    if (@available(iOS 11.0, *)) {
        self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    }
    [self.view addSubview:self.scrollView];

    self.contentView = [[UIView alloc] initWithFrame:CGRectZero];
    self.contentView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.scrollView addSubview:self.contentView];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.bottomBar.topAnchor]
    ]];

    if (@available(iOS 11.0, *)) {
        UILayoutGuide *contentGuide = self.scrollView.contentLayoutGuide;
        UILayoutGuide *frameGuide = self.scrollView.frameLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.topAnchor constraintEqualToAnchor:contentGuide.topAnchor],
            [self.contentView.leadingAnchor constraintEqualToAnchor:frameGuide.leadingAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:frameGuide.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:contentGuide.bottomAnchor],
            [self.contentView.widthAnchor constraintEqualToAnchor:frameGuide.widthAnchor]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.topAnchor],
            [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.leadingAnchor],
            [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.trailingAnchor],
            [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.bottomAnchor],
            [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.widthAnchor]
        ]];
    }

    [self setupFloorplanView];
    [self setupAuditCard];
    [self setupSectionTitle];
    [self setupRoomTableView];
}

- (void)setupFloorplanView {
    self.floorplanContainer = [[UIView alloc] initWithFrame:CGRectZero];
    self.floorplanContainer.translatesAutoresizingMaskIntoConstraints = NO;
    self.floorplanContainer.clipsToBounds = NO;
    [self.contentView addSubview:self.floorplanContainer];

    [NSLayoutConstraint activateConstraints:@[
        [self.floorplanContainer.topAnchor constraintEqualToAnchor:self.contentView.topAnchor],
        [self.floorplanContainer.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.floorplanContainer.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        [self.floorplanContainer.heightAnchor constraintEqualToConstant:272] // 220 + 22(进度卡片溢出) + 文案
    ]];

    // 户型图背景
    self.floorplanView = [[UIView alloc] initWithFrame:CGRectZero];
    self.floorplanView.translatesAutoresizingMaskIntoConstraints = NO;
    self.floorplanView.clipsToBounds = YES;
    [self.floorplanContainer addSubview:self.floorplanView];

    [NSLayoutConstraint activateConstraints:@[
        [self.floorplanView.topAnchor constraintEqualToAnchor:self.floorplanContainer.topAnchor],
        [self.floorplanView.leadingAnchor constraintEqualToAnchor:self.floorplanContainer.leadingAnchor],
        [self.floorplanView.trailingAnchor constraintEqualToAnchor:self.floorplanContainer.trailingAnchor],
        [self.floorplanView.heightAnchor constraintEqualToConstant:220]
    ]];

    UIView *bgView = [[UIView alloc] initWithFrame:CGRectZero];
    bgView.translatesAutoresizingMaskIntoConstraints = NO;
    bgView.backgroundColor = [UIColor colorWithRed:30/255.0 green:37/255.0 blue:51/255.0 alpha:1.0];
    [self.floorplanView addSubview:bgView];
    [NSLayoutConstraint activateConstraints:@[
        [bgView.topAnchor constraintEqualToAnchor:self.floorplanView.topAnchor],
        [bgView.leadingAnchor constraintEqualToAnchor:self.floorplanView.leadingAnchor],
        [bgView.trailingAnchor constraintEqualToAnchor:self.floorplanView.trailingAnchor],
        [bgView.bottomAnchor constraintEqualToAnchor:self.floorplanView.bottomAnchor]
    ]];

    self.floorplanOverlayView = [[UIView alloc] initWithFrame:CGRectZero];
    self.floorplanOverlayView.translatesAutoresizingMaskIntoConstraints = NO;
    self.floorplanOverlayView.backgroundColor = [UIColor clearColor];
    [self.floorplanView addSubview:self.floorplanOverlayView];
    [NSLayoutConstraint activateConstraints:@[
        [self.floorplanOverlayView.topAnchor constraintEqualToAnchor:self.floorplanView.topAnchor],
        [self.floorplanOverlayView.leadingAnchor constraintEqualToAnchor:self.floorplanView.leadingAnchor],
        [self.floorplanOverlayView.trailingAnchor constraintEqualToAnchor:self.floorplanView.trailingAnchor],
        [self.floorplanOverlayView.bottomAnchor constraintEqualToAnchor:self.floorplanView.bottomAnchor]
    ]];

    self.floorplanGradientLayer = [CAGradientLayer layer];
    self.floorplanGradientLayer.colors = @[(id)[UIColor colorWithWhite:0 alpha:0.5].CGColor,
                                          (id)[UIColor colorWithWhite:0 alpha:0.2].CGColor,
                                          (id)[UIColor clearColor].CGColor];
    self.floorplanGradientLayer.locations = @[@0, @0.6, @1];
    [self.floorplanOverlayView.layer addSublayer:self.floorplanGradientLayer];

    // 项目信息
    self.projectInfoView = [[UIView alloc] initWithFrame:CGRectZero];
    self.projectInfoView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.floorplanView addSubview:self.projectInfoView];
    [NSLayoutConstraint activateConstraints:@[
        [self.projectInfoView.leadingAnchor constraintEqualToAnchor:self.floorplanView.leadingAnchor constant:16],
        [self.projectInfoView.topAnchor constraintEqualToAnchor:self.floorplanView.topAnchor constant:96],
        [self.projectInfoView.trailingAnchor constraintLessThanOrEqualToAnchor:self.floorplanView.trailingAnchor constant:-56],
        [self.projectInfoView.heightAnchor constraintEqualToConstant:60]
    ]];

    self.projectNameLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.projectNameLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.projectNameLabel.text = @"远洋·山水花园";
    self.projectNameLabel.font = [UIFont boldSystemFontOfSize:18];
    self.projectNameLabel.textColor = [UIColor whiteColor];
    [self.projectInfoView addSubview:self.projectNameLabel];

    self.projectAddrLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.projectAddrLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.projectAddrLabel.text = @"北京市朝阳区望京西路 88 号 · 2 栋 1502";
    self.projectAddrLabel.font = [UIFont systemFontOfSize:12];
    self.projectAddrLabel.textColor = [UIColor colorWithWhite:1 alpha:0.65];
    [self.projectInfoView addSubview:self.projectAddrLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.projectNameLabel.leadingAnchor constraintEqualToAnchor:self.projectInfoView.leadingAnchor],
        [self.projectNameLabel.topAnchor constraintEqualToAnchor:self.projectInfoView.topAnchor],
        [self.projectNameLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.projectInfoView.trailingAnchor],

        [self.projectAddrLabel.leadingAnchor constraintEqualToAnchor:self.projectInfoView.leadingAnchor],
        [self.projectAddrLabel.topAnchor constraintEqualToAnchor:self.projectNameLabel.bottomAnchor constant:2],
        [self.projectAddrLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.projectInfoView.trailingAnchor]
    ]];

    self.roomTypeTag = [[UIView alloc] initWithFrame:CGRectZero];
    self.roomTypeTag.translatesAutoresizingMaskIntoConstraints = NO;
    self.roomTypeTag.backgroundColor = [UIColor colorWithWhite:0 alpha:0.3];
    self.roomTypeTag.layer.cornerRadius = 11;
    self.roomTypeTag.layer.borderWidth = 1;
    self.roomTypeTag.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.1].CGColor;
    [self.floorplanView addSubview:self.roomTypeTag];
    [NSLayoutConstraint activateConstraints:@[
        [self.roomTypeTag.trailingAnchor constraintEqualToAnchor:self.floorplanView.trailingAnchor constant:-16],
        [self.roomTypeTag.topAnchor constraintEqualToAnchor:self.floorplanView.topAnchor constant:96],
        [self.roomTypeTag.widthAnchor constraintEqualToConstant:80],
        [self.roomTypeTag.heightAnchor constraintEqualToConstant:22]
    ]];

    self.roomTypeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.roomTypeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.roomTypeLabel.text = @"三室一厅";
    self.roomTypeLabel.font = [UIFont systemFontOfSize:12];
    self.roomTypeLabel.textColor = [UIColor colorWithWhite:1 alpha:0.8];
    self.roomTypeLabel.textAlignment = NSTextAlignmentCenter;
    [self.roomTypeTag addSubview:self.roomTypeLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.roomTypeLabel.leadingAnchor constraintEqualToAnchor:self.roomTypeTag.leadingAnchor],
        [self.roomTypeLabel.trailingAnchor constraintEqualToAnchor:self.roomTypeTag.trailingAnchor],
        [self.roomTypeLabel.topAnchor constraintEqualToAnchor:self.roomTypeTag.topAnchor],
        [self.roomTypeLabel.bottomAnchor constraintEqualToAnchor:self.roomTypeTag.bottomAnchor]
    ]];

    // 进度卡片
    self.progressCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.progressCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressCard.backgroundColor = [UIColor colorWithWhite:1 alpha:0.95];
    self.progressCard.layer.cornerRadius = 12;
    self.progressCard.layer.shadowColor = [UIColor blackColor].CGColor;
    self.progressCard.layer.shadowOpacity = 0.08;
    self.progressCard.layer.shadowOffset = CGSizeMake(0, 1);
    self.progressCard.layer.shadowRadius = 4;
    [self.floorplanContainer addSubview:self.progressCard];
    [NSLayoutConstraint activateConstraints:@[
        [self.progressCard.centerXAnchor constraintEqualToAnchor:self.floorplanContainer.centerXAnchor],
        [self.progressCard.bottomAnchor constraintEqualToAnchor:self.floorplanView.bottomAnchor constant:22],
        [self.progressCard.widthAnchor constraintEqualToConstant:72],
        [self.progressCard.heightAnchor constraintEqualToConstant:72]
    ]];

    self.progressDonut = [[CDProgressDonutView alloc] initWithFrame:CGRectZero];
    self.progressDonut.translatesAutoresizingMaskIntoConstraints = NO;
    [self.progressCard addSubview:self.progressDonut];
    [NSLayoutConstraint activateConstraints:@[
        [self.progressDonut.centerXAnchor constraintEqualToAnchor:self.progressCard.centerXAnchor],
        [self.progressDonut.centerYAnchor constraintEqualToAnchor:self.progressCard.centerYAnchor],
        [self.progressDonut.widthAnchor constraintEqualToConstant:48],
        [self.progressDonut.heightAnchor constraintEqualToConstant:48]
    ]];

    self.progressTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.progressTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.progressTitleLabel.text = @"采集进度";
    self.progressTitleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    self.progressTitleLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    [self.floorplanContainer addSubview:self.progressTitleLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.progressTitleLabel.centerXAnchor constraintEqualToAnchor:self.progressCard.centerXAnchor],
        [self.progressTitleLabel.topAnchor constraintEqualToAnchor:self.progressCard.bottomAnchor constant:6]
    ]];

    // 简单模拟户型图
    UIView *floorplanSVG = [[UIView alloc] initWithFrame:CGRectZero];
    floorplanSVG.translatesAutoresizingMaskIntoConstraints = NO;
    floorplanSVG.backgroundColor = [UIColor clearColor];
    [self.floorplanView addSubview:floorplanSVG];
    [NSLayoutConstraint activateConstraints:@[
        [floorplanSVG.leadingAnchor constraintEqualToAnchor:self.floorplanView.leadingAnchor],
        [floorplanSVG.trailingAnchor constraintEqualToAnchor:self.floorplanView.trailingAnchor],
        [floorplanSVG.topAnchor constraintEqualToAnchor:self.floorplanView.topAnchor],
        [floorplanSVG.bottomAnchor constraintEqualToAnchor:self.floorplanView.bottomAnchor]
    ]];

    // 外墙
    UIView *outerWall = [[UIView alloc] initWithFrame:CGRectZero];
    outerWall.layer.borderWidth = 1.5;
    outerWall.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.25].CGColor;
    [floorplanSVG addSubview:outerWall];

    // 房间分隔线
    NSArray *roomNames = @[@"主卧", @"次卧", @"客厅", @"厨房", @"卫生间"];
    (void)roomNames;

    // 仅用于占位展示，保持与屏幕宽度成比例
    outerWall.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [outerWall.centerXAnchor constraintEqualToAnchor:floorplanSVG.centerXAnchor],
        [outerWall.centerYAnchor constraintEqualToAnchor:floorplanSVG.centerYAnchor constant:-10],
        [outerWall.widthAnchor constraintEqualToAnchor:floorplanSVG.widthAnchor multiplier:0.7],
        [outerWall.heightAnchor constraintEqualToConstant:130]
    ]];
}

- (CDInsetLabel *)makePillLabelWithBackgroundColor:(UIColor *)bgColor textColor:(UIColor *)textColor {
    CDInsetLabel *label = [[CDInsetLabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    label.textColor = textColor;
    label.backgroundColor = bgColor;
    label.contentInsets = UIEdgeInsetsMake(4, 10, 4, 10);
    label.layer.cornerRadius = 11;
    label.clipsToBounds = YES;
    label.textAlignment = NSTextAlignmentCenter;
    label.text = @"-";
    [label setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [label setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisHorizontal];
    [NSLayoutConstraint activateConstraints:@[
        [label.heightAnchor constraintEqualToConstant:22]
    ]];
    return label;
}

- (void)setupAuditCard {
    self.auditCard = [[UIView alloc] initWithFrame:CGRectZero];
    self.auditCard.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditCard.backgroundColor = [UIColor whiteColor];
    self.auditCard.layer.cornerRadius = 8;
    self.auditCard.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1].CGColor;
    self.auditCard.layer.shadowOpacity = 0.08;
    self.auditCard.layer.shadowOffset = CGSizeMake(0, 1);
    self.auditCard.layer.shadowRadius = 4;
    [self.contentView addSubview:self.auditCard];

    [NSLayoutConstraint activateConstraints:@[
        [self.auditCard.topAnchor constraintEqualToAnchor:self.floorplanContainer.bottomAnchor constant:16],
        [self.auditCard.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.auditCard.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.auditCard.heightAnchor constraintEqualToConstant:124]
    ]];

    UIView *innerView = [[UIView alloc] initWithFrame:CGRectZero];
    innerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.auditCard addSubview:innerView];
    [NSLayoutConstraint activateConstraints:@[
        [innerView.leadingAnchor constraintEqualToAnchor:self.auditCard.leadingAnchor constant:12],
        [innerView.trailingAnchor constraintEqualToAnchor:self.auditCard.trailingAnchor constant:-12],
        [innerView.topAnchor constraintEqualToAnchor:self.auditCard.topAnchor constant:14],
        [innerView.bottomAnchor constraintEqualToAnchor:self.auditCard.bottomAnchor constant:-14]
    ]];

    self.auditStateLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.auditStateLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditStateLabel.font = [UIFont boldSystemFontOfSize:14];
    self.auditStateLabel.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    self.auditStateLabel.text = @"审核状态";
    [innerView addSubview:self.auditStateLabel];

    self.auditSubtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.auditSubtitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditSubtitleLabel.font = [UIFont systemFontOfSize:12];
    self.auditSubtitleLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    self.auditSubtitleLabel.numberOfLines = 1;
    [innerView addSubview:self.auditSubtitleLabel];

    self.auditStackedBar = [[CDStackedBarView alloc] initWithFrame:CGRectZero];
    self.auditStackedBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditStackedBar.cornerRadius = 4;
    self.auditStackedBar.backgroundColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
    [innerView addSubview:self.auditStackedBar];

    self.pillIncompleteLabel = [self makePillLabelWithBackgroundColor:[UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0]
                                                            textColor:[UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0]];
    self.pillReviewingLabel = [self makePillLabelWithBackgroundColor:[UIColor colorWithRed:232/255.0 green:240/255.0 blue:255/255.0 alpha:1.0]
                                                           textColor:[UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0]];
    self.pillFailLabel = [self makePillLabelWithBackgroundColor:[UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0]
                                                      textColor:[UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0]];
    self.pillPassLabel = [self makePillLabelWithBackgroundColor:[UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0]
                                                      textColor:[UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0]];

    self.auditPillsStack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.pillIncompleteLabel,
        self.pillReviewingLabel,
        self.pillFailLabel,
        self.pillPassLabel
    ]];
    self.auditPillsStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditPillsStack.axis = UILayoutConstraintAxisHorizontal;
    self.auditPillsStack.alignment = UIStackViewAlignmentCenter;
    self.auditPillsStack.spacing = 8;
    self.auditPillsStack.distribution = UIStackViewDistributionFill;
    [innerView addSubview:self.auditPillsStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.auditStateLabel.leadingAnchor constraintEqualToAnchor:innerView.leadingAnchor],
        [self.auditStateLabel.topAnchor constraintEqualToAnchor:innerView.topAnchor],
        [self.auditStateLabel.trailingAnchor constraintEqualToAnchor:innerView.trailingAnchor],

        [self.auditSubtitleLabel.leadingAnchor constraintEqualToAnchor:innerView.leadingAnchor],
        [self.auditSubtitleLabel.topAnchor constraintEqualToAnchor:self.auditStateLabel.bottomAnchor constant:4],
        [self.auditSubtitleLabel.trailingAnchor constraintEqualToAnchor:innerView.trailingAnchor],

        [self.auditStackedBar.leadingAnchor constraintEqualToAnchor:innerView.leadingAnchor],
        [self.auditStackedBar.topAnchor constraintEqualToAnchor:self.auditSubtitleLabel.bottomAnchor constant:10],
        [self.auditStackedBar.trailingAnchor constraintEqualToAnchor:innerView.trailingAnchor],
        [self.auditStackedBar.heightAnchor constraintEqualToConstant:8],

        [self.auditPillsStack.leadingAnchor constraintEqualToAnchor:innerView.leadingAnchor],
        [self.auditPillsStack.topAnchor constraintEqualToAnchor:self.auditStackedBar.bottomAnchor constant:12],
        [self.auditPillsStack.trailingAnchor constraintLessThanOrEqualToAnchor:innerView.trailingAnchor],
        [self.auditPillsStack.bottomAnchor constraintEqualToAnchor:innerView.bottomAnchor]
    ]];
}

- (void)setupSectionTitle {
    UIView *sectionHeader = [[UIView alloc] initWithFrame:CGRectZero];
    sectionHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:sectionHeader];

    [NSLayoutConstraint activateConstraints:@[
        [sectionHeader.topAnchor constraintEqualToAnchor:self.auditCard.bottomAnchor constant:12],
        [sectionHeader.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [sectionHeader.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [sectionHeader.heightAnchor constraintEqualToConstant:20]
    ]];

    self.sectionTitle = [[UILabel alloc] initWithFrame:CGRectZero];
    self.sectionTitle.translatesAutoresizingMaskIntoConstraints = NO;
    self.sectionTitle.text = @"房间";
    self.sectionTitle.font = [UIFont boldSystemFontOfSize:13];
    self.sectionTitle.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    [sectionHeader addSubview:self.sectionTitle];

    UIView *countBadge = [[UIView alloc] initWithFrame:CGRectZero];
    countBadge.translatesAutoresizingMaskIntoConstraints = NO;
    countBadge.backgroundColor = [UIColor colorWithRed:224/255.0 green:237/255.0 blue:255/255.0 alpha:1.0];
    countBadge.layer.cornerRadius = 10;
    [sectionHeader addSubview:countBadge];

    self.roomCountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.roomCountLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.roomCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.roomList.count];
    self.roomCountLabel.font = [UIFont systemFontOfSize:11];
    self.roomCountLabel.textColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    self.roomCountLabel.textAlignment = NSTextAlignmentCenter;
    [countBadge addSubview:self.roomCountLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.sectionTitle.leadingAnchor constraintEqualToAnchor:sectionHeader.leadingAnchor],
        [self.sectionTitle.centerYAnchor constraintEqualToAnchor:sectionHeader.centerYAnchor],

        [countBadge.leadingAnchor constraintEqualToAnchor:self.sectionTitle.trailingAnchor constant:6],
        [countBadge.centerYAnchor constraintEqualToAnchor:sectionHeader.centerYAnchor],
        [countBadge.heightAnchor constraintEqualToConstant:18],

        [self.roomCountLabel.leadingAnchor constraintEqualToAnchor:countBadge.leadingAnchor constant:6],
        [self.roomCountLabel.trailingAnchor constraintEqualToAnchor:countBadge.trailingAnchor constant:-6],
        [self.roomCountLabel.topAnchor constraintEqualToAnchor:countBadge.topAnchor],
        [self.roomCountLabel.bottomAnchor constraintEqualToAnchor:countBadge.bottomAnchor],
        [countBadge.widthAnchor constraintGreaterThanOrEqualToConstant:20]
    ]];

    // roomTableView 依赖 sectionHeader 的 bottom 做布局
    sectionHeader.accessibilityIdentifier = @"sectionHeader";
}

- (void)setupRoomTableView {
    self.roomTableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    self.roomTableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.roomTableView.delegate = self;
    self.roomTableView.dataSource = self;
    self.roomTableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    self.roomTableView.scrollEnabled = NO;
    self.roomTableView.backgroundColor = [UIColor clearColor];
    self.roomTableView.rowHeight = 90;
    [self.roomTableView registerClass:[CDRoomCardCell class] forCellReuseIdentifier:@"RoomCard"];
    [self.contentView addSubview:self.roomTableView];

    UIView *sectionHeader = nil;
    for (UIView *subview in self.contentView.subviews) {
        if ([subview.accessibilityIdentifier isEqualToString:@"sectionHeader"]) {
            sectionHeader = subview;
            break;
        }
    }

    NSLayoutYAxisAnchor *topAnchor = sectionHeader ? sectionHeader.bottomAnchor : self.auditCard.bottomAnchor;
    self.roomTableHeightConstraint = [self.roomTableView.heightAnchor constraintEqualToConstant:0];
    [NSLayoutConstraint activateConstraints:@[
        [self.roomTableView.topAnchor constraintEqualToAnchor:topAnchor constant:4],
        [self.roomTableView.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor],
        [self.roomTableView.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor],
        self.roomTableHeightConstraint,
        [self.roomTableView.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16]
    ]];
}

- (void)setupBottomBar {
    self.bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBar.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.bottomBar];

    self.bottomBarHeightConstraint = [self.bottomBar.heightAnchor constraintEqualToConstant:84];
    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        self.bottomBarHeightConstraint
    ]];

    UIView *topLine = [[UIView alloc] initWithFrame:CGRectZero];
    topLine.translatesAutoresizingMaskIntoConstraints = NO;
    topLine.backgroundColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
    [self.bottomBar addSubview:topLine];
    [NSLayoutConstraint activateConstraints:@[
        [topLine.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor],
        [topLine.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor],
        [topLine.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor],
        [topLine.heightAnchor constraintEqualToConstant:1]
    ]];

    self.submitBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.submitBtn.translatesAutoresizingMaskIntoConstraints = NO;
    [self.submitBtn setTitle:@"提交" forState:UIControlStateNormal];
    self.submitBtn.backgroundColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    [self.submitBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.submitBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.submitBtn.layer.cornerRadius = 4;
    [self.submitBtn addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:self.submitBtn];
    [NSLayoutConstraint activateConstraints:@[
        [self.submitBtn.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:16],
        [self.submitBtn.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-16],
        [self.submitBtn.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:10],
        [self.submitBtn.heightAnchor constraintEqualToConstant:48]
    ]];

    self.submitHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.submitHintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.submitHintLabel.font = [UIFont systemFontOfSize:12];
    self.submitHintLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    self.submitHintLabel.textAlignment = NSTextAlignmentCenter;
    self.submitHintLabel.text = @"";
    [self.bottomBar addSubview:self.submitHintLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.submitHintLabel.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:16],
        [self.submitHintLabel.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-16],
        [self.submitHintLabel.topAnchor constraintEqualToAnchor:self.submitBtn.bottomAnchor constant:6],
        [self.submitHintLabel.heightAnchor constraintEqualToConstant:16]
    ]];

    [self updateBottomBarHeight];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.floorplanGradientLayer.frame = self.floorplanOverlayView.bounds;
}

- (void)viewSafeAreaInsetsDidChange {
    [super viewSafeAreaInsetsDidChange];
    [self updateBottomBarHeight];
}

- (void)updateBottomBarHeight {
    CGFloat bottomH = 84;
    if (@available(iOS 11.0, *)) {
        bottomH += self.view.safeAreaInsets.bottom;
    }
    self.bottomBarHeightConstraint.constant = bottomH;
}

- (void)updateRoomTableHeight {
    self.roomCountLabel.text = [NSString stringWithFormat:@"%lu", (unsigned long)self.roomList.count];
    self.roomTableHeightConstraint.constant = self.roomList.count * 90.0;
}

- (void)refreshOverviewUI {
    NSInteger total = self.roomList.count;
    NSInteger captured = 0;
    NSInteger reviewing = 0;
    NSInteger fail = 0;
    NSInteger pass = 0;

    for (CDRoomItem *room in self.roomList) {
        if (!room.captureComplete) continue;
        captured += 1;
        if (room.auditStatus == 1) reviewing += 1;
        else if (room.auditStatus == 2) pass += 1;
        else if (room.auditStatus == 3) fail += 1;
    }

    NSInteger incomplete = total - captured;
    NSInteger audited = pass + fail;

    CGFloat captureProgress = total > 0 ? (captured * 1.0 / total) : 0;
    self.progressDonut.progress = captureProgress;
    self.progressDonut.centerText = [NSString stringWithFormat:@"%ld/%ld", (long)captured, (long)total];

    if (incomplete > 0) {
        self.auditStateLabel.text = @"先完成采集";
        self.auditSubtitleLabel.text = [NSString stringWithFormat:@"完成采集后才会进入审核（已进入审核：%ld/%ld）", (long)captured, (long)total];
    } else if (reviewing > 0) {
        self.auditStateLabel.text = @"审核进行中";
        self.auditSubtitleLabel.text = [NSString stringWithFormat:@"已出结果 %ld/%ld · 审核中 %ld", (long)audited, (long)captured, (long)reviewing];
    } else {
        self.auditStateLabel.text = @"审核已完成";
        if (fail == 0 && total > 0) {
            self.auditSubtitleLabel.text = @"全部房间已通过审核";
        } else if (fail > 0) {
            self.auditSubtitleLabel.text = [NSString stringWithFormat:@"未通过 %ld/%ld", (long)fail, (long)captured];
        } else {
            self.auditSubtitleLabel.text = @"";
        }
    }

    self.pillIncompleteLabel.text = [NSString stringWithFormat:@"未采集 %ld", (long)incomplete];
    self.pillReviewingLabel.text = [NSString stringWithFormat:@"审核中 %ld", (long)reviewing];
    self.pillFailLabel.text = [NSString stringWithFormat:@"未通过 %ld", (long)fail];
    self.pillPassLabel.text = [NSString stringWithFormat:@"已通过 %ld", (long)pass];

    self.auditStackedBar.values = @[@(reviewing), @(fail), @(pass)];
    self.auditStackedBar.colors = @[
        [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0],
        [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0],
        [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0]
    ];

    BOOL canSubmit = (total > 0 && incomplete == 0 && reviewing == 0 && fail == 0 && pass == total);
    self.submitBtn.enabled = canSubmit;
    if (canSubmit) {
        self.submitBtn.backgroundColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
        self.submitHintLabel.text = @"全部房间已通过审核，可提交";
    } else {
        self.submitBtn.backgroundColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
        if (incomplete > 0) {
            self.submitHintLabel.text = [NSString stringWithFormat:@"不可提交：还有 %ld 个房间未完成采集", (long)incomplete];
        } else if (reviewing > 0) {
            self.submitHintLabel.text = [NSString stringWithFormat:@"不可提交：还有 %ld 个房间审核中", (long)reviewing];
        } else if (fail > 0) {
            self.submitHintLabel.text = [NSString stringWithFormat:@"不可提交：有 %ld 个房间未通过审核", (long)fail];
        } else {
            self.submitHintLabel.text = @"不可提交：审核未完成";
        }
    }

    [self updateRoomTableHeight];
    [self.roomTableView reloadData];
}

#pragma mark - StatusBar

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

#pragma mark - UITableViewDataSource

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.roomList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CDRoomCardCell *cell = [tableView dequeueReusableCellWithIdentifier:@"RoomCard" forIndexPath:indexPath];
    if (indexPath.row < self.roomList.count) {
        [cell configWithRoom:self.roomList[indexPath.row]];
    }
    return cell;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.row >= self.roomList.count) return;
    CDRoomItem *room = self.roomList[indexPath.row];
    CDRoomVideoReviewViewController *vc = [[CDRoomVideoReviewViewController alloc] initWithRoom:room];
    [self.navigationController pushViewController:vc animated:YES];
}

#pragma mark - Actions

- (void)submitTapped {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提交" message:@"确认提交所有房间视频？" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"确认" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        NSLog(@"提交成功");
    }]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
