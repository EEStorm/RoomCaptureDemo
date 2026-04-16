#import "CDStereoCameraViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>

@interface CDStereoCameraChannel : NSObject
@property (nonatomic, strong) AVCaptureDevice *device;
@property (nonatomic, strong) AVCaptureDeviceInput *input;
@property (nonatomic, strong) AVCaptureMovieFileOutput *movieOutput;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) UIView *tileView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) NSURL *recordingURL;
@property (nonatomic, copy) NSString *displayName;
@end

@implementation CDStereoCameraChannel
@end

@interface CDStereoCameraViewController () <AVCaptureFileOutputRecordingDelegate>

@property (nonatomic, strong) AVCaptureMultiCamSession *session;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;
@property (nonatomic, strong) NSMutableArray<CDStereoCameraChannel *> *channels;
@property (nonatomic, strong) UIView *previewContainer;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UILabel *recordHintLabel;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) NSTimer *uiTimer;
@property (nonatomic, assign) BOOL didAttemptSetup;
@property (nonatomic, assign) BOOL sessionConfigured;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) NSTimeInterval recordingStartedAt;
@property (nonatomic, assign) NSInteger pendingStops;
@property (nonatomic, strong) NSMutableArray<NSURL *> *finishedRecordingURLs;
@property (nonatomic, strong) dispatch_queue_t exportQueue;

@end

@implementation CDStereoCameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"双目相机";
    self.view.backgroundColor = [UIColor blackColor];
    self.sessionQueue = dispatch_queue_create("com.example.captureDemo.stereo.session", DISPATCH_QUEUE_SERIAL);
    self.exportQueue = dispatch_queue_create("com.example.captureDemo.stereo.export", DISPATCH_QUEUE_SERIAL);
    self.channels = [NSMutableArray array];
    self.finishedRecordingURLs = [NSMutableArray array];
    [self setupUI];
}

- (void)dealloc {
    [self.uiTimer invalidate];
    if (self.session) {
        [self.session stopRunning];
    }
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.didAttemptSetup) {
        self.didAttemptSetup = YES;
        [self requestPermissionsAndSetupIfNeeded];
    } else if (self.sessionConfigured) {
        [self startSessionIfNeeded];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:NO];

    if (self.isRecording) {
        [self stopRecording];
    }

    [self stopUITimer];
    dispatch_async(self.sessionQueue, ^{
        if (self.session.isRunning) {
            [self.session stopRunning];
        }
    });
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    self.previewContainer.frame = self.view.bounds;

    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;

    self.backButton.frame = CGRectMake(16.0, safeTop + 10.0, 32.0, 32.0);
    self.titleLabel.frame = CGRectMake(60.0, safeTop + 6.0, width - 120.0, 24.0);
    self.statusLabel.frame = CGRectMake(24.0, CGRectGetMaxY(self.titleLabel.frame) + 4.0, width - 48.0, 18.0);

    CGFloat controlsHeight = 144.0 + safeBottom;
    CGFloat controlsTop = height - controlsHeight;
    self.recordHintLabel.frame = CGRectMake(24.0, controlsTop + 10.0, width - 48.0, 18.0);
    self.recordButton.frame = CGRectMake((width - 84.0) / 2.0, controlsTop + 30.0, 84.0, 84.0);
    self.durationLabel.frame = CGRectMake(24.0, CGRectGetMaxY(self.recordButton.frame) + 2.0, width - 48.0, 22.0);

    [self layoutPreviewTiles];
    [self updateRecordButtonAppearance];
}

