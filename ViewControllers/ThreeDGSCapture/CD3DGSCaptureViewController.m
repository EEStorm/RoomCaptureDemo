#import "CD3DGSCaptureViewController.h"
#import "CD3DGSCameraService.h"
#import "CD3DGSMetrics.h"
#import "CD3DGSVideoListViewController.h"
#import "CDCameraSettingsViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <Vision/Vision.h>
#import <QuartzCore/QuartzCore.h>

@interface CD3DGSCaptureViewController () {
    double _translationRatios[12];
}

@property (nonatomic, assign) BOOL previousNavigationBarHidden;
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *paramsLabel;
@property (nonatomic, strong) UIView *recordingIndicator;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) NSTimer *uiTimer;

@property (nonatomic, strong) UILabel *translationLabel;
@property (nonatomic, strong) UILabel *rotationLabel;
@property (nonatomic, strong) UILabel *blurLabel;
@property (nonatomic, strong) UILabel *shakeLabel;
@property (nonatomic, strong) UIView *warningBorderView;
@property (nonatomic, strong) UIView *metricsContainer;
@property (nonatomic, strong) UILabel *lockStatusTag;

@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) NSOperationQueue *motionQueue;
@property (nonatomic, assign) double lastRotationDegreesPerSecond;
@property (nonatomic, assign) double filteredRotationDegreesPerSecond;
@property (nonatomic, assign) double lastAccelerationMagnitude;
@property (nonatomic, assign) double accelWindowSum;
@property (nonatomic, assign) NSUInteger accelWindowCount;
@property (nonatomic, assign) NSUInteger accelWindowIndex;
@property (nonatomic, assign) BOOL shakeVisible;
@property (nonatomic, strong) NSTimer *shakeHideTimer;
@property (nonatomic, assign) NSTimeInterval lastShakeTimestamp;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *accelWindow;

@property (nonatomic, assign) CVPixelBufferRef analysisBufferA;
@property (nonatomic, assign) CVPixelBufferRef analysisBufferB;
@property (nonatomic, assign) BOOL analysisUseAForWrite;
@property (nonatomic, assign) BOOL hasPrevAnalysisFrame;
@property (nonatomic, assign) NSUInteger translationRatioCount;
@property (nonatomic, assign) NSUInteger translationRatioIndex;

@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) NSTimer *toastHideTimer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastToastAtByKey;
@property (nonatomic, strong) AVSpeechSynthesizer *speechSynthesizer;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *lastSpokenAtByKey;

@end

@implementation CD3DGSCaptureViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"3DGS拍摄";
    self.view.backgroundColor = [UIColor blackColor];
    self.motionManager = [[CMMotionManager alloc] init];
    self.motionQueue = [[NSOperationQueue alloc] init];
    self.motionQueue.maxConcurrentOperationCount = 1;
    self.accelWindow = [NSMutableArray array];
    self.lastToastAtByKey = [NSMutableDictionary dictionary];
    self.lastSpokenAtByKey = [NSMutableDictionary dictionary];
    self.speechSynthesizer = [[AVSpeechSynthesizer alloc] init];
    [self setupUI];
    [self setupCamera];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsDidChange)
                                                 name:@"CDCameraSettingsDidChange"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(lockStatusDidChange)
                                                 name:@"CD3DGSCameraParametersLockDidChange"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.toastHideTimer invalidate];
    if (_analysisBufferA) {
        CVPixelBufferRelease(_analysisBufferA);
        _analysisBufferA = nil;
    }
    if (_analysisBufferB) {
        CVPixelBufferRelease(_analysisBufferB);
        _analysisBufferB = nil;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat screenWidth = self.view.bounds.size.width;

    UIView *previewContainer = [self.view viewWithTag:100];
    previewContainer.frame = self.view.bounds;
    self.previewLayer.frame = previewContainer.bounds;

    self.topBar.frame = CGRectMake(0, safeTop, screenWidth, 100);

    UIView *centerContainer = self.topBar.subviews.count > 2 ? self.topBar.subviews[2] : nil;
    if (centerContainer) {
        centerContainer.frame = CGRectMake(60, 20, screenWidth - 120, 60);
        UILabel *resLabel = [centerContainer viewWithTag:300];
        if (resLabel) {
            resLabel.frame = CGRectMake(0, 0, centerContainer.bounds.size.width, 25);
        }
        self.paramsLabel.frame = CGRectMake(0, 28, centerContainer.bounds.size.width, 25);
    }

    self.backButton.frame = CGRectMake(16, 35, 30, 30);
    self.settingsButton.frame = CGRectMake(screenWidth - 46, 35, 30, 30);
    self.durationLabel.frame = CGRectMake(screenWidth - 120, 64, 90, 24);
    self.recordingIndicator.frame = CGRectMake(screenWidth - 28, 70, 12, 12);

    UIView *bottomBar = [self.view viewWithTag:200];
    if (!bottomBar) {
        bottomBar = [self.view.subviews lastObject];
    }
    if (bottomBar) {
        bottomBar.frame = CGRectMake(0, self.view.bounds.size.height - 180, screenWidth, 180);
        if (self.recordButton) {
            CGFloat btnSize = 80;
            CGFloat btnX = (screenWidth - btnSize) / 2;
            self.recordButton.frame = CGRectMake(btnX, 50, btnSize, btnSize);
        }
    }

    self.metricsContainer.frame = CGRectMake(12, safeTop + 112, screenWidth - 24, 56);
    self.shakeLabel.frame = CGRectMake((screenWidth - 160) / 2, safeTop + 176, 160, 32);
    CGFloat toastY = self.view.bounds.size.height - self.view.safeAreaInsets.bottom - 180 - 12 - 44;
    self.toastLabel.frame = CGRectMake(16, toastY, screenWidth - 32, 44);
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    if (self.navigationController) {
        self.previousNavigationBarHidden = self.navigationController.navigationBarHidden;
        [self.navigationController setNavigationBarHidden:YES animated:animated];
    }
    [[CD3DGSCameraService shared] startSession];
    [self startUITimer];
    [self startMotionUpdates];
    [self attachSampleBufferHandler];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    if ((self.isMovingFromParentViewController || self.isBeingDismissed) && self.navigationController) {
        [self.navigationController setNavigationBarHidden:self.previousNavigationBarHidden animated:animated];
    }
    [[CD3DGSCameraService shared] stopSession];
    [[CD3DGSCameraService shared] setSampleBufferHandler:nil];
    [self stopMotionUpdates];
    [self stopUITimer];
}