- (void)setupUI {
    self.previewContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    self.previewContainer.backgroundColor = [UIColor blackColor];
    [self.view addSubview:self.previewContainer];

    UIView *topFade = [[UIView alloc] initWithFrame:CGRectZero];
    topFade.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.30];
    topFade.userInteractionEnabled = NO;
    topFade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleBottomMargin;
    topFade.frame = CGRectMake(0, 0, self.view.bounds.size.width, 88);
    [self.view addSubview:topFade];

    UIView *bottomFade = [[UIView alloc] initWithFrame:CGRectZero];
    bottomFade.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.38];
    bottomFade.userInteractionEnabled = NO;
    bottomFade.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    bottomFade.frame = CGRectMake(0, self.view.bounds.size.height - 156, self.view.bounds.size.width, 156);
    [self.view addSubview:bottomFade];

    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.backButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    self.backButton.tintColor = [UIColor whiteColor];
    [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.backButton];

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = @"双目分镜拍摄";
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.textColor = [UIColor whiteColor];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:18.0];
    [self.view addSubview:self.titleLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.text = @"准备加载相机";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.82];
    self.statusLabel.font = [UIFont systemFontOfSize:12.0];
    self.statusLabel.numberOfLines = 1;
    [self.view addSubview:self.statusLabel];

    self.recordHintLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.recordHintLabel.text = @"将同时录制所有可用镜头";
    self.recordHintLabel.textAlignment = NSTextAlignmentCenter;
    self.recordHintLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.82];
    self.recordHintLabel.font = [UIFont systemFontOfSize:12.0];
    [self.view addSubview:self.recordHintLabel];

    self.recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.recordButton.layer.cornerRadius = 42.0;
    self.recordButton.layer.borderWidth = 4.0;
    self.recordButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.recordButton.backgroundColor = [UIColor clearColor];
    [self.recordButton addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.recordButton];

    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.durationLabel.text = @"00:00.0";
    self.durationLabel.textAlignment = NSTextAlignmentCenter;
    self.durationLabel.textColor = [UIColor whiteColor];
    self.durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:20.0 weight:UIFontWeightSemibold];
    self.durationLabel.hidden = YES;
    [self.view addSubview:self.durationLabel];

    [self updateRecordButtonAppearance];
}

- (void)requestPermissionsAndSetupIfNeeded {
    [self updateStatus:@"检查相机权限..."];

    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL videoGranted) {
        if (!videoGranted) {
            [self showSimpleAlertWithTitle:@"无法访问相机" message:@"请在系统设置中允许相机权限后重试。"];
            [self updateStatus:@"相机权限未开启"];
            return;
        }

        [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (status != PHAuthorizationStatusAuthorized && status != PHAuthorizationStatusLimited) {
                    [self showSimpleAlertWithTitle:@"无法写入相册" message:@"请在系统设置中允许添加到相册，否则无法保存录制结果。"];
                    [self updateStatus:@"相册写入权限未开启"];
                    return;
                }

                [self configureSessionIfNeeded];
            });
        }];
    }];
}

- (void)configureSessionIfNeeded {
    if (self.sessionConfigured) {
        [self startSessionIfNeeded];
        return;
    }

    if (![AVCaptureMultiCamSession isMultiCamSupported]) {
        [self updateStatus:@"当前设备不支持多路相机"];
        [self showSimpleAlertWithTitle:@"设备不支持" message:@"当前设备不支持同时开启多个摄像头。"];
        return;
    }

    [self updateStatus:@"正在配置多路相机..."];

    dispatch_async(self.sessionQueue, ^{
        AVCaptureMultiCamSession *session = [[AVCaptureMultiCamSession alloc] init];
        NSMutableArray<CDStereoCameraChannel *> *configuredChannels = [NSMutableArray array];

        NSArray<AVCaptureDevice *> *devices = [self discoverCandidateDevices];
        for (AVCaptureDevice *device in devices) {
            CDStereoCameraChannel *channel = [self buildChannelForDevice:device inSession:session];
            if (channel) {
                [configuredChannels addObject:channel];
            }
        }

        if (configuredChannels.count == 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self updateStatus:@"没有可用的多路镜头"];
                [self showSimpleAlertWithTitle:@"配置失败" message:@"没有成功接入可同时工作的后置镜头。"];
            });
            return;
        }

        self.session = session;
        self.sessionConfigured = YES;
        self.channels = configuredChannels;

        dispatch_async(dispatch_get_main_queue(), ^{
            [self installPreviewTiles];
            [self layoutPreviewTiles];
            [self updateStatus:[NSString stringWithFormat:@"已接入 %lu 路镜头，竖屏录制已开启", (unsigned long)self.channels.count]];
            [self startSessionIfNeeded];
        });
    });
}

- (NSArray<AVCaptureDevice *> *)discoverCandidateDevices {
    AVCaptureDeviceDiscoverySession *discovery = [AVCaptureDeviceDiscoverySession
                                                  discoverySessionWithDeviceTypes:@[
        AVCaptureDeviceTypeBuiltInUltraWideCamera,
        AVCaptureDeviceTypeBuiltInWideAngleCamera,
        AVCaptureDeviceTypeBuiltInTelephotoCamera
    ]
                                                  mediaType:AVMediaTypeVideo
                                                   position:AVCaptureDevicePositionBack];

    NSMutableArray<AVCaptureDevice *> *orderedDevices = [NSMutableArray array];
    NSArray<NSString *> *preferredTypes = @[
        AVCaptureDeviceTypeBuiltInUltraWideCamera,
        AVCaptureDeviceTypeBuiltInWideAngleCamera,
        AVCaptureDeviceTypeBuiltInTelephotoCamera
    ];

    for (NSString *type in preferredTypes) {
        for (AVCaptureDevice *device in discovery.devices) {
            if ([device.deviceType isEqualToString:type]) {
                [orderedDevices addObject:device];
            }
        }
    }

    return orderedDevices;
}

- (CDStereoCameraChannel *)buildChannelForDevice:(AVCaptureDevice *)device inSession:(AVCaptureMultiCamSession *)session {
    NSError *inputError = nil;
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:&inputError];
    if (!inputError && [session canAddInput:input]) {
        [session addInputWithNoConnections:input];
    } else {
        return nil;
    }

    AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    if ([session canAddOutput:movieOutput]) {
        [session addOutputWithNoConnections:movieOutput];
    } else {
        return nil;
    }

    AVCaptureInputPort *videoPort = nil;
    for (AVCaptureInputPort *port in input.ports) {
        if ([port.mediaType isEqualToString:AVMediaTypeVideo]) {
            videoPort = port;
            break;
        }
    }
    if (!videoPort) {
        return nil;
    }

    AVCaptureConnection *movieConnection = [AVCaptureConnection connectionWithInputPorts:@[videoPort] output:movieOutput];
    if (![session canAddConnection:movieConnection]) {
        return nil;
    }
    movieConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    if (movieConnection.isVideoStabilizationSupported) {
        movieConnection.preferredVideoStabilizationMode = AVCaptureVideoStabilizationModeAuto;
    }
    [session addConnection:movieConnection];

    AVCaptureVideoPreviewLayer *previewLayer = [AVCaptureVideoPreviewLayer layerWithSessionWithNoConnection:session];
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;

    AVCaptureConnection *previewConnection = [AVCaptureConnection connectionWithInputPort:videoPort videoPreviewLayer:previewLayer];
    if (![session canAddConnection:previewConnection]) {
        return nil;
    }
    previewConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
    [session addConnection:previewConnection];

    CDStereoCameraChannel *channel = [[CDStereoCameraChannel alloc] init];
    channel.device = device;
    channel.input = input;
    channel.movieOutput = movieOutput;
    channel.previewLayer = previewLayer;
    channel.displayName = [self displayNameForDevice:device];
    return channel;
}