- (void)settingsDidChange {
    [self updateSettingsLabels];
}

- (void)lockStatusDidChange {
    [self updateLockStatusTag];
}

- (void)setupUI {
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat screenWidth = self.view.bounds.size.width;

    UIView *previewContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    previewContainer.backgroundColor = [UIColor blackColor];
    previewContainer.tag = 100;
    [self.view addSubview:previewContainer];

    self.topBar = [[UIView alloc] initWithFrame:CGRectMake(0, safeTop, screenWidth, 100)];
    [self.view addSubview:self.topBar];

    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backButton.frame = CGRectMake(16, 35, 30, 30);
    UIImage *backImg = [UIImage systemImageNamed:@"chevron.left"];
    [self.backButton setImage:backImg forState:UIControlStateNormal];
    self.backButton.tintColor = [UIColor whiteColor];
    [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.backButton];

    self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.settingsButton.frame = CGRectMake(screenWidth - 46, 35, 30, 30);
    UIImage *gearImg = [UIImage systemImageNamed:@"gearshape.fill"];
    [self.settingsButton setImage:gearImg forState:UIControlStateNormal];
    self.settingsButton.tintColor = [UIColor whiteColor];
    [self.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.settingsButton];

    UIView *centerContainer = [[UIView alloc] init];
    centerContainer.frame = CGRectMake(60, 20, screenWidth - 120, 60);
    [self.topBar addSubview:centerContainer];

    UILabel *resLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, centerContainer.bounds.size.width, 25)];
    resLabel.text = @"1080P 30fps";
    resLabel.textColor = [UIColor whiteColor];
    resLabel.font = [UIFont boldSystemFontOfSize:14];
    resLabel.textAlignment = NSTextAlignmentCenter;
    resLabel.tag = 300;
    [centerContainer addSubview:resLabel];

    self.paramsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 28, centerContainer.bounds.size.width, 25)];
    self.paramsLabel.text = @"参数读取中…";
    self.paramsLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.paramsLabel.font = [UIFont systemFontOfSize:12];
    self.paramsLabel.textAlignment = NSTextAlignmentCenter;
    [centerContainer addSubview:self.paramsLabel];

    self.recordingIndicator = [[UIView alloc] initWithFrame:CGRectMake(screenWidth - 28, 70, 12, 12)];
    self.recordingIndicator.backgroundColor = [UIColor redColor];
    self.recordingIndicator.layer.cornerRadius = 6;
    self.recordingIndicator.hidden = YES;
    [self.topBar addSubview:self.recordingIndicator];

    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(screenWidth - 120, 64, 90, 24)];
    self.durationLabel.text = @"00:00.0";
    self.durationLabel.textColor = [UIColor whiteColor];
    self.durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
    self.durationLabel.textAlignment = NSTextAlignmentRight;
    self.durationLabel.hidden = YES;
    [self.topBar addSubview:self.durationLabel];

    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 180, screenWidth, 180)];
    bottomBar.tag = 200;
    [self.view addSubview:bottomBar];

    self.warningBorderView = [[UIView alloc] initWithFrame:previewContainer.bounds];
    self.warningBorderView.userInteractionEnabled = NO;
    self.warningBorderView.layer.borderWidth = 0;
    self.warningBorderView.layer.borderColor = [UIColor systemRedColor].CGColor;
    self.warningBorderView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [previewContainer addSubview:self.warningBorderView];

    self.metricsContainer = [[UIView alloc] initWithFrame:CGRectMake(12, safeTop + 112, screenWidth - 24, 56)];
    self.metricsContainer.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.45];
    self.metricsContainer.layer.cornerRadius = 12;
    self.metricsContainer.layer.borderWidth = 1;
    self.metricsContainer.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10].CGColor;
    self.metricsContainer.clipsToBounds = YES;
    [self.view addSubview:self.metricsContainer];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 10, 120, 18)];
    titleLabel.text = @"拍摄辅助";
    titleLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.90];
    titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    [self.metricsContainer addSubview:titleLabel];

    self.lockStatusTag = [[UILabel alloc] initWithFrame:CGRectMake(self.metricsContainer.bounds.size.width - 12 - 88, 8, 88, 20)];
    self.lockStatusTag.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.lockStatusTag.font = [UIFont systemFontOfSize:10 weight:UIFontWeightSemibold];
    self.lockStatusTag.textAlignment = NSTextAlignmentCenter;
    self.lockStatusTag.layer.cornerRadius = 10;
    self.lockStatusTag.clipsToBounds = YES;
    [self.metricsContainer addSubview:self.lockStatusTag];
    self.lockStatusTag.userInteractionEnabled = YES;
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(lockTagTapped)];
    [self.lockStatusTag addGestureRecognizer:tap];

    self.translationLabel = [[UILabel alloc] initWithFrame:CGRectMake(12, 30, 120, 22)];
    self.translationLabel.text = @"移动 不可用";
    self.translationLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.translationLabel.textAlignment = NSTextAlignmentCenter;
    self.translationLabel.layer.cornerRadius = 2;
    self.translationLabel.clipsToBounds = YES;
    [self.metricsContainer addSubview:self.translationLabel];

    self.rotationLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(self.translationLabel.frame) + 8, 30, 96, 22)];
    self.rotationLabel.text = @"旋转 --";
    self.rotationLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.rotationLabel.textAlignment = NSTextAlignmentCenter;
    self.rotationLabel.layer.cornerRadius = 2;
    self.rotationLabel.clipsToBounds = YES;
    [self.metricsContainer addSubview:self.rotationLabel];

    self.blurLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(self.rotationLabel.frame) + 8, 30, 84, 22)];
    self.blurLabel.text = @"清晰 不可判";
    self.blurLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.blurLabel.textAlignment = NSTextAlignmentCenter;
    self.blurLabel.layer.cornerRadius = 2;
    self.blurLabel.clipsToBounds = YES;
    [self.metricsContainer addSubview:self.blurLabel];

    UILabel *noteLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(self.blurLabel.frame) + 8, 30, self.metricsContainer.bounds.size.width - CGRectGetMaxX(self.blurLabel.frame) - 20, 22)];
    noteLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    noteLabel.text = @"慢走、少转、稳拿";
    noteLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.70];
    noteLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightRegular];
    [self.metricsContainer addSubview:noteLabel];

    self.shakeLabel = [[UILabel alloc] initWithFrame:CGRectMake((screenWidth - 160) / 2, safeTop + 176, 160, 32)];
    self.shakeLabel.text = @"拿稳手机";
    self.shakeLabel.textColor = [UIColor whiteColor];
    self.shakeLabel.backgroundColor = [[UIColor colorWithRed:0xE8/255.0 green:0x22/255.0 blue:0x22/255.0 alpha:1.0] colorWithAlphaComponent:0.92];
    self.shakeLabel.layer.cornerRadius = 12;
    self.shakeLabel.clipsToBounds = YES;
    self.shakeLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.shakeLabel.textAlignment = NSTextAlignmentCenter;
    self.shakeLabel.hidden = YES;
    [self.view addSubview:self.shakeLabel];

    self.toastLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, self.view.bounds.size.height - 180 - 12 - 44, screenWidth - 32, 44)];
    self.toastLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
    self.toastLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.72];
    self.toastLabel.textColor = [UIColor whiteColor];
    self.toastLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    self.toastLabel.textAlignment = NSTextAlignmentCenter;
    self.toastLabel.numberOfLines = 2;
    self.toastLabel.layer.cornerRadius = 12;
    self.toastLabel.clipsToBounds = YES;
    self.toastLabel.hidden = YES;
    [self.view addSubview:self.toastLabel];

    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, screenWidth, 20)];
    self.hintLabel.text = @"点击录制按钮开始采集";
    self.hintLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.hintLabel.font = [UIFont systemFontOfSize:13];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    [bottomBar addSubview:self.hintLabel];

    UIButton *listBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    listBtn.frame = CGRectMake(50, 60, 60, 70);
    UIImage *folderImg = [UIImage systemImageNamed:@"folder.fill"];
    [listBtn setImage:folderImg forState:UIControlStateNormal];
    listBtn.tintColor = [UIColor whiteColor];
    [listBtn setTitle:@"视频" forState:UIControlStateNormal];
    listBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [listBtn addTarget:self action:@selector(showVideoList) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:listBtn];

    CGFloat btnSize = 80;
    CGFloat btnX = (screenWidth - btnSize) / 2;
    CGFloat btnY = 50;
    self.recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    self.recordButton.frame = CGRectMake(btnX, btnY, btnSize, btnSize);
    self.recordButton.layer.borderWidth = 4;
    self.recordButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.recordButton.layer.cornerRadius = 40;
    self.recordButton.clipsToBounds = NO;
    self.recordButton.exclusiveTouch = YES;
    [self.recordButton addTarget:self action:@selector(toggleRecording) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:self.recordButton];

    [self updateRecordButton:NO];

    [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.translationLabel prefix:@"移动"];
    [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.rotationLabel prefix:@"旋转"];
    [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.blurLabel prefix:nil];
    self.blurLabel.text = @"清晰 不可判";
    [self updateLockStatusTag];
}

- (void)setupCamera {
    dispatch_async(dispatch_get_main_queue(), ^{
        AVCaptureVideoPreviewLayer *preview = [[CD3DGSCameraService shared] setupCamera];
        if (!preview) {
            [self showAlert:@"相机错误" message:@"无法初始化相机"];
            return;
        }

        self.previewLayer = preview;
        preview.frame = self.view.bounds;

        UIView *container = [self.view viewWithTag:100];
        [container.layer addSublayer:preview];

        [[CD3DGSCameraService shared] startSession];
        [self updateSettingsLabels];
        [self updateLockStatusTag];
    });
}

- (void)updateLockStatusTag {
    BOOL locked = [CD3DGSCameraService shared].parametersLocked;
    NSString *summary = [CD3DGSCameraService shared].parametersLockSummary ?: @"";
    NSString *text = locked ? @"参数已锁定" : @"参数异常";
    UIColor *bg = locked ? [[UIColor colorWithRed:0xEB/255.0 green:0xFF/255.0 blue:0xF7/255.0 alpha:1.0] colorWithAlphaComponent:0.92] : [[UIColor colorWithRed:0xFE/255.0 green:0xED/255.0 blue:0xED/255.0 alpha:1.0] colorWithAlphaComponent:0.92];
    UIColor *fg = locked ? [UIColor colorWithRed:0x00/255.0 green:0xA6/255.0 blue:0x66/255.0 alpha:1.0] : [UIColor colorWithRed:0xE8/255.0 green:0x22/255.0 blue:0x22/255.0 alpha:1.0];

    dispatch_async(dispatch_get_main_queue(), ^{
        self.lockStatusTag.text = text;
        self.lockStatusTag.backgroundColor = bg;
        self.lockStatusTag.textColor = fg;
        self.lockStatusTag.accessibilityLabel = summary;
    });
}