- (NSString *)displayNameForDevice:(AVCaptureDevice *)device {
    if ([device.deviceType isEqualToString:AVCaptureDeviceTypeBuiltInUltraWideCamera]) {
        return @"0.5x 超广角";
    }
    if ([device.deviceType isEqualToString:AVCaptureDeviceTypeBuiltInWideAngleCamera]) {
        return @"1.0x 广角";
    }
    if ([device.deviceType isEqualToString:AVCaptureDeviceTypeBuiltInTelephotoCamera]) {
        return @"长焦";
    }
    return device.localizedName ?: @"镜头";
}

- (void)installPreviewTiles {
    for (UIView *subview in [self.previewContainer.subviews copy]) {
        [subview removeFromSuperview];
    }

    for (CDStereoCameraChannel *channel in self.channels) {
        UIView *tileView = [[UIView alloc] initWithFrame:CGRectZero];
        tileView.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1.0];
        tileView.layer.cornerRadius = 18.0;
        tileView.layer.masksToBounds = YES;

        channel.previewLayer.frame = tileView.bounds;
        [tileView.layer addSublayer:channel.previewLayer];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.text = channel.displayName;
        label.textColor = [UIColor whiteColor];
        label.font = [UIFont boldSystemFontOfSize:12.0];
        label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
        label.textAlignment = NSTextAlignmentCenter;
        [tileView addSubview:label];

        channel.tileView = tileView;
        channel.titleLabel = label;
        [self.previewContainer addSubview:tileView];
    }
}

- (void)layoutPreviewTiles {
    NSUInteger count = self.channels.count;
    if (count == 0) {
        return;
    }

    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat safeBottom = self.view.safeAreaInsets.bottom;
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = self.view.bounds.size.height;
    CGFloat topInset = safeTop + 56.0;
    CGFloat bottomInset = 154.0 + safeBottom;
    CGFloat availableWidth = width - 32.0;
    CGFloat availableHeight = height - topInset - bottomInset;
    CGFloat spacing = 12.0;

    NSUInteger columns = count <= 2 ? 1 : 2;
    NSUInteger rows = (count + columns - 1) / columns;

    CGFloat maxTileWidthByColumns = (availableWidth - spacing * (columns - 1)) / columns;
    CGFloat maxTileHeightByRows = (availableHeight - spacing * (rows - 1)) / rows;
    CGFloat tileWidth = MIN(maxTileWidthByColumns, maxTileHeightByRows * 9.0 / 16.0);
    CGFloat tileHeight = tileWidth * 16.0 / 9.0;

    CGFloat contentWidth = columns * tileWidth + spacing * (columns - 1);
    CGFloat contentHeight = rows * tileHeight + spacing * (rows - 1);
    CGFloat originX = (width - contentWidth) / 2.0;
    CGFloat originY = topInset + MAX(0.0, (availableHeight - contentHeight) / 2.0);

    for (NSUInteger idx = 0; idx < count; idx++) {
        CDStereoCameraChannel *channel = self.channels[idx];
        NSUInteger row = idx / columns;
        NSUInteger column = idx % columns;
        CGRect tileFrame = CGRectMake(originX + column * (tileWidth + spacing),
                                      originY + row * (tileHeight + spacing),
                                      tileWidth,
                                      tileHeight);
        channel.tileView.frame = tileFrame;
        channel.previewLayer.frame = channel.tileView.bounds;
        channel.titleLabel.frame = CGRectMake(8.0, 8.0, tileFrame.size.width - 16.0, 24.0);
        channel.titleLabel.layer.cornerRadius = 12.0;
        channel.titleLabel.layer.masksToBounds = YES;
    }
}

- (void)startSessionIfNeeded {
    dispatch_async(self.sessionQueue, ^{
        if (self.session && !self.session.isRunning) {
            [self.session startRunning];
        }
    });
}

- (void)toggleRecording {
    if (!self.sessionConfigured || self.channels.count == 0) {
        [self showSimpleAlertWithTitle:@"尚未就绪" message:@"相机还没有准备完成，请稍后再试。"];
        return;
    }

    if (self.isRecording) {
        [self stopRecording];
    } else {
        [self startRecording];
    }
}