- (void)lockTagTapped {
    NSString *summary = [CD3DGSCameraService shared].parametersLockSummary ?: @"";
    if (summary.length == 0) {
        summary = @"参数状态未知";
    }
    [self showAlert:@"参数状态" message:summary];
}

- (void)showSettings {
    CDCameraSettingsViewController *settingsVC = [[CDCameraSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)ensureAnalysisBuffersIfNeeded {
    if (self.analysisBufferA && self.analysisBufferB) {
        return;
    }
    NSDictionary *attrs = @{ (id)kCVPixelBufferIOSurfacePropertiesKey: @{} };
    CVPixelBufferRef a = nil;
    CVPixelBufferRef b = nil;
    CVReturn r1 = CVPixelBufferCreate(kCFAllocatorDefault, 160, 120, kCVPixelFormatType_OneComponent8, (__bridge CFDictionaryRef)attrs, &a);
    CVReturn r2 = CVPixelBufferCreate(kCFAllocatorDefault, 160, 120, kCVPixelFormatType_OneComponent8, (__bridge CFDictionaryRef)attrs, &b);
    if (r1 != kCVReturnSuccess || r2 != kCVReturnSuccess) {
        if (a) CVPixelBufferRelease(a);
        if (b) CVPixelBufferRelease(b);
        return;
    }
    self.analysisBufferA = a;
    self.analysisBufferB = b;
    self.analysisUseAForWrite = YES;
    self.hasPrevAnalysisFrame = NO;
    self.translationRatioCount = 0;
    self.translationRatioIndex = 0;
}

- (void)resetTranslationStateWithMessage:(NSString *)message {
    self.hasPrevAnalysisFrame = NO;
    self.translationRatioCount = 0;
    self.translationRatioIndex = 0;
    dispatch_async(dispatch_get_main_queue(), ^{
        self.translationLabel.text = message;
        [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.translationLabel prefix:nil];
    });
}

- (void)showToast:(NSString *)message key:(NSString *)key minInterval:(NSTimeInterval)minInterval {
    if (message.length == 0 || key.length == 0) {
        return;
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval last = [self.lastToastAtByKey[key] doubleValue];
    if (last > 0 && (now - last) < minInterval) {
        return;
    }
    self.lastToastAtByKey[key] = @(now);

    dispatch_async(dispatch_get_main_queue(), ^{
        self.toastLabel.text = message;
        self.toastLabel.hidden = NO;
        self.toastLabel.alpha = 1.0;

        [self.toastHideTimer invalidate];
        __weak typeof(self) weakSelf = self;
        self.toastHideTimer = [NSTimer scheduledTimerWithTimeInterval:1.6 repeats:NO block:^(NSTimer * _Nonnull timer) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            [UIView animateWithDuration:0.18 animations:^{
                self.toastLabel.alpha = 0.0;
            } completion:^(BOOL finished) {
                self.toastLabel.hidden = YES;
                self.toastLabel.alpha = 1.0;
            }];
        }];
    });
}

- (void)speak:(NSString *)message key:(NSString *)key minInterval:(NSTimeInterval)minInterval {
    if (message.length == 0 || key.length == 0) {
        return;
    }
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSTimeInterval last = [self.lastSpokenAtByKey[key] doubleValue];
    if (last > 0 && (now - last) < minInterval) {
        return;
    }
    self.lastSpokenAtByKey[key] = @(now);

    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.speechSynthesizer.isSpeaking) {
            return;
        }
        AVSpeechUtterance *utterance = [[AVSpeechUtterance alloc] initWithString:message];
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate;
        utterance.pitchMultiplier = 1.0;
        utterance.volume = 0.9;
        [self.speechSynthesizer speakUtterance:utterance];
    });
}

- (void)grayStatsForBuffer:(CVPixelBufferRef)grayBuffer mean:(double *)meanOut std:(double *)stdOut min:(uint8_t *)minOut max:(uint8_t *)maxOut {
    if (meanOut) *meanOut = -1;
    if (stdOut) *stdOut = -1;
    if (minOut) *minOut = 0;
    if (maxOut) *maxOut = 0;
    if (!grayBuffer) return;

    CVPixelBufferLockBaseAddress(grayBuffer, kCVPixelBufferLock_ReadOnly);
    size_t width = CVPixelBufferGetWidth(grayBuffer);
    size_t height = CVPixelBufferGetHeight(grayBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(grayBuffer);
    const uint8_t *base = (const uint8_t *)CVPixelBufferGetBaseAddress(grayBuffer);
    if (!base || width == 0 || height == 0) {
        CVPixelBufferUnlockBaseAddress(grayBuffer, kCVPixelBufferLock_ReadOnly);
        return;
    }

    double sum = 0;
    double sumSq = 0;
    size_t count = 0;
    uint8_t minV = 255;
    uint8_t maxV = 0;

    for (size_t y = 0; y < height; y++) {
        const uint8_t *row = base + y * bytesPerRow;
        for (size_t x = 0; x < width; x++) {
            uint8_t v = row[x];
            sum += (double)v;
            sumSq += (double)v * (double)v;
            count += 1;
            if (v < minV) minV = v;
            if (v > maxV) maxV = v;
        }
    }

    CVPixelBufferUnlockBaseAddress(grayBuffer, kCVPixelBufferLock_ReadOnly);

    if (count == 0) return;
    double mean = sum / (double)count;
    double var = (sumSq / (double)count) - (mean * mean);
    double std = var > 0 ? sqrt(var) : 0;

    if (meanOut) *meanOut = mean;
    if (stdOut) *stdOut = std;
    if (minOut) *minOut = minV;
    if (maxOut) *maxOut = maxV;
}

- (void)applyTrafficLight:(CD3DGSTrafficLight)light toTag:(UILabel *)tag prefix:(NSString * _Nullable)prefix {
    UIColor *textColor = nil;
    UIColor *bgColor = nil;

    switch (light) {
        case CD3DGSTrafficLightGreen:
            textColor = [UIColor colorWithRed:0x00/255.0 green:0xA6/255.0 blue:0x66/255.0 alpha:1.0];
            bgColor = [[UIColor colorWithRed:0xEB/255.0 green:0xFF/255.0 blue:0xF7/255.0 alpha:1.0] colorWithAlphaComponent:0.92];
            break;
        case CD3DGSTrafficLightYellow:
            textColor = [UIColor colorWithRed:0xFA/255.0 green:0xA2/255.0 blue:0x41/255.0 alpha:1.0];
            bgColor = [[UIColor colorWithRed:0xFF/255.0 green:0xF3/255.0 blue:0xE0/255.0 alpha:1.0] colorWithAlphaComponent:0.92];
            break;
        case CD3DGSTrafficLightRed:
            textColor = [UIColor colorWithRed:0xE8/255.0 green:0x22/255.0 blue:0x22/255.0 alpha:1.0];
            bgColor = [[UIColor colorWithRed:0xFE/255.0 green:0xED/255.0 blue:0xED/255.0 alpha:1.0] colorWithAlphaComponent:0.92];
            break;
        case CD3DGSTrafficLightUnavailable:
        default:
            textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.75];
            bgColor = [[UIColor whiteColor] colorWithAlphaComponent:0.12];
            break;
    }

    tag.textColor = textColor;
    tag.backgroundColor = bgColor;

    if (prefix) {
        tag.text = [NSString stringWithFormat:@"%@ %@", prefix, [self labelForTrafficLight:light]];
    }
}

- (UIColor *)colorForTrafficLight:(CD3DGSTrafficLight)light {
    switch (light) {
        case CD3DGSTrafficLightGreen: return [UIColor systemGreenColor];
        case CD3DGSTrafficLightYellow: return [UIColor systemYellowColor];
        case CD3DGSTrafficLightRed: return [UIColor systemRedColor];
        case CD3DGSTrafficLightUnavailable: default: return [UIColor systemGrayColor];
    }
}

- (NSString *)labelForTrafficLight:(CD3DGSTrafficLight)light {
    switch (light) {
        case CD3DGSTrafficLightGreen: return @"适中";
        case CD3DGSTrafficLightYellow: return @"偏快";
        case CD3DGSTrafficLightRed: return @"过快";
        case CD3DGSTrafficLightUnavailable: default: return @"不可用";
    }
}

- (NSString *)blurTextForTrafficLight:(CD3DGSTrafficLight)light {
    switch (light) {
        case CD3DGSTrafficLightGreen: return @"清晰";
        case CD3DGSTrafficLightYellow: return @"注意";
        case CD3DGSTrafficLightRed: return @"模糊";
        case CD3DGSTrafficLightUnavailable: default: return @"不可判";
    }
}

- (void)attachSampleBufferHandler {
    __weak typeof(self) weakSelf = self;
    [[CD3DGSCameraService shared] setSampleBufferHandler:^(CMSampleBufferRef sampleBuffer) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self) return;
        if (!sampleBuffer) return;

        double rotationDegPerSec = self.filteredRotationDegreesPerSecond;
        if (![CD3DGSMetrics isTranslationEstimationAllowedForRotationDegreesPerSecond:rotationDegPerSec]) {
            [self resetTranslationStateWithMessage:@"移动：不可用(先别转太快)"];
            return;
        }

        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        if (!imageBuffer) {
            [self resetTranslationStateWithMessage:@"移动：不可用"];
            return;
        }

        [self ensureAnalysisBuffersIfNeeded];
        if (!self.analysisBufferA || !self.analysisBufferB) {
            [self resetTranslationStateWithMessage:@"移动：不可用"];
            return;
        }

        CVPixelBufferRef writeBuffer = self.analysisUseAForWrite ? self.analysisBufferA : self.analysisBufferB;
        CVPixelBufferRef readBuffer = self.analysisUseAForWrite ? self.analysisBufferB : self.analysisBufferA;

        CVPixelBufferLockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);
        size_t srcWidth = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
        size_t srcHeight = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
        size_t srcBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
        uint8_t *src = (uint8_t *)CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);

        CVPixelBufferLockBaseAddress(writeBuffer, 0);
        size_t dstBytesPerRow = CVPixelBufferGetBytesPerRow(writeBuffer);
        uint8_t *dst = (uint8_t *)CVPixelBufferGetBaseAddress(writeBuffer);

        // Nearest-neighbor downsample luma plane to 160x120.
        for (int y = 0; y < 120; y++) {
            size_t srcY = (size_t)((double)y * (double)srcHeight / 120.0);
            uint8_t *dstRow = dst + (size_t)y * dstBytesPerRow;
            uint8_t *srcRow = src + srcY * srcBytesPerRow;
            for (int x = 0; x < 160; x++) {
                size_t srcX = (size_t)((double)x * (double)srcWidth / 160.0);
                dstRow[x] = srcRow[srcX];
            }
        }

        CVPixelBufferUnlockBaseAddress(writeBuffer, 0);
        CVPixelBufferUnlockBaseAddress(imageBuffer, kCVPixelBufferLock_ReadOnly);

        if (!self.hasPrevAnalysisFrame) {
            self.hasPrevAnalysisFrame = YES;
            self.analysisUseAForWrite = !self.analysisUseAForWrite;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.translationLabel.text = @"移动：计算中…";
                self.translationLabel.textColor = [UIColor systemGrayColor];
            });
            return;
        }

        double lapVar = [self laplacianVarianceForGrayBuffer:writeBuffer];
        double mean = -1;
        double std = -1;
        uint8_t minV = 0;
        uint8_t maxV = 0;
        [self grayStatsForBuffer:writeBuffer mean:&mean std:&std min:&minV max:&maxV];
        double range = (double)maxV - (double)minV;

        BOOL isLowLight = (mean >= 0 && mean < 35.0);
        BOOL isLowTexture = (lapVar >= 0 && lapVar < 80.0);
        BOOL isWhiteWall = (mean >= 0 && mean > 180.0 && std >= 0 && std < 12.0 && range < 40.0 && isLowTexture);

        if (isLowLight) {
            self.translationRatioCount = 0;
            self.translationRatioIndex = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.translationLabel.text = @"移动 不可用（太暗）";
                [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.translationLabel prefix:nil];
            });
            [self showToast:@"光线太暗：先开灯/补光，再继续拍摄" key:@"low_light" minInterval:2.0];
            [self speak:@"光线太暗，请开灯或补光后再拍" key:@"low_light" minInterval:6.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.blurLabel.text = @"清晰 不可判";
                [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.blurLabel prefix:nil];
            });
            self.analysisUseAForWrite = !self.analysisUseAForWrite;
            return;
        }

        if (isWhiteWall) {
            self.translationRatioCount = 0;
            self.translationRatioIndex = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.translationLabel.text = @"移动 不可用（白墙）";
                [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.translationLabel prefix:nil];
            });
            [self showToast:@"疑似白墙/纯色墙：对准门框/家具边，停 1 秒再走" key:@"white_wall" minInterval:2.0];
            [self speak:@"请对准门框或家具边，停一秒再移动" key:@"white_wall" minInterval:8.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.blurLabel.text = @"清晰 不可判";
                [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.blurLabel prefix:nil];
            });
            self.analysisUseAForWrite = !self.analysisUseAForWrite;
            return;
        }

        if (isLowTexture) {
            self.translationRatioCount = 0;
            self.translationRatioIndex = 0;
            dispatch_async(dispatch_get_main_queue(), ^{
                self.translationLabel.text = @"移动 不可用（画面太平）";
                [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.translationLabel prefix:nil];
            });
            [self showToast:@"画面太平：对准门框/窗框/柜子边，停 1 秒再走" key:@"low_texture" minInterval:2.0];
            [self speak:@"画面太平，请对准门框或家具边再移动" key:@"low_texture" minInterval:8.0];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.blurLabel.text = @"清晰 不可判";
                [self applyTrafficLight:CD3DGSTrafficLightUnavailable toTag:self.blurLabel prefix:nil];
            });
            self.analysisUseAForWrite = !self.analysisUseAForWrite;
            return;
        }

        // Blur monitoring (only when not low light / not low texture).
        CD3DGSTrafficLight blurLight = CD3DGSTrafficLightGreen;
        if (lapVar >= 0 && lapVar < 140.0) {
            blurLight = CD3DGSTrafficLightRed;
        } else if (lapVar >= 0 && lapVar < 180.0) {
            blurLight = CD3DGSTrafficLightYellow;
        }
        NSString *blurText = [self blurTextForTrafficLight:blurLight];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.blurLabel.text = [NSString stringWithFormat:@"清晰 %@", blurText];
            [self applyTrafficLight:blurLight toTag:self.blurLabel prefix:nil];
        });
        if (blurLight == CD3DGSTrafficLightRed) {
            [self showToast:@"画面模糊：请停一下，双手握稳后再继续" key:@"blur" minInterval:2.0];
            [self speak:@"画面模糊，请停一下，握稳手机再继续" key:@"blur" minInterval:8.0];
        }

        NSError *error = nil;
        VNTranslationalImageRegistrationRequest *request = [[VNTranslationalImageRegistrationRequest alloc] initWithTargetedCVPixelBuffer:readBuffer options:@{}];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCVPixelBuffer:writeBuffer options:@{}];
        BOOL ok = [handler performRequests:@[request] error:&error];
        if (!ok || error) {
            [self resetTranslationStateWithMessage:@"移动：不可用(纹理不足)"];
            self.analysisUseAForWrite = !self.analysisUseAForWrite;
            return;
        }

        NSArray *results = request.results;
        if (results.count == 0) {
            [self resetTranslationStateWithMessage:@"移动：不可用(纹理不足)"];
            self.analysisUseAForWrite = !self.analysisUseAForWrite;
            return;
        }

        VNImageTranslationAlignmentObservation *obs = (VNImageTranslationAlignmentObservation *)results.firstObject;
        CGAffineTransform t = obs.alignmentTransform;
        double d = hypot((double)t.tx, (double)t.ty);
        double ratio = d / 160.0;

        self->_translationRatios[self.translationRatioIndex] = ratio;
        self.translationRatioIndex = (self.translationRatioIndex + 1) % 12;
        self.translationRatioCount = MIN((NSUInteger)12, self.translationRatioCount + 1);

        double sum = 0;
        for (NSUInteger i = 0; i < self.translationRatioCount; i++) {
            sum += self->_translationRatios[i];
        }
        double avg = (self.translationRatioCount > 0) ? (sum / (double)self.translationRatioCount) : ratio;
        CD3DGSTrafficLight light = [CD3DGSMetrics translationTrafficLightForRatio:avg];
        NSString *label = [self labelForTrafficLight:light];

        dispatch_async(dispatch_get_main_queue(), ^{
            self.translationLabel.text = [NSString stringWithFormat:@"移动 %@", label];
            [self applyTrafficLight:light toTag:self.translationLabel prefix:nil];
        });

        self.analysisUseAForWrite = !self.analysisUseAForWrite;
    }];
}