- (void)startRecording {
    if (self.isRecording) {
        return;
    }

    [self.finishedRecordingURLs removeAllObjects];
    self.pendingStops = 0;
    self.isRecording = YES;
    self.recordingStartedAt = CACurrentMediaTime();
    self.durationLabel.hidden = NO;
    self.recordHintLabel.text = @"正在同步录制所有镜头";
    [self updateStatus:@"开始录制..."];
    [self startUITimer];
    [self updateRecordButtonAppearance];

    dispatch_async(self.sessionQueue, ^{
        for (CDStereoCameraChannel *channel in self.channels) {
            if (channel.movieOutput.isRecording) {
                continue;
            }

            NSURL *outputURL = [self temporaryURLForDeviceName:channel.displayName];
            channel.recordingURL = outputURL;
            self.pendingStops += 1;
            [channel.movieOutput startRecordingToOutputFileURL:outputURL recordingDelegate:self];
        }
    });
}

- (void)stopRecording {
    if (!self.isRecording) {
        return;
    }

    self.recordHintLabel.text = @"停止中...";
    [self updateStatus:@"正在结束录制..."];

    dispatch_async(self.sessionQueue, ^{
        for (CDStereoCameraChannel *channel in self.channels) {
            if (channel.movieOutput.isRecording) {
                [channel.movieOutput stopRecording];
            }
        }
    });
}

- (NSURL *)temporaryURLForDeviceName:(NSString *)deviceName {
    NSString *safeName = [[deviceName stringByReplacingOccurrencesOfString:@" " withString:@"_"]
                          stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *filename = [NSString stringWithFormat:@"%@_%@.mov",
                          safeName,
                          [[NSUUID UUID] UUIDString]];
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:filename];
    return [NSURL fileURLWithPath:path];
}

- (void)captureOutput:(AVCaptureFileOutput *)output
didStartRecordingToOutputFileAtURL:(NSURL *)fileURL
      fromConnections:(NSArray<AVCaptureConnection *> *)connections {
    dispatch_async(dispatch_get_main_queue(), ^{
        [self updateStatus:[NSString stringWithFormat:@"录制中，共 %lu 路", (unsigned long)self.channels.count]];
    });
}

- (void)captureOutput:(AVCaptureFileOutput *)output
didFinishRecordingToOutputFileAtURL:(NSURL *)outputFileURL
      fromConnections:(NSArray<AVCaptureConnection *> *)connections
                error:(NSError *)error {
    if (!error && outputFileURL) {
        @synchronized (self.finishedRecordingURLs) {
            [self.finishedRecordingURLs addObject:outputFileURL];
        }
    }

    BOOL shouldFinalize = NO;
    @synchronized (self) {
        self.pendingStops = MAX(0, self.pendingStops - 1);
        shouldFinalize = (self.pendingStops == 0);
    }

    if (shouldFinalize) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.isRecording = NO;
            [self stopUITimer];
            [self updateRecordButtonAppearance];
            self.recordHintLabel.text = @"正在整理并保存到相册";
            [self updateStatus:@"导出竖屏视频并写入相册..."];
            [self finalizeRecordings];
        });
    }
}