- (double)laplacianVarianceForGrayBuffer:(CVPixelBufferRef)grayBuffer {
    if (!grayBuffer) return -1;
    CVPixelBufferLockBaseAddress(grayBuffer, kCVPixelBufferLock_ReadOnly);
    size_t width = CVPixelBufferGetWidth(grayBuffer);
    size_t height = CVPixelBufferGetHeight(grayBuffer);
    size_t bytesPerRow = CVPixelBufferGetBytesPerRow(grayBuffer);
    const uint8_t *base = (const uint8_t *)CVPixelBufferGetBaseAddress(grayBuffer);
    if (!base || width < 3 || height < 3) {
        CVPixelBufferUnlockBaseAddress(grayBuffer, kCVPixelBufferLock_ReadOnly);
        return -1;
    }

    double sum = 0;
    double sumSq = 0;
    size_t count = 0;

    for (size_t y = 1; y + 1 < height; y++) {
        const uint8_t *row = base + y * bytesPerRow;
        const uint8_t *rowUp = base + (y - 1) * bytesPerRow;
        const uint8_t *rowDown = base + (y + 1) * bytesPerRow;
        for (size_t x = 1; x + 1 < width; x++) {
            int c = row[x];
            int lap = (row[x - 1] + row[x + 1] + rowUp[x] + rowDown[x]) - 4 * c;
            double v = (double)lap;
            sum += v;
            sumSq += v * v;
            count += 1;
        }
    }

    CVPixelBufferUnlockBaseAddress(grayBuffer, kCVPixelBufferLock_ReadOnly);

    if (count == 0) return -1;
    double mean = sum / (double)count;
    double var = (sumSq / (double)count) - (mean * mean);
    return var;
}

- (void)startMotionUpdates {
    if (self.motionManager.isGyroAvailable) {
        self.motionManager.gyroUpdateInterval = 1.0 / 30.0;
        __weak typeof(self) weakSelf = self;
        [self.motionManager startGyroUpdatesToQueue:self.motionQueue withHandler:^(CMGyroData * _Nullable gyroData, NSError * _Nullable error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !gyroData) return;
            double radPerSec = sqrt(gyroData.rotationRate.x * gyroData.rotationRate.x +
                                    gyroData.rotationRate.y * gyroData.rotationRate.y +
                                    gyroData.rotationRate.z * gyroData.rotationRate.z);
            double degPerSec = radPerSec * 180.0 / M_PI;
            self.lastRotationDegreesPerSecond = degPerSec;
            // EMA smoothing to reduce jitter sensitivity.
            const double alpha = 0.08;
            self.filteredRotationDegreesPerSecond = self.filteredRotationDegreesPerSecond * (1.0 - alpha) + degPerSec * alpha;

            CD3DGSTrafficLight light = [CD3DGSMetrics rotationTrafficLightForDegreesPerSecond:self.filteredRotationDegreesPerSecond];
            NSString *label = [self labelForTrafficLight:light];
            dispatch_async(dispatch_get_main_queue(), ^{
                self.rotationLabel.text = [NSString stringWithFormat:@"旋转 %@", label];
                [self applyTrafficLight:light toTag:self.rotationLabel prefix:nil];
            });
        }];
    }

    if (self.motionManager.isDeviceMotionAvailable) {
        self.motionManager.deviceMotionUpdateInterval = 1.0 / 50.0;
        __weak typeof(self) weakSelf = self;
        [self.motionManager startDeviceMotionUpdatesToQueue:self.motionQueue withHandler:^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self || !motion) return;
            double ax = motion.userAcceleration.x;
            double ay = motion.userAcceleration.y;
            double az = motion.userAcceleration.z;
            double mag = sqrt(ax * ax + ay * ay + az * az);
            [self handleAccelerationMagnitude:mag];
        }];
    }
}

- (void)stopMotionUpdates {
    [self.motionManager stopGyroUpdates];
    [self.motionManager stopDeviceMotionUpdates];
    self.lastRotationDegreesPerSecond = 0;
    self.filteredRotationDegreesPerSecond = 0;
    self.accelWindowSum = 0;
    self.accelWindowCount = 0;
    self.accelWindowIndex = 0;
    [self.accelWindow removeAllObjects];
    [self.shakeHideTimer invalidate];
    self.shakeHideTimer = nil;
    self.shakeLabel.hidden = YES;
    self.warningBorderView.layer.borderWidth = 0;
    self.shakeVisible = NO;
    self.lastShakeTimestamp = 0;
}

- (void)handleAccelerationMagnitude:(double)mag {
    const NSUInteger windowSize = 50; // ~1s at 50Hz

    if (self.accelWindowCount < windowSize) {
        [self.accelWindow addObject:@(mag)];
        self.accelWindowSum += mag;
        self.accelWindowCount += 1;
        self.accelWindowIndex = self.accelWindowCount % windowSize;
    } else {
        double old = [self.accelWindow[self.accelWindowIndex] doubleValue];
        self.accelWindow[self.accelWindowIndex] = @(mag);
        self.accelWindowSum += mag - old;
        self.accelWindowIndex = (self.accelWindowIndex + 1) % windowSize;
    }

    double avg = (self.accelWindowCount > 0) ? (self.accelWindowSum / (double)self.accelWindowCount) : 0;
    self.lastAccelerationMagnitude = mag;

    // P0: simple spike detection + floor to avoid noise triggering.
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    BOOL spike = (avg > 0.01) && (mag > MAX(0.14, avg * 2.2));
    if (spike && (now - self.lastShakeTimestamp > 0.8)) {
        self.lastShakeTimestamp = now;
        [self showShakeWarning];
    }
}

- (void)showShakeWarning {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.shakeLabel.hidden = NO;
        self.warningBorderView.layer.borderWidth = 3;
        self.shakeVisible = YES;

        [self.shakeHideTimer invalidate];
        __weak typeof(self) weakSelf = self;
        self.shakeHideTimer = [NSTimer scheduledTimerWithTimeInterval:0.35 repeats:NO block:^(NSTimer * _Nonnull timer) {
            __strong typeof(weakSelf) self = weakSelf;
            if (!self) return;
            self.shakeLabel.hidden = YES;
            self.warningBorderView.layer.borderWidth = 0;
            self.shakeVisible = NO;
        }];
    });
}

- (void)startUITimer {
    [self stopUITimer];
    self.uiTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                     target:self
                                                   selector:@selector(updateUI)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)stopUITimer {
    [self.uiTimer invalidate];
    self.uiTimer = nil;
}