- (void)finalizeRecordings {
    NSArray<NSURL *> *urls = [self.finishedRecordingURLs copy];
    if (urls.count == 0) {
        self.durationLabel.hidden = YES;
        self.recordHintLabel.text = @"录制失败，请重试";
        [self updateStatus:@"没有拿到有效视频文件"];
        [self showSimpleAlertWithTitle:@"录制失败" message:@"没有生成可保存的视频文件。"];
        return;
    }

    [self updateStatus:[NSString stringWithFormat:@"准备保存 %lu 条视频...", (unsigned long)urls.count]];

    dispatch_async(self.exportQueue, ^{
        NSInteger savedCount = 0;
        NSError *lastError = nil;

        for (NSUInteger idx = 0; idx < urls.count; idx++) {
            @autoreleasepool {
                NSURL *sourceURL = urls[idx];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self updateStatus:[NSString stringWithFormat:@"正在保存第 %lu/%lu 条视频...",
                                        (unsigned long)(idx + 1),
                                        (unsigned long)urls.count]];
                });

                dispatch_semaphore_t waitSemaphore = dispatch_semaphore_create(0);
                __block NSURL *finalURL = nil;
                __block NSError *stepError = nil;

                [self exportVideoToPortraitIfNeeded:sourceURL completion:^(NSURL * _Nullable exportedURL, NSError * _Nullable error) {
                    finalURL = exportedURL;
                    stepError = error;
                    dispatch_semaphore_signal(waitSemaphore);
                }];
                dispatch_semaphore_wait(waitSemaphore, DISPATCH_TIME_FOREVER);

                if (!stepError && finalURL) {
                    dispatch_semaphore_t saveSemaphore = dispatch_semaphore_create(0);
                    [self saveVideoToPhotoLibrary:finalURL completion:^(NSError * _Nullable saveError) {
                        stepError = saveError;
                        dispatch_semaphore_signal(saveSemaphore);
                    }];
                    dispatch_semaphore_wait(saveSemaphore, DISPATCH_TIME_FOREVER);
                }

                if (!stepError) {
                    savedCount += 1;
                } else {
                    lastError = stepError;
                }

                [[NSFileManager defaultManager] removeItemAtURL:sourceURL error:nil];
                if (finalURL && ![finalURL isEqual:sourceURL]) {
                    [[NSFileManager defaultManager] removeItemAtURL:finalURL error:nil];
                }
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            self.durationLabel.hidden = YES;
            if (savedCount == urls.count) {
                self.recordHintLabel.text = @"已保存到系统相册";
                [self updateStatus:[NSString stringWithFormat:@"保存完成，共 %ld 条视频", (long)savedCount]];
            } else {
                self.recordHintLabel.text = @"部分视频保存失败";
                [self updateStatus:@"保存时出现异常"];
                NSString *message = lastError.localizedDescription ?: @"请检查相册权限或设备存储空间。";
                [self showSimpleAlertWithTitle:@"保存未完成" message:message];
            }
        });
    });
}

- (void)exportVideoToPortraitIfNeeded:(NSURL *)sourceURL
                           completion:(void (^)(NSURL * _Nullable finalURL, NSError * _Nullable error))completion {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!videoTrack) {
        completion(nil, [NSError errorWithDomain:@"CDStereoCameraErrorDomain"
                                            code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"无法读取视频轨道"}]);
        return;
    }

    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *compositionVideoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                                                                                 preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *insertError = nil;
    [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration)
                                   ofTrack:videoTrack
                                    atTime:kCMTimeZero
                                     error:&insertError];
    if (insertError) {
        completion(nil, insertError);
        return;
    }

    CGAffineTransform preferredTransform = videoTrack.preferredTransform;
    CGRect transformedRect = CGRectApplyAffineTransform(CGRectMake(0, 0, videoTrack.naturalSize.width, videoTrack.naturalSize.height),
                                                        preferredTransform);
    CGSize renderSize = CGSizeMake(fabs(transformedRect.size.width), fabs(transformedRect.size.height));
    if (renderSize.width < 1.0 || renderSize.height < 1.0) {
        renderSize = CGSizeMake(videoTrack.naturalSize.height, videoTrack.naturalSize.width);
    }

    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    videoComposition.renderSize = renderSize;
    Float64 nominalFPS = videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30.0;
    videoComposition.frameDuration = CMTimeMake(1, (int32_t)lrint(nominalFPS));

    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, composition.duration);

    AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compositionVideoTrack];
    [layerInstruction setTransform:preferredTransform atTime:kCMTimeZero];
    instruction.layerInstructions = @[layerInstruction];
    videoComposition.instructions = @[instruction];

    NSURL *outputURL = [self temporaryNormalizedURL];
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition
                                                                           presetName:AVAssetExportPresetHighestQuality];
    exportSession.outputURL = outputURL;
    exportSession.outputFileType = AVFileTypeMPEG4;
    exportSession.shouldOptimizeForNetworkUse = YES;
    exportSession.videoComposition = videoComposition;

    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        switch (exportSession.status) {
            case AVAssetExportSessionStatusCompleted:
                completion(outputURL, nil);
                break;
            case AVAssetExportSessionStatusFailed:
            case AVAssetExportSessionStatusCancelled:
                completion(nil, exportSession.error ?: [NSError errorWithDomain:@"CDStereoCameraErrorDomain"
                                                                           code:-2
                                                                       userInfo:@{NSLocalizedDescriptionKey: @"视频导出失败"}]);
                break;
            default:
                completion(nil, [NSError errorWithDomain:@"CDStereoCameraErrorDomain"
                                                    code:-3
                                                userInfo:@{NSLocalizedDescriptionKey: @"视频导出未完成"}]);
                break;
        }
    }];
}

- (NSURL *)temporaryNormalizedURL {
    NSString *filename = [NSString stringWithFormat:@"stereo_portrait_%@.mp4", [[NSUUID UUID] UUIDString]];
    return [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:filename]];
}

- (void)saveVideoToPhotoLibrary:(NSURL *)fileURL completion:(void (^)(NSError * _Nullable error))completion {
    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
        [PHAssetCreationRequest creationRequestForAssetFromVideoAtFileURL:fileURL];
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (!success && !error) {
            error = [NSError errorWithDomain:@"CDStereoCameraErrorDomain"
                                        code:-4
                                    userInfo:@{NSLocalizedDescriptionKey: @"写入相册失败"}];
        }
        completion(error);
    }];
}

- (void)startUITimer {
    [self stopUITimer];
    self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                     target:self
                                                   selector:@selector(updateDurationLabel)
                                                 userInfo:nil
                                                  repeats:YES];
}

- (void)stopUITimer {
    [self.uiTimer invalidate];
    self.uiTimer = nil;
}

- (void)updateDurationLabel {
    if (!self.isRecording) {
        return;
    }

    NSTimeInterval duration = MAX(0.0, CACurrentMediaTime() - self.recordingStartedAt);
    NSInteger minutes = (NSInteger)(duration / 60.0);
    NSInteger seconds = (NSInteger)duration % 60;
    NSInteger tenths = (NSInteger)floor((duration - floor(duration)) * 10.0);
    self.durationLabel.text = [NSString stringWithFormat:@"%02ld:%02ld.%01ld",
                               (long)minutes,
                               (long)seconds,
                               (long)tenths];
}

- (void)updateRecordButtonAppearance {
    for (CALayer *layer in [self.recordButton.layer.sublayers copy]) {
        [layer removeFromSuperlayer];
    }

    CGFloat outerSize = CGRectGetWidth(self.recordButton.bounds);
    if (outerSize <= 0.0) {
        outerSize = 84.0;
    }

    CGFloat innerSize = self.isRecording ? 34.0 : 70.0;
    CGFloat inset = (outerSize - innerSize) / 2.0;

    CAShapeLayer *shapeLayer = [CAShapeLayer layer];
    shapeLayer.frame = CGRectMake(inset, inset, innerSize, innerSize);
    UIBezierPath *path = self.isRecording
    ? [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, innerSize, innerSize) cornerRadius:6.0]
    : [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, innerSize, innerSize)];
    shapeLayer.path = path.CGPath;
    shapeLayer.fillColor = [UIColor redColor].CGColor;
    [self.recordButton.layer addSublayer:shapeLayer];
}

- (void)updateStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.statusLabel.text = status;
    });
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showSimpleAlertWithTitle:(NSString *)title message:(NSString *)message {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:alert animated:YES completion:nil];
    });
}

@end