- (void)updateUI {
    BOOL isRecording = [[CD3DGSCameraService shared] isRecording];
    NSTimeInterval duration = [[CD3DGSCameraService shared] recordingDuration];

    self.durationLabel.text = [self formatDuration:duration];
    self.durationLabel.hidden = !isRecording;
    self.recordingIndicator.hidden = !isRecording;
    self.hintLabel.text = isRecording ? @"录制中..." : @"点击录制按钮开始采集";

    if (isRecording) {
        static CGFloat alpha = 1.0;
        alpha = alpha > 0.5 ? 0.3 : 1.0;
        self.recordingIndicator.alpha = alpha;
    } else {
        self.recordingIndicator.alpha = 1.0;
    }

    [self updateRecordButton:isRecording];
}

- (void)updateRecordButton:(BOOL)isRecording {
    CGFloat btnSize = 80;
    CGFloat innerSize = isRecording ? 32 : 68;
    CGFloat offset = (btnSize - innerSize) / 2;

    for (CALayer *layer in [self.recordButton.layer.sublayers copy]) {
        if ([layer isKindOfClass:[CAShapeLayer class]]) {
            [layer removeFromSuperlayer];
        }
    }

    CAShapeLayer *innerLayer = [CAShapeLayer layer];
    innerLayer.frame = CGRectMake(offset, offset, innerSize, innerSize);

    UIBezierPath *path;
    if (isRecording) {
        path = [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, innerSize, innerSize) cornerRadius:4];
    } else {
        path = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(0, 0, innerSize, innerSize)];
    }
    innerLayer.path = path.CGPath;
    innerLayer.fillColor = [UIColor redColor].CGColor;

    [self.recordButton.layer addSublayer:innerLayer];
}

- (void)updateSettingsLabels {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    UILabel *resLabel = [self.topBar viewWithTag:300];
    NSInteger resolution = [defaults integerForKey:@"CDSettingsResolution"];
    NSArray *resolutions = @[@"720P", @"1080P", @"4K"];
    NSInteger frameRate = [defaults integerForKey:@"CDSettingsFrameRate"];
    if (frameRate == 0) frameRate = 30;
    resLabel.text = [NSString stringWithFormat:@"%@ %ldfps", resolutions[resolution], (long)frameRate];

    NSInteger cameraLens = [defaults integerForKey:@"CDSettingsCameraLens"];
    NSArray *lensNames = @[@"0.5x广角", @"1.0x广角"];
    float whiteBalance = [defaults floatForKey:@"CDSettingsWhiteBalance"];
    if (whiteBalance == 0) whiteBalance = 4500;
    float shutterSpeed = [defaults floatForKey:@"CDSettingsShutterSpeed"];
    if (shutterSpeed == 0) shutterSpeed = 250;
    float iso = [defaults floatForKey:@"CDSettingsISO"];
    if (iso == 0) iso = 320;
    id exposureModeObj = [defaults objectForKey:@"CDSettingsExposureMode"];
    NSInteger exposureMode = 0;
    if (exposureModeObj == nil) {
        BOOL legacyISOAuto = [defaults boolForKey:@"CDSettingsISOAuto"];
        exposureMode = legacyISOAuto ? 1 : 0;
    } else {
        exposureMode = [defaults integerForKey:@"CDSettingsExposureMode"];
    }
    float settleSeconds = [defaults floatForKey:@"CDSettingsAutoLockSettleSeconds"];
    if (settleSeconds <= 0) settleSeconds = 1.0f;
    NSTimeInterval lockedSeconds = [defaults doubleForKey:@"CDLastLockedExposureSeconds"];
    float lockedISO = [defaults floatForKey:@"CDLastLockedISO"];

    if (exposureMode == 0) {
        self.paramsLabel.text = [NSString stringWithFormat:@"%@ | %.0fK | 1/%.0f | ISO%.0f",
                                 lensNames[cameraLens], whiteBalance, shutterSpeed, iso];
    } else if (exposureMode == 1) {
        self.paramsLabel.text = [NSString stringWithFormat:@"%@ | %.0fK | ≤1/%.0f | ISO自适应",
                                 lensNames[cameraLens], whiteBalance, shutterSpeed];
    } else if (exposureMode == 2) {
        if (lockedSeconds > 0 && lockedISO > 0) {
            NSInteger roundedDenom = (NSInteger)llround(1.0 / lockedSeconds);
            self.paramsLabel.text = [NSString stringWithFormat:@"%@ | %.0fK | ≤1/%.0f | 已锁定 1/%ld ISO%.0f",
                                     lensNames[cameraLens], whiteBalance, shutterSpeed, (long)roundedDenom, lockedISO];
        } else {
            self.paramsLabel.text = [NSString stringWithFormat:@"%@ | %.0fK | ≤1/%.0f | 自动锁定(%.1fs)",
                                     lensNames[cameraLens], whiteBalance, shutterSpeed, settleSeconds];
        }
    } else {
        self.paramsLabel.text = [NSString stringWithFormat:@"%@ | %.0fK | ≤1/%.0f | 曝光模式%ld",
                                 lensNames[cameraLens], whiteBalance, shutterSpeed, (long)exposureMode];
    }
}

- (void)toggleRecording {
    if ([[CD3DGSCameraService shared] isRecording]) {
        [[CD3DGSCameraService shared] stopRecording];
    } else {
        [[CD3DGSCameraService shared] startRecording];
    }
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showVideoList {
    CD3DGSVideoListViewController *listVC = [[CD3DGSVideoListViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSString *)formatDuration:(NSTimeInterval)duration {
    int min = (int)duration / 60;
    int sec = (int)duration % 60;
    int tenths = (int)((duration - floor(duration)) * 10);
    return [NSString stringWithFormat:@"%02d:%02d.%d", min, sec, tenths];
}

@end
