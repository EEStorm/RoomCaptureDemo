#import "CD3DGSCaptureViewController.h"
#import "CD3DGSCaptureGuidanceState.h"
#import "CD3DGSCameraService.h"
#import "CD3DGSVideoListViewController.h"
#import "CDCameraSettingsViewController.h"
#import "../RoomShootFlow/CDRoomItem.h"
#import "../RoomShootFlow/CDRoomVideoReviewViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreMotion/CoreMotion.h>
#import <ImageIO/ImageIO.h>
#import <QuartzCore/QuartzCore.h>
#import "CaptureDemo-Swift.h"

@interface CD3DGSCaptureViewController ()

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) UIView *imuReservedContainerView;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) NSTimer *uiTimer;

@property (nonatomic, strong) UIView *toastContainerView;
@property (nonatomic, strong) UILabel *toastLabel;
@property (nonatomic, strong) UIView *imuStatusToastContainerView;
@property (nonatomic, strong) UILabel *imuStatusToastLabel;
@property (nonatomic, strong) UILabel *captureStepLabel;
@property (nonatomic, strong) UILabel *recordingDurationLabel;
@property (nonatomic, strong) UIButton *previousStepButton;
@property (nonatomic, strong) UILabel *previousStepLabel;
@property (nonatomic, strong) UIButton *nextStepButton;
@property (nonatomic, strong) UILabel *nextStepLabel;
@property (nonatomic, strong) CD3DGSCaptureGuidanceState *guidanceState;
@property (nonatomic, assign) BOOL isFinishingCurrentRecording;
@property (nonatomic, assign) BOOL isPreparingToRecord;
@property (nonatomic, strong) UIView *guideVideoOverlayView;
@property (nonatomic, strong) UIView *guideVideoFrameView;
@property (nonatomic, strong) UILabel *guideVideoTitleLabel;
@property (nonatomic, strong) UIButton *guideVideoSkipButton;
@property (nonatomic, strong) UILabel *countdownLabel;
@property (nonatomic, strong) AVPlayer *guideVideoPlayer;
@property (nonatomic, strong) AVPlayerLayer *guideVideoPlayerLayer;
@property (nonatomic, strong) NSTimer *countdownTimer;
@property (nonatomic, assign) NSInteger countdownValue;
@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) NSOperationQueue *motionQueue;
@property (nonatomic, strong) UIView *imuTopLimitLineView;
@property (nonatomic, strong) UIView *imuBottomLimitLineView;
@property (nonatomic, strong) UIView *imuCrossView;
@property (nonatomic, strong) UIView *imuCrossHorizontalLineView;
@property (nonatomic, strong) UIView *imuCrossVerticalLineView;
@property (nonatomic, strong) UILabel *imuPitchAngleLabel;
@property (nonatomic, strong) UILabel *imuAngularSpeedLabel;
@property (nonatomic, strong) UIView *imuWarningLabelContainerView;
@property (nonatomic, strong) UILabel *imuWarningLabel;
@property (nonatomic, strong) UILabel *imuMovementSpeedLabel;
@property (nonatomic, strong) UIView *imuLeftWarningView;
@property (nonatomic, strong) UIView *imuRightWarningView;
@property (nonatomic, strong) CAGradientLayer *imuLeftWarningGradientLayer;
@property (nonatomic, strong) CAGradientLayer *imuRightWarningGradientLayer;
@property (nonatomic, assign) CGFloat currentPitchDegrees;
@property (nonatomic, assign) CGFloat currentPitchOffsetY;
@property (nonatomic, assign) BOOL pitchWarningActive;
@property (nonatomic, assign) CGFloat currentAngularSpeedDegreesPerSecond;
@property (nonatomic, assign) BOOL angularSpeedWarningActive;
@property (nonatomic, strong) UIView *imuRollLeftLimitLineView;
@property (nonatomic, strong) UIView *imuRollRightLimitLineView;
@property (nonatomic, strong) UILabel *imuRollAngleLabel;
@property (nonatomic, strong) UIView *imuRollWarningLabelContainerView;
@property (nonatomic, strong) UILabel *imuRollWarningLabel;
@property (nonatomic, strong) UIView *imuTopWarningView;
@property (nonatomic, strong) UIView *imuBottomWarningView;
@property (nonatomic, strong) CAGradientLayer *imuTopWarningGradientLayer;
@property (nonatomic, strong) CAGradientLayer *imuBottomWarningGradientLayer;
@property (nonatomic, assign) CGFloat currentRollDegrees;
@property (nonatomic, assign) BOOL rollWarningActive;
@property (nonatomic, strong) UIView *stepGifContainerView;
@property (nonatomic, strong) UIImageView *stepGifImageView;
@property (nonatomic, strong) NSCache<NSString *, UIImage *> *stepGifCache;
@property (nonatomic, assign) NSInteger stepGifDisplayedIndex;
@property (nonatomic, assign) CGFloat currentMovementSpeedMetersPerSecond;
@property (nonatomic, assign) CGFloat movementVelocityX;
@property (nonatomic, assign) CGFloat movementVelocityY;
@property (nonatomic, assign) CGFloat movementVelocityZ;
@property (nonatomic, assign) BOOL movementWarningActive;
@property (nonatomic, strong) UIImpactFeedbackGenerator *warningImpactFeedbackGenerator;

@end

@implementation CD3DGSCaptureViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"3DGS拍摄";
    self.view.backgroundColor = [UIColor blackColor];
    self.guidanceState = [[CD3DGSCaptureGuidanceState alloc] init];
    self.warningImpactFeedbackGenerator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    self.stepGifCache = [[NSCache alloc] init];
    self.stepGifDisplayedIndex = NSNotFound;
    [self setupUI];
    [self setupCamera];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsDidChange)
                                                 name:@"CDCameraSettingsDidChange"
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(recordingDidFinish:)
                                                 name:CD3DGSCameraDidFinishRecordingNotification
                                              object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat screenWidth = self.view.bounds.size.width;

    UIView *previewContainer1 = [self.view viewWithTag:100];
    previewContainer1.frame = self.view.bounds;
    self.previewLayer.frame = previewContainer1.bounds;
    self.imuReservedContainerView.frame = self.view.bounds;

    self.topBar.frame = CGRectMake(0, safeTop, screenWidth, 96);

    UIView *centerContainer = self.topBar.subviews.count > 2 ? self.topBar.subviews[2] : nil;
    if (centerContainer) {
        centerContainer.frame = CGRectMake(64, 12, screenWidth - 128, 40);
        UILabel *titleLabel = [centerContainer viewWithTag:300];
        titleLabel.frame = centerContainer.bounds;
    }

    self.backButton.frame = CGRectMake(16, 17, 30, 30);
    self.settingsButton.frame = CGRectMake(screenWidth - 46, 17, 30, 30);
    self.captureStepLabel.frame = CGRectMake(16, 56, screenWidth - 32, 24);

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
        self.recordingDurationLabel.frame = CGRectMake((screenWidth - 120) / 2, 134, 120, 22);
        CGFloat stepSize = 54;
        CGFloat stepY = 50;
        CGFloat previousCenterX = MAX(76, screenWidth * 0.20);
        CGFloat nextCenterX = MIN(screenWidth - 76, screenWidth * 0.80);
        self.previousStepButton.frame = CGRectMake(previousCenterX - stepSize / 2, stepY, stepSize, stepSize);
        self.nextStepButton.frame = CGRectMake(nextCenterX - stepSize / 2, stepY, stepSize, stepSize);
        self.previousStepLabel.frame = CGRectMake(previousCenterX - 36, stepY + 55, 72, 20);
        self.nextStepLabel.frame = CGRectMake(nextCenterX - 36, stepY + 55, 72, 20);
    }

    CGFloat stepGifSize = 112.0;
    CGFloat stepGifX = 16.0;
    CGFloat stepGifY = CGRectGetMinY(bottomBar.frame) - stepGifSize - 12.0;
    self.stepGifContainerView.frame = CGRectMake(stepGifX,
                                                 MAX(safeTop + 8.0, stepGifY),
                                                 stepGifSize,
                                                 stepGifSize);
    self.stepGifImageView.frame = self.stepGifContainerView.bounds;

    CGFloat toastWidth = MIN(screenWidth - 48, 340);
    CGFloat toastHorizontalInset = 16;
    CGFloat toastVerticalInset = 12;
    CGFloat recordButtonTopY = self.view.bounds.size.height - 180 + 50;
    if (bottomBar && self.recordButton) {
        recordButtonTopY = CGRectGetMinY(bottomBar.frame) + CGRectGetMinY(self.recordButton.frame);
    }
    CGFloat toastMaxHeight = MAX(56, recordButtonTopY - 16 - safeTop - 12);
    CGSize toastTextSize = CGSizeMake(toastWidth - toastHorizontalInset * 2, CGFLOAT_MAX);
    CGRect toastTextRect = [self.toastLabel.text ?: @"" boundingRectWithSize:toastTextSize
                                                                      options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                                   attributes:@{NSFontAttributeName: self.toastLabel.font}
                                                                      context:nil];
    CGFloat toastHeight = MIN(MAX(ceil(toastTextRect.size.height) + toastVerticalInset * 2, 56), toastMaxHeight);
    CGFloat toastY = recordButtonTopY - 16 - toastHeight;
    self.toastContainerView.frame = CGRectMake((screenWidth - toastWidth) / 2, toastY, toastWidth, toastHeight);
    self.toastLabel.frame = CGRectInset(self.toastContainerView.bounds, toastHorizontalInset, toastVerticalInset);

    self.guideVideoOverlayView.frame = self.view.bounds;
    CGFloat guideWidth = MIN(screenWidth - 48, 360);
    CGFloat guideHeight = guideWidth * 9.0 / 16.0;
    CGFloat guideY = (self.view.bounds.size.height - guideHeight) / 2.0;
    self.guideVideoFrameView.frame = CGRectMake((screenWidth - guideWidth) / 2.0, guideY, guideWidth, guideHeight);
    self.guideVideoPlayerLayer.frame = CGRectInset(self.guideVideoFrameView.bounds, 4, 4);
    self.guideVideoTitleLabel.frame = CGRectMake(20, CGRectGetMinY(self.guideVideoFrameView.frame) - 72, screenWidth - 40, 56);
    self.guideVideoSkipButton.frame = CGRectMake(CGRectGetMaxX(self.guideVideoFrameView.frame) - 64, CGRectGetMinY(self.guideVideoFrameView.frame) - 44, 64, 32);
    self.countdownLabel.frame = self.guideVideoOverlayView.bounds;

    CGFloat sideWidth = 84.0;
    self.imuLeftWarningView.frame = CGRectMake(0, 0, sideWidth, self.view.bounds.size.height);
    self.imuRightWarningView.frame = CGRectMake(screenWidth - sideWidth, 0, sideWidth, self.view.bounds.size.height);
    self.imuLeftWarningGradientLayer.frame = self.imuLeftWarningView.bounds;
    self.imuRightWarningGradientLayer.frame = self.imuRightWarningView.bounds;

    CGFloat imuTop = CGRectGetMaxY(self.topBar.frame) + 14.0;
    CGFloat imuBottom = CGRectGetMinY(bottomBar.frame) - 14.0;
    CGFloat imuHeight = MAX(0, imuBottom - imuTop);
    CGFloat centerX = screenWidth * 0.5;
    CGFloat statusToastWidth = MIN(screenWidth - 72, 320);
    NSString *statusText = self.imuStatusToastLabel.text ?: @"";
    CGSize statusTextSize = CGSizeMake(statusToastWidth - 32, CGFLOAT_MAX);
    CGRect statusTextRect = [statusText boundingRectWithSize:statusTextSize
                                                     options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading
                                                  attributes:@{NSFontAttributeName: self.imuStatusToastLabel.font}
                                                     context:nil];
    CGFloat statusToastHeight = MIN(MAX(ceil(statusTextRect.size.height) + 22.0, 52.0), MAX(52.0, imuHeight * 0.20));
    CGFloat lowerLineBottomY = CGRectGetMaxY(self.imuBottomLimitLineView.frame);
    CGFloat statusToastAnchorY = lowerLineBottomY + 42.0;
    CGFloat statusToastMaxY = CGRectGetMinY(bottomBar.frame) - 8.0 - statusToastHeight;
    CGFloat statusToastY = MIN(MAX(statusToastAnchorY, imuTop), statusToastMaxY);
    self.imuStatusToastContainerView.frame = CGRectMake((screenWidth - statusToastWidth) / 2.0,
                                                        statusToastY,
                                                        statusToastWidth,
                                                        statusToastHeight);
    self.imuStatusToastLabel.frame = CGRectInset(self.imuStatusToastContainerView.bounds, 16.0, 11.0);
    CGFloat pitchCenterY = imuTop + imuHeight * 0.30;
    CGFloat rollCenterY = imuTop + imuHeight * 0.70;
    CGFloat maxOffset = 52.0;
    CGFloat lineWidth = 58.0;
    CGFloat lineHeight = 2.0;
    CGFloat movementScale = 1.0;
    if ([[CD3DGSCameraService shared] isRecording] && !self.isPreparingToRecord && !self.isFinishingCurrentRecording) {
        CGFloat normalizedSpeed = MIN(MAX(self.currentMovementSpeedMetersPerSecond, 0.0), 1.0);
        movementScale = MAX(0.42, 1.0 - 0.62 * pow(normalizedSpeed, 0.58));
    }
    CGFloat crossSize = 44.0 * movementScale;
    CGFloat pitchCrossCenterY = pitchCenterY + self.currentPitchOffsetY;
    CGFloat angleLabelX = MIN(screenWidth - 132.0, centerX + 56.0);
    CGFloat angleLabelWidth = MAX(88.0, MIN(122.0, screenWidth - angleLabelX - 16.0));
    CGFloat movementLabelWidth = MAX(100.0, MIN(144.0, centerX - 28.0));

    self.imuTopLimitLineView.frame = CGRectMake(centerX - lineWidth / 2.0, pitchCenterY - maxOffset, lineWidth, lineHeight);
    self.imuBottomLimitLineView.frame = CGRectMake(centerX - lineWidth / 2.0, pitchCenterY + maxOffset, lineWidth, lineHeight);
    self.imuCrossView.frame = CGRectMake(centerX - crossSize / 2.0, pitchCrossCenterY - crossSize / 2.0, crossSize, crossSize);
    self.imuCrossView.transform = CGAffineTransformMakeRotation((CGFloat)(self.currentRollDegrees * M_PI / 180.0));
    self.imuCrossHorizontalLineView.frame = CGRectMake(0, (crossSize - 3.0) / 2.0, crossSize, 3.0);
    self.imuCrossVerticalLineView.frame = CGRectMake((crossSize - 3.0) / 2.0, 0, 3.0, crossSize);
    self.imuPitchAngleLabel.frame = CGRectMake(centerX - angleLabelWidth / 2.0,
                                               MAX(imuTop, pitchCenterY - maxOffset - 30.0),
                                               angleLabelWidth,
                                               24.0);
    self.imuAngularSpeedLabel.frame = CGRectMake(centerX - angleLabelWidth / 2.0,
                                                  lowerLineBottomY + 10.0,
                                                  angleLabelWidth,
                                                  22.0);
    self.imuMovementSpeedLabel.frame = CGRectMake(16.0,
                                                  MAX(imuTop, pitchCenterY - 12.0),
                                                  movementLabelWidth,
                                                  24.0);

    CGFloat warningWidth = 168.0;
    CGFloat warningHeight = 34.0;
    self.imuWarningLabelContainerView.frame = CGRectMake((screenWidth - warningWidth) / 2.0,
                                                          CGRectGetMaxY(self.imuBottomLimitLineView.frame) + 18.0,
                                                          warningWidth,
                                                          warningHeight);
    self.imuWarningLabel.frame = CGRectInset(self.imuWarningLabelContainerView.bounds, 14, 6);

    CGFloat rollLineWidth = 2.0;
    CGFloat rollLineHeight = 58.0;

    self.imuRollLeftLimitLineView.frame = CGRectMake(centerX - maxOffset, rollCenterY - rollLineHeight / 2.0, rollLineWidth, rollLineHeight);
    self.imuRollRightLimitLineView.frame = CGRectMake(centerX + maxOffset, rollCenterY - rollLineHeight / 2.0, rollLineWidth, rollLineHeight);
    self.imuRollAngleLabel.frame = CGRectMake(angleLabelX,
                                              pitchCenterY - 12.0,
                                              angleLabelWidth,
                                              24.0);

    self.imuRollWarningLabelContainerView.frame = CGRectMake((screenWidth - warningWidth) / 2.0,
                                                             CGRectGetMaxY(self.imuRollRightLimitLineView.frame) + 18.0,
                                                             warningWidth,
                                                             warningHeight);
    self.imuRollWarningLabel.frame = CGRectInset(self.imuRollWarningLabelContainerView.bounds, 14, 6);

    [self.view bringSubviewToFront:self.guideVideoOverlayView];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [[CD3DGSCameraService shared] startSession];
    [self startUITimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [[CD3DGSCameraService shared] stopSession];
    [self stopUITimer];
    [self cancelPreparationFlow];
}

- (void)settingsDidChange {
    [self updateSettingsLabels];
}

- (void)setupUI {
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat screenWidth = self.view.bounds.size.width;

    UIView *previewContainer = [[UIView alloc] initWithFrame:self.view.bounds];
    previewContainer.backgroundColor = [UIColor blackColor];
    previewContainer.tag = 100;
    [self.view addSubview:previewContainer];

    self.imuReservedContainerView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.imuReservedContainerView.backgroundColor = [UIColor clearColor];
    self.imuReservedContainerView.userInteractionEnabled = NO;
    [self.view addSubview:self.imuReservedContainerView];

    self.topBar = [[UIView alloc] initWithFrame:CGRectMake(0, safeTop, screenWidth, 96)];
    [self.view addSubview:self.topBar];

    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backButton.frame = CGRectMake(16, 17, 30, 30);
    UIImage *backImg = [UIImage systemImageNamed:@"chevron.left"];
    [self.backButton setImage:backImg forState:UIControlStateNormal];
    self.backButton.tintColor = [UIColor whiteColor];
    [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.backButton];

    self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.settingsButton.frame = CGRectMake(screenWidth - 46, 17, 30, 30);
    UIImage *gearImg = [UIImage systemImageNamed:@"gearshape.fill"];
    [self.settingsButton setImage:gearImg forState:UIControlStateNormal];
    self.settingsButton.tintColor = [UIColor whiteColor];
    [self.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.settingsButton];

    UIView *centerContainer = [[UIView alloc] init];
    centerContainer.frame = CGRectMake(64, 12, screenWidth - 128, 40);
    [self.topBar addSubview:centerContainer];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:centerContainer.bounds];
    titleLabel.text = @"3DGS拍摄";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.tag = 300;
    [centerContainer addSubview:titleLabel];

    self.captureStepLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 56, screenWidth - 32, 24)];
    self.captureStepLabel.textColor = [UIColor whiteColor];
    self.captureStepLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    self.captureStepLabel.textAlignment = NSTextAlignmentLeft;
    self.captureStepLabel.adjustsFontSizeToFitWidth = YES;
    self.captureStepLabel.minimumScaleFactor = 0.78;
    [self.topBar addSubview:self.captureStepLabel];

    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 180, screenWidth, 180)];
    bottomBar.tag = 200;
    [self.view addSubview:bottomBar];

    [self setupGuidanceOverlayWithScreenWidth:screenWidth safeTop:safeTop];
    [self setupPitchIMUOverlay];
    [self setupStepGifOverlay];
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

    self.recordingDurationLabel = [[UILabel alloc] initWithFrame:CGRectMake((screenWidth - 120) / 2, 134, 120, 22)];
    self.recordingDurationLabel.text = @"00:00.0";
    self.recordingDurationLabel.textColor = [UIColor whiteColor];
    self.recordingDurationLabel.font = [UIFont monospacedDigitSystemFontOfSize:15 weight:UIFontWeightSemibold];
    self.recordingDurationLabel.textAlignment = NSTextAlignmentCenter;
    self.recordingDurationLabel.hidden = YES;
    [bottomBar addSubview:self.recordingDurationLabel];

    self.previousStepButton = [self stepButtonWithImageName:@"arrow.uturn.left"];
    [self.previousStepButton addTarget:self action:@selector(previousStepTapped) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:self.previousStepButton];

    self.previousStepLabel = [self stepLabelWithText:@"上一步"];
    [bottomBar addSubview:self.previousStepLabel];

    self.nextStepButton = [self stepButtonWithImageName:@"arrow.uturn.right"];
    [self.nextStepButton addTarget:self action:@selector(nextStepTapped) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:self.nextStepButton];

    self.nextStepLabel = [self stepLabelWithText:@"下一步"];
    [bottomBar addSubview:self.nextStepLabel];

    [self setupGuideVideoOverlay];

    [self updateRecordButton:NO];
    [self updateGuidanceUI];
}

- (void)setupPitchIMUOverlay {
    self.imuLeftWarningView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuLeftWarningView.userInteractionEnabled = NO;
    self.imuLeftWarningView.alpha = 0;
    self.imuLeftWarningView.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuLeftWarningView];

    self.imuRightWarningView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuRightWarningView.userInteractionEnabled = NO;
    self.imuRightWarningView.alpha = 0;
    self.imuRightWarningView.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuRightWarningView];

    UIColor *warningRed = [UIColor colorWithRed:0.98 green:0.10 blue:0.08 alpha:0.74];
    UIColor *clearRed = [UIColor colorWithRed:0.98 green:0.10 blue:0.08 alpha:0.0];

    self.imuLeftWarningGradientLayer = [CAGradientLayer layer];
    self.imuLeftWarningGradientLayer.startPoint = CGPointMake(0, 0.5);
    self.imuLeftWarningGradientLayer.endPoint = CGPointMake(1, 0.5);
    self.imuLeftWarningGradientLayer.colors = @[(__bridge id)warningRed.CGColor, (__bridge id)clearRed.CGColor];
    [self.imuLeftWarningView.layer addSublayer:self.imuLeftWarningGradientLayer];

    self.imuRightWarningGradientLayer = [CAGradientLayer layer];
    self.imuRightWarningGradientLayer.startPoint = CGPointMake(1, 0.5);
    self.imuRightWarningGradientLayer.endPoint = CGPointMake(0, 0.5);
    self.imuRightWarningGradientLayer.colors = @[(__bridge id)warningRed.CGColor, (__bridge id)clearRed.CGColor];
    [self.imuRightWarningView.layer addSublayer:self.imuRightWarningGradientLayer];

    self.imuTopLimitLineView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuTopLimitLineView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.88];
    self.imuTopLimitLineView.userInteractionEnabled = NO;
    [self.imuReservedContainerView addSubview:self.imuTopLimitLineView];

    self.imuBottomLimitLineView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuBottomLimitLineView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.88];
    self.imuBottomLimitLineView.userInteractionEnabled = NO;
    [self.imuReservedContainerView addSubview:self.imuBottomLimitLineView];

    self.imuCrossView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuCrossView.userInteractionEnabled = NO;
    [self.imuReservedContainerView addSubview:self.imuCrossView];

    self.imuCrossHorizontalLineView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuCrossHorizontalLineView.backgroundColor = [UIColor whiteColor];
    self.imuCrossHorizontalLineView.layer.cornerRadius = 1.5;
    [self.imuCrossView addSubview:self.imuCrossHorizontalLineView];

    self.imuCrossVerticalLineView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuCrossVerticalLineView.backgroundColor = [UIColor whiteColor];
    self.imuCrossVerticalLineView.layer.cornerRadius = 1.5;
    [self.imuCrossView addSubview:self.imuCrossVerticalLineView];

    self.imuPitchAngleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.imuPitchAngleLabel.text = @"俯仰 +0°";
    self.imuPitchAngleLabel.textColor = [UIColor whiteColor];
    self.imuPitchAngleLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightSemibold];
    self.imuPitchAngleLabel.textAlignment = NSTextAlignmentCenter;
    self.imuPitchAngleLabel.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuPitchAngleLabel];

    self.imuAngularSpeedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.imuAngularSpeedLabel.text = @"角速度 0°/s";
    self.imuAngularSpeedLabel.textColor = [UIColor whiteColor];
    self.imuAngularSpeedLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightSemibold];
    self.imuAngularSpeedLabel.textAlignment = NSTextAlignmentCenter;
    self.imuAngularSpeedLabel.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuAngularSpeedLabel];

    self.imuMovementSpeedLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.imuMovementSpeedLabel.text = @"移动 0.0m/s";
    self.imuMovementSpeedLabel.textColor = [UIColor whiteColor];
    self.imuMovementSpeedLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightSemibold];
    self.imuMovementSpeedLabel.textAlignment = NSTextAlignmentLeft;
    self.imuMovementSpeedLabel.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuMovementSpeedLabel];

    self.imuWarningLabelContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuWarningLabelContainerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.44];
    self.imuWarningLabelContainerView.layer.cornerRadius = 14;
    self.imuWarningLabelContainerView.clipsToBounds = YES;
    self.imuWarningLabelContainerView.hidden = YES;
    self.imuWarningLabelContainerView.alpha = 0;
    [self.imuReservedContainerView addSubview:self.imuWarningLabelContainerView];

    self.imuWarningLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.imuWarningLabel.text = @"请保持手机水平";
    self.imuWarningLabel.textColor = [UIColor whiteColor];
    self.imuWarningLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.imuWarningLabel.textAlignment = NSTextAlignmentCenter;
    [self.imuWarningLabelContainerView addSubview:self.imuWarningLabel];

    self.imuTopWarningView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuTopWarningView.userInteractionEnabled = NO;
    self.imuTopWarningView.alpha = 0;
    self.imuTopWarningView.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuTopWarningView];

    self.imuBottomWarningView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuBottomWarningView.userInteractionEnabled = NO;
    self.imuBottomWarningView.alpha = 0;
    self.imuBottomWarningView.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuBottomWarningView];

    UIColor *rollWarningRed = [UIColor colorWithRed:0.98 green:0.10 blue:0.08 alpha:0.74];
    UIColor *rollClearRed = [UIColor colorWithRed:0.98 green:0.10 blue:0.08 alpha:0.0];

    self.imuTopWarningGradientLayer = [CAGradientLayer layer];
    self.imuTopWarningGradientLayer.startPoint = CGPointMake(0.5, 0);
    self.imuTopWarningGradientLayer.endPoint = CGPointMake(0.5, 1);
    self.imuTopWarningGradientLayer.colors = @[(__bridge id)rollWarningRed.CGColor, (__bridge id)rollClearRed.CGColor];
    [self.imuTopWarningView.layer addSublayer:self.imuTopWarningGradientLayer];

    self.imuBottomWarningGradientLayer = [CAGradientLayer layer];
    self.imuBottomWarningGradientLayer.startPoint = CGPointMake(0.5, 1);
    self.imuBottomWarningGradientLayer.endPoint = CGPointMake(0.5, 0);
    self.imuBottomWarningGradientLayer.colors = @[(__bridge id)rollWarningRed.CGColor, (__bridge id)rollClearRed.CGColor];
    [self.imuBottomWarningView.layer addSublayer:self.imuBottomWarningGradientLayer];

    self.imuRollLeftLimitLineView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuRollLeftLimitLineView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.88];
    self.imuRollLeftLimitLineView.userInteractionEnabled = NO;
    [self.imuReservedContainerView addSubview:self.imuRollLeftLimitLineView];

    self.imuRollRightLimitLineView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuRollRightLimitLineView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.88];
    self.imuRollRightLimitLineView.userInteractionEnabled = NO;
    [self.imuReservedContainerView addSubview:self.imuRollRightLimitLineView];

    self.imuRollAngleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.imuRollAngleLabel.text = @"侧倾角 +0°";
    self.imuRollAngleLabel.textColor = [UIColor whiteColor];
    self.imuRollAngleLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightSemibold];
    self.imuRollAngleLabel.textAlignment = NSTextAlignmentCenter;
    self.imuRollAngleLabel.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuRollAngleLabel];

    self.imuRollWarningLabelContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuRollWarningLabelContainerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.44];
    self.imuRollWarningLabelContainerView.layer.cornerRadius = 14;
    self.imuRollWarningLabelContainerView.clipsToBounds = YES;
    self.imuRollWarningLabelContainerView.hidden = YES;
    self.imuRollWarningLabelContainerView.alpha = 0;
    [self.imuReservedContainerView addSubview:self.imuRollWarningLabelContainerView];

    self.imuRollWarningLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.imuRollWarningLabel.text = @"请保持手机垂直";
    self.imuRollWarningLabel.textColor = [UIColor whiteColor];
    self.imuRollWarningLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    self.imuRollWarningLabel.textAlignment = NSTextAlignmentCenter;
    [self.imuRollWarningLabelContainerView addSubview:self.imuRollWarningLabel];

}

- (void)setupGuidanceOverlayWithScreenWidth:(CGFloat)screenWidth safeTop:(CGFloat)safeTop {
    CGFloat toastWidth = MIN(screenWidth - 48, 340);
    self.toastContainerView = [[UIView alloc] initWithFrame:CGRectMake((screenWidth - toastWidth) / 2, self.view.bounds.size.height - 272, toastWidth, 78)];
    self.toastContainerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.50];
    self.toastContainerView.layer.cornerRadius = 3;
    self.toastContainerView.clipsToBounds = YES;
    [self.imuReservedContainerView addSubview:self.toastContainerView];

    self.toastLabel = [[UILabel alloc] initWithFrame:CGRectInset(self.toastContainerView.bounds, 16, 12)];
    self.toastLabel.textColor = [UIColor whiteColor];
    self.toastLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    self.toastLabel.numberOfLines = 0;
    self.toastLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [self.toastContainerView addSubview:self.toastLabel];

    self.imuStatusToastContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.imuStatusToastContainerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.50];
    self.imuStatusToastContainerView.layer.cornerRadius = 16;
    self.imuStatusToastContainerView.clipsToBounds = YES;
    self.imuStatusToastContainerView.hidden = YES;
    [self.imuReservedContainerView addSubview:self.imuStatusToastContainerView];

    self.imuStatusToastLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.imuStatusToastLabel.textColor = [UIColor whiteColor];
    self.imuStatusToastLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.imuStatusToastLabel.numberOfLines = 0;
    self.imuStatusToastLabel.lineBreakMode = NSLineBreakByWordWrapping;
    self.imuStatusToastLabel.textAlignment = NSTextAlignmentCenter;
    [self.imuStatusToastContainerView addSubview:self.imuStatusToastLabel];
}

- (void)setupGuideVideoOverlay {
    self.guideVideoOverlayView = [[UIView alloc] initWithFrame:self.view.bounds];
    self.guideVideoOverlayView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.68];
    self.guideVideoOverlayView.hidden = YES;
    self.guideVideoOverlayView.alpha = 0;
    [self.view addSubview:self.guideVideoOverlayView];

    self.guideVideoFrameView = [[UIView alloc] initWithFrame:CGRectZero];
    self.guideVideoFrameView.backgroundColor = [UIColor whiteColor];
    self.guideVideoFrameView.layer.cornerRadius = 4;
    self.guideVideoFrameView.clipsToBounds = YES;
    [self.guideVideoOverlayView addSubview:self.guideVideoFrameView];

    self.guideVideoTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.guideVideoTitleLabel.textColor = [UIColor whiteColor];
    self.guideVideoTitleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    self.guideVideoTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.guideVideoTitleLabel.numberOfLines = 2;
    [self.guideVideoOverlayView addSubview:self.guideVideoTitleLabel];

    self.guideVideoSkipButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.guideVideoSkipButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.48];
    self.guideVideoSkipButton.tintColor = [UIColor whiteColor];
    self.guideVideoSkipButton.layer.cornerRadius = 16;
    self.guideVideoSkipButton.clipsToBounds = YES;
    self.guideVideoSkipButton.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    [self.guideVideoSkipButton setTitle:@"跳过" forState:UIControlStateNormal];
    self.guideVideoSkipButton.hidden = YES;
    [self.guideVideoSkipButton addTarget:self action:@selector(skipGuideVideoTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.guideVideoOverlayView addSubview:self.guideVideoSkipButton];

    self.countdownLabel = [[UILabel alloc] initWithFrame:self.guideVideoOverlayView.bounds];
    self.countdownLabel.textColor = [UIColor whiteColor];
    self.countdownLabel.font = [UIFont monospacedDigitSystemFontOfSize:96 weight:UIFontWeightBold];
    self.countdownLabel.textAlignment = NSTextAlignmentCenter;
    self.countdownLabel.hidden = YES;
    [self.guideVideoOverlayView addSubview:self.countdownLabel];
}

- (UIButton *)stepButtonWithImageName:(NSString *)imageName {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
    button.layer.borderWidth = 2;
    button.layer.borderColor = [UIColor whiteColor].CGColor;
    button.layer.cornerRadius = 27;
    button.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
    button.tintColor = [UIColor whiteColor];
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:24 weight:UIImageSymbolWeightRegular];
    UIImage *image = [UIImage systemImageNamed:imageName withConfiguration:config];
    [button setImage:image forState:UIControlStateNormal];
    return button;
}

- (UILabel *)stepLabelWithText:(NSString *)text {
    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textColor = [UIColor whiteColor];
    label.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    label.textAlignment = NSTextAlignmentCenter;
    return label;
}

- (UIImage *)guidanceExampleImageWithSize:(CGSize)size {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
        CGContextRef context = rendererContext.CGContext;
        [[UIColor colorWithRed:0xEC/255.0 green:0xE1/255.0 blue:0xCC/255.0 alpha:1.0] setFill];
        CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));

        [[UIColor colorWithRed:0xC3/255.0 green:0xAE/255.0 blue:0x8B/255.0 alpha:1.0] setFill];
        CGContextFillRect(context, CGRectMake(0, size.height * 0.66, size.width, size.height * 0.34));

        [[UIColor colorWithRed:0xF8/255.0 green:0xF2/255.0 blue:0xE6/255.0 alpha:1.0] setFill];
        CGContextFillRect(context, CGRectMake(size.width * 0.10, size.height * 0.14, size.width * 0.32, size.height * 0.44));
        CGContextFillRect(context, CGRectMake(size.width * 0.47, size.height * 0.16, size.width * 0.42, size.height * 0.42));

        [[UIColor colorWithWhite:1 alpha:0.72] setFill];
        CGContextFillRect(context, CGRectMake(size.width * 0.13, size.height * 0.18, size.width * 0.26, size.height * 0.36));
        CGContextFillRect(context, CGRectMake(size.width * 0.50, size.height * 0.20, size.width * 0.36, size.height * 0.34));

        [[UIColor colorWithRed:0x8D/255.0 green:0x74/255.0 blue:0x56/255.0 alpha:1.0] setFill];
        CGContextFillRect(context, CGRectMake(size.width * 0.18, size.height * 0.57, size.width * 0.64, size.height * 0.16));
        CGContextFillRect(context, CGRectMake(size.width * 0.22, size.height * 0.73, size.width * 0.08, size.height * 0.16));
        CGContextFillRect(context, CGRectMake(size.width * 0.70, size.height * 0.73, size.width * 0.08, size.height * 0.16));

        [[UIColor colorWithRed:0x6F/255.0 green:0x62/255.0 blue:0x4F/255.0 alpha:1.0] setStroke];
        CGContextSetLineWidth(context, 2);
        CGContextStrokeRect(context, CGRectInset(CGRectMake(size.width * 0.18, size.height * 0.57, size.width * 0.64, size.height * 0.16), 1, 1));
    }];
}

- (void)setupStepGifOverlay {
    self.stepGifContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    self.stepGifContainerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.18];
    self.stepGifContainerView.layer.cornerRadius = 12.0;
    self.stepGifContainerView.layer.borderWidth = 1.0;
    self.stepGifContainerView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.18].CGColor;
    self.stepGifContainerView.clipsToBounds = YES;
    self.stepGifContainerView.hidden = YES;
    self.stepGifContainerView.userInteractionEnabled = NO;
    [self.imuReservedContainerView addSubview:self.stepGifContainerView];

    self.stepGifImageView = [[UIImageView alloc] initWithFrame:self.stepGifContainerView.bounds];
    self.stepGifImageView.backgroundColor = [UIColor clearColor];
    self.stepGifImageView.contentMode = UIViewContentModeScaleAspectFit;
    self.stepGifImageView.clipsToBounds = YES;
    [self.stepGifContainerView addSubview:self.stepGifImageView];

    [self refreshStepGifOverlay];
}

- (void)refreshStepGifOverlay {
    BOOL shouldShow = [[CD3DGSCameraService shared] isRecording] && !self.isPreparingToRecord && !self.isFinishingCurrentRecording;
    self.stepGifContainerView.hidden = !shouldShow;
    if (!shouldShow) {
        return;
    }

    NSInteger stepIndex = self.guidanceState.currentStepIndex;
    if (self.stepGifDisplayedIndex == stepIndex && self.stepGifImageView.image) {
        return;
    }

    NSString *resourceName = [self stepGifResourceNameForIndex:stepIndex];
    UIImage *gifImage = [self animatedGIFImageNamed:resourceName];
    self.stepGifImageView.image = gifImage;
    self.stepGifDisplayedIndex = stepIndex;
}

- (NSString *)stepGifResourceNameForIndex:(NSInteger)stepIndex {
    return [NSString stringWithFormat:@"step%03ld", (long)stepIndex + 1];
}

- (UIImage *)animatedGIFImageNamed:(NSString *)name {
    if (!name.length) {
        return nil;
    }

    UIImage *cachedImage = [self.stepGifCache objectForKey:name];
    if (cachedImage) {
        return cachedImage;
    }

    NSString *path = [[NSBundle mainBundle] pathForResource:name ofType:@"gif"];
    if (!path) {
        path = [[NSBundle mainBundle] pathForResource:name ofType:@"GIF"];
    }
    if (!path) {
        return nil;
    }

    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data.length) {
        return nil;
    }

    UIImage *image = [self animatedGIFImageFromData:data scale:[UIScreen mainScreen].scale];
    if (image) {
        [self.stepGifCache setObject:image forKey:name];
    }
    return image;
}

- (UIImage *)animatedGIFImageFromData:(NSData *)data scale:(CGFloat)scale {
    if (!data.length) {
        return nil;
    }

    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) {
        return nil;
    }

    size_t frameCount = CGImageSourceGetCount(source);
    if (frameCount == 0) {
        CFRelease(source);
        return nil;
    }

    NSMutableArray<UIImage *> *images = [NSMutableArray arrayWithCapacity:frameCount];
    NSTimeInterval duration = 0.0;
    for (size_t i = 0; i < frameCount; i++) {
        CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, i, NULL);
        if (!cgImage) {
            continue;
        }
        NSDictionary *frameProperties = (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, i, NULL);
        NSTimeInterval frameDuration = [self gifFrameDurationFromProperties:frameProperties];
        duration += frameDuration;
        UIImage *frameImage = [UIImage imageWithCGImage:cgImage scale:scale orientation:UIImageOrientationUp];
        if (frameImage) {
            [images addObject:frameImage];
        }
        CGImageRelease(cgImage);
    }

    CFRelease(source);
    if (images.count == 0) {
        return nil;
    }

    if (duration <= 0.0) {
        duration = (NSTimeInterval)images.count / 12.0;
    }
    return [UIImage animatedImageWithImages:images duration:duration];
}

- (NSTimeInterval)gifFrameDurationFromProperties:(NSDictionary *)properties {
    NSDictionary *gifProperties = properties[(NSString *)kCGImagePropertyGIFDictionary];
    NSNumber *unclampedDelay = gifProperties[(NSString *)kCGImagePropertyGIFUnclampedDelayTime];
    NSNumber *delay = gifProperties[(NSString *)kCGImagePropertyGIFDelayTime];
    NSTimeInterval frameDuration = unclampedDelay.doubleValue > 0.0 ? unclampedDelay.doubleValue : delay.doubleValue;
    if (frameDuration < 0.02) {
        frameDuration = 0.08;
    }
    return frameDuration;
}

- (void)previousStepTapped {
    if ([[CD3DGSCameraService shared] isRecording] || self.isFinishingCurrentRecording) {
        return;
    }
    [self.guidanceState moveToPreviousStep];
    [self updateGuidanceUI];
}

- (void)nextStepTapped {
    if ([[CD3DGSCameraService shared] isRecording] || self.isFinishingCurrentRecording) {
        return;
    }
    [self.guidanceState moveToNextStep];
    [self updateGuidanceUI];
}

- (void)updateGuidanceUI {
    BOOL isBusy = [[CD3DGSCameraService shared] isRecording] || self.isFinishingCurrentRecording || self.isPreparingToRecord;
    self.captureStepLabel.text = self.guidanceState.currentInstruction;
    BOOL isRecording = [[CD3DGSCameraService shared] isRecording];
    NSString *warningText = isRecording ? [self currentWarningToastText] : nil;
    BOOL shouldShowLongToast = !isRecording && !self.isPreparingToRecord;
    self.toastContainerView.hidden = !shouldShowLongToast;
    self.toastLabel.text = self.guidanceState.currentToastText;
    self.imuStatusToastContainerView.hidden = !(isRecording && warningText.length > 0);
    self.imuStatusToastLabel.text = warningText;
    [self refreshStepGifOverlay];
    [self.view setNeedsLayout];
    [self updateStepButton:self.previousStepButton label:self.previousStepLabel enabled:self.guidanceState.canMoveToPreviousStep && !isBusy];
    [self updateStepButton:self.nextStepButton label:self.nextStepLabel enabled:self.guidanceState.canMoveToNextStep && !isBusy];
    self.recordButton.enabled = !self.guidanceState.isComplete && !self.isFinishingCurrentRecording && !self.isPreparingToRecord;
    self.recordButton.alpha = self.recordButton.enabled ? 1.0 : 0.45;
}

- (void)updateStepButton:(UIButton *)button label:(UILabel *)label enabled:(BOOL)enabled {
    button.enabled = enabled;
    CGFloat alpha = enabled ? 1.0 : 0.45;
    button.alpha = alpha;
    label.alpha = alpha;
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
    });
}

- (void)showSettings {
    CDCameraSettingsViewController *settingsVC = [[CDCameraSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
    [self presentViewController:nav animated:YES completion:nil];
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
    [self updateRecordButton:isRecording];
    if (isRecording) {
        self.recordingDurationLabel.hidden = NO;
        self.recordingDurationLabel.text = [self formatDuration:[CD3DGSCameraService shared].recordingDuration];
        [self startPitchMonitoringIfNeeded];
    } else {
        self.recordingDurationLabel.hidden = YES;
        [self stopPitchMonitoring];
    }
    [self updateGuidanceUI];
}

- (void)startPitchMonitoringIfNeeded {
    if (self.motionManager.isDeviceMotionActive) {
        return;
    }
    if (!self.motionManager) {
        self.motionManager = [[CMMotionManager alloc] init];
    }
    if (!self.motionQueue) {
        self.motionQueue = [[NSOperationQueue alloc] init];
        self.motionQueue.maxConcurrentOperationCount = 1;
    }
    if (!self.motionManager.isDeviceMotionAvailable) {
        return;
    }

    self.imuTopLimitLineView.hidden = NO;
    self.imuBottomLimitLineView.hidden = NO;
    self.imuCrossView.hidden = NO;
    self.imuPitchAngleLabel.hidden = NO;
    self.imuRollAngleLabel.hidden = NO;
    self.imuWarningLabelContainerView.hidden = YES;
    self.imuLeftWarningView.hidden = YES;
    self.imuRightWarningView.hidden = YES;
    self.imuRollWarningLabelContainerView.hidden = YES;
    self.imuTopWarningView.hidden = YES;
    self.imuBottomWarningView.hidden = YES;
    self.imuLeftWarningView.alpha = 0;
    self.imuRightWarningView.alpha = 0;
    self.imuTopWarningView.alpha = 0;
    self.imuBottomWarningView.alpha = 0;
    self.imuTopLimitLineView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.88];
    self.imuBottomLimitLineView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.88];
    self.imuCrossHorizontalLineView.backgroundColor = [UIColor whiteColor];
    self.imuCrossVerticalLineView.backgroundColor = [UIColor whiteColor];
    self.imuPitchAngleLabel.textColor = [UIColor whiteColor];
    self.imuAngularSpeedLabel.hidden = NO;
    self.imuAngularSpeedLabel.text = @"角速度 0°/s";
    self.imuAngularSpeedLabel.textColor = [UIColor whiteColor];
    self.imuMovementSpeedLabel.hidden = NO;
    self.imuMovementSpeedLabel.text = @"移动 0.0m/s";
    self.imuMovementSpeedLabel.textColor = [UIColor whiteColor];
    self.imuStatusToastContainerView.hidden = YES;
    self.currentMovementSpeedMetersPerSecond = 0;
    self.movementVelocityX = 0;
    self.movementVelocityY = 0;
    self.movementVelocityZ = 0;
    self.movementWarningActive = NO;
    [self.warningImpactFeedbackGenerator prepare];

    self.motionManager.deviceMotionUpdateInterval = 1.0 / 30.0;
    __weak typeof(self) weakSelf = self;
    [self.motionManager startDeviceMotionUpdatesToQueue:self.motionQueue withHandler:^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !motion) return;
        double pitchDegrees = [self screenPitchDegreesForMotion:motion];
        double rollDegrees = [self screenRollDegreesForMotion:motion];
        CGFloat angularSpeed = [self angularSpeedDegreesPerSecondForMotion:motion];
        CGFloat movementSpeed = [self movementSpeedMetersPerSecondForMotion:motion];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self updateAngularSpeedDegreesPerSecond:angularSpeed];
            [self updateMovementSpeedMetersPerSecond:movementSpeed];
            [self updatePitchIMUUIWithPitchDegrees:pitchDegrees];
            [self updateRollIMUUIWithRollDegrees:rollDegrees];
        });
    }];
}

- (double)screenPitchDegreesForMotion:(CMDeviceMotion *)motion {
    CMAcceleration gravity = motion.gravity;
    return [CD3DGSPitchCalibration pitchDegreesWithGravityX:gravity.x
                                                   gravityY:gravity.y
                                                   gravityZ:gravity.z
                                        interfaceOrientation:[self currentInterfaceOrientation]];
}

- (void)stopPitchMonitoring {
    [self.motionManager stopDeviceMotionUpdates];
    self.currentPitchDegrees = 0;
    self.currentPitchOffsetY = 0;
    self.pitchWarningActive = NO;
    self.currentAngularSpeedDegreesPerSecond = 0;
    self.angularSpeedWarningActive = NO;
    self.currentRollDegrees = 0;
    self.rollWarningActive = NO;
    self.currentMovementSpeedMetersPerSecond = 0;
    self.movementVelocityX = 0;
    self.movementVelocityY = 0;
    self.movementVelocityZ = 0;
    self.movementWarningActive = NO;
    self.imuTopLimitLineView.hidden = YES;
    self.imuBottomLimitLineView.hidden = YES;
    self.imuCrossView.hidden = YES;
    self.imuLeftWarningView.hidden = YES;
    self.imuRightWarningView.hidden = YES;
    self.imuRollLeftLimitLineView.hidden = YES;
    self.imuRollRightLimitLineView.hidden = YES;
    self.imuTopWarningView.hidden = YES;
    self.imuBottomWarningView.hidden = YES;
    self.imuLeftWarningView.alpha = 0;
    self.imuRightWarningView.alpha = 0;
    self.imuTopWarningView.alpha = 0;
    self.imuBottomWarningView.alpha = 0;
    self.imuWarningLabelContainerView.hidden = YES;
    self.imuWarningLabelContainerView.alpha = 0;
    self.imuRollWarningLabelContainerView.hidden = YES;
    self.imuRollWarningLabelContainerView.alpha = 0;
    self.imuStatusToastContainerView.hidden = YES;
    self.imuStatusToastLabel.text = nil;
    self.imuPitchAngleLabel.hidden = YES;
    self.imuAngularSpeedLabel.hidden = YES;
    self.imuMovementSpeedLabel.hidden = YES;
    self.imuRollAngleLabel.hidden = YES;
    self.imuTopLimitLineView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.88];
    self.imuBottomLimitLineView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.88];
    self.imuCrossView.transform = CGAffineTransformIdentity;
    self.imuAngularSpeedLabel.hidden = YES;
    self.imuAngularSpeedLabel.text = @"角速度 0°/s";
    self.stepGifContainerView.hidden = YES;
    self.stepGifImageView.image = nil;
}

- (CGFloat)movementSpeedMetersPerSecondForMotion:(CMDeviceMotion *)motion {
    CGFloat dt = self.motionManager.deviceMotionUpdateInterval > 0 ? self.motionManager.deviceMotionUpdateInterval : (1.0 / 30.0);
    CGFloat ax = motion.userAcceleration.x * 9.81;
    CGFloat ay = motion.userAcceleration.y * 9.81;
    CGFloat az = motion.userAcceleration.z * 9.81;
    CGFloat accelerationMagnitude = sqrt(ax * ax + ay * ay + az * az);
    CGFloat damping = accelerationMagnitude < 0.15 ? 0.82 : 0.90;

    self.movementVelocityX = (self.movementVelocityX + ax * dt) * damping;
    self.movementVelocityY = (self.movementVelocityY + ay * dt) * damping;
    self.movementVelocityZ = (self.movementVelocityZ + az * dt) * damping;

    CGFloat speed = sqrt(self.movementVelocityX * self.movementVelocityX +
                         self.movementVelocityY * self.movementVelocityY +
                         self.movementVelocityZ * self.movementVelocityZ);
    return MIN(MAX(speed, 0.0), 2.5);
}

- (CGFloat)angularSpeedDegreesPerSecondForMotion:(CMDeviceMotion *)motion {
    CMRotationRate rate = motion.rotationRate;
    CGFloat angularSpeedRadians = sqrt(rate.x * rate.x + rate.y * rate.y + rate.z * rate.z);
    return angularSpeedRadians * 180.0 / M_PI;
}

- (void)updateAngularSpeedDegreesPerSecond:(CGFloat)speed {
    if (![[CD3DGSCameraService shared] isRecording]) {
        return;
    }

    CGFloat smoothedSpeed = self.currentAngularSpeedDegreesPerSecond * 0.80 + speed * 0.20;
    self.currentAngularSpeedDegreesPerSecond = MIN(MAX(smoothedSpeed, 0.0), 360.0);
    BOOL warningActive = self.currentAngularSpeedDegreesPerSecond >= 45.0;
    BOOL shouldTriggerHaptic = (!self.angularSpeedWarningActive && warningActive);
    self.angularSpeedWarningActive = warningActive;
    self.imuAngularSpeedLabel.hidden = NO;
    self.imuAngularSpeedLabel.text = [NSString stringWithFormat:@"角速度 %.0f°/s", self.currentAngularSpeedDegreesPerSecond];
    self.imuAngularSpeedLabel.textColor = [UIColor whiteColor];
    if (shouldTriggerHaptic) {
        [self.warningImpactFeedbackGenerator impactOccurred];
        [self.warningImpactFeedbackGenerator prepare];
    }
    [self refreshIMUWarningChrome];
    [self updateGuidanceUI];
    [self.view setNeedsLayout];
}

- (void)updateMovementSpeedMetersPerSecond:(CGFloat)speed {
    if (![[CD3DGSCameraService shared] isRecording]) {
        return;
    }

    self.currentMovementSpeedMetersPerSecond = MIN(MAX(speed, 0.0), 2.5);
    BOOL warningActive = self.currentMovementSpeedMetersPerSecond >= 0.5;
    BOOL shouldTriggerHaptic = (!self.movementWarningActive && warningActive);
    self.movementWarningActive = warningActive;
    self.imuMovementSpeedLabel.hidden = NO;
    self.imuMovementSpeedLabel.text = warningActive ? [NSString stringWithFormat:@"移动过快 %.1fm/s", self.currentMovementSpeedMetersPerSecond]
                                                    : [NSString stringWithFormat:@"移动 %.1fm/s", self.currentMovementSpeedMetersPerSecond];
    self.imuMovementSpeedLabel.textColor = warningActive ? [UIColor colorWithRed:0.96 green:0.17 blue:0.12 alpha:1.0] : [UIColor whiteColor];
    if (shouldTriggerHaptic) {
        [self.warningImpactFeedbackGenerator impactOccurred];
        [self.warningImpactFeedbackGenerator prepare];
    }
    [self.view setNeedsLayout];
}

- (void)updatePitchIMUUIWithPitchDegrees:(double)pitchDegrees {
    if (![[CD3DGSCameraService shared] isRecording]) {
        [self stopPitchMonitoring];
        return;
    }
    self.currentPitchDegrees = (CGFloat)pitchDegrees;

    CGFloat threshold = 8.0;
    CGFloat maxOffset = 52.0;
    self.currentPitchOffsetY = [CD3DGSPitchCalibration offsetYForRelativePitchDegrees:self.currentPitchDegrees
                                                                           threshold:threshold
                                                                           maxOffset:maxOffset];
    self.imuPitchAngleLabel.text = [NSString stringWithFormat:@"俯仰 %+.0f°", self.currentPitchDegrees];

    BOOL warningActive = [CD3DGSPitchCalibration isWarningActiveForRelativePitchDegrees:self.currentPitchDegrees
                                                                               threshold:threshold];
    [self applyPitchWarningActive:warningActive animated:YES];
    [self refreshIMUWarningChrome];
    [self updateGuidanceUI];
    [self.view setNeedsLayout];
}

- (double)screenRollDegreesForMotion:(CMDeviceMotion *)motion {
    CMAcceleration gravity = motion.gravity;
    return [CD3DGSPitchCalibration rollDegreesWithGravityX:gravity.x
                                                  gravityY:gravity.y
                                                  gravityZ:gravity.z
                                       interfaceOrientation:[self currentInterfaceOrientation]];
}

- (void)updateRollIMUUIWithRollDegrees:(double)rollDegrees {
    if (![[CD3DGSCameraService shared] isRecording]) {
        [self stopPitchMonitoring];
        return;
    }

    self.currentRollDegrees = (CGFloat)rollDegrees;

    CGFloat threshold = 20.0;
    self.imuRollAngleLabel.text = [NSString stringWithFormat:@"侧倾角 %+.0f°", self.currentRollDegrees];
    self.imuCrossView.transform = CGAffineTransformMakeRotation((CGFloat)(self.currentRollDegrees * M_PI / 180.0));

    BOOL warningActive = [CD3DGSPitchCalibration isWarningActiveForRelativeRollDegrees:self.currentRollDegrees
                                                                              threshold:threshold];
    [self applyRollWarningActive:warningActive animated:YES];
    [self refreshIMUWarningChrome];
    [self updateGuidanceUI];
    [self.view setNeedsLayout];
}

- (UIInterfaceOrientation)currentInterfaceOrientation {
    for (UIScene *scene in UIApplication.sharedApplication.connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        if (windowScene.activationState == UISceneActivationStateForegroundActive ||
            windowScene.activationState == UISceneActivationStateForegroundInactive) {
            return windowScene.interfaceOrientation;
        }
    }
    return UIInterfaceOrientationPortrait;
}

- (void)applyPitchWarningActive:(BOOL)warningActive animated:(BOOL)animated {
    BOOL shouldTriggerHaptic = (!self.pitchWarningActive && warningActive);
    if (self.pitchWarningActive == warningActive && self.imuLeftWarningView.hidden == !warningActive) {
        return;
    }
    self.pitchWarningActive = warningActive;

    void (^showBlock)(void) = ^{
        self.imuLeftWarningView.hidden = !warningActive;
        self.imuRightWarningView.hidden = !warningActive;
        UIColor *lineColor = warningActive ? [UIColor colorWithRed:0.96 green:0.17 blue:0.12 alpha:1.0]
                                           : [[UIColor whiteColor] colorWithAlphaComponent:0.88];
        self.imuTopLimitLineView.backgroundColor = lineColor;
        self.imuBottomLimitLineView.backgroundColor = lineColor;
        self.imuPitchAngleLabel.textColor = warningActive ? lineColor : [UIColor whiteColor];
    };

    if (animated) {
        [UIView animateWithDuration:0.18 animations:showBlock];
    } else {
        showBlock();
    }

    if (shouldTriggerHaptic) {
        [self.warningImpactFeedbackGenerator impactOccurred];
        [self.warningImpactFeedbackGenerator prepare];
    }
}

- (void)applyRollWarningActive:(BOOL)warningActive animated:(BOOL)animated {
    BOOL shouldTriggerHaptic = (!self.rollWarningActive && warningActive);
    if (self.rollWarningActive == warningActive && self.imuTopWarningView.hidden == !warningActive) {
        return;
    }
    self.rollWarningActive = warningActive;

    void (^showBlock)(void) = ^{
        self.imuTopWarningView.hidden = !warningActive;
        self.imuBottomWarningView.hidden = !warningActive;
        UIColor *lineColor = warningActive ? [UIColor colorWithRed:0.96 green:0.17 blue:0.12 alpha:1.0]
                                           : [[UIColor whiteColor] colorWithAlphaComponent:0.88];
        self.imuRollLeftLimitLineView.backgroundColor = lineColor;
        self.imuRollRightLimitLineView.backgroundColor = lineColor;
        self.imuCrossHorizontalLineView.backgroundColor = warningActive ? lineColor : [UIColor whiteColor];
        self.imuCrossVerticalLineView.backgroundColor = warningActive ? lineColor : [UIColor whiteColor];
        self.imuRollAngleLabel.textColor = warningActive ? lineColor : [UIColor whiteColor];
    };

    if (animated) {
        [UIView animateWithDuration:0.18 animations:showBlock];
    } else {
        showBlock();
    }

    if (shouldTriggerHaptic) {
        [self.warningImpactFeedbackGenerator impactOccurred];
        [self.warningImpactFeedbackGenerator prepare];
    }
}

- (void)refreshIMUWarningChrome {
    BOOL anyWarningActive = self.pitchWarningActive || self.rollWarningActive || self.angularSpeedWarningActive;
    CGFloat alpha = anyWarningActive ? 0.82 : 0.0;
    self.imuLeftWarningView.hidden = !anyWarningActive;
    self.imuRightWarningView.hidden = !anyWarningActive;
    self.imuTopWarningView.hidden = !anyWarningActive;
    self.imuBottomWarningView.hidden = !anyWarningActive;
    self.imuLeftWarningView.alpha = alpha;
    self.imuRightWarningView.alpha = alpha;
    self.imuTopWarningView.alpha = alpha;
    self.imuBottomWarningView.alpha = alpha;
}

- (NSString *)currentWarningToastText {
    if (self.pitchWarningActive || self.rollWarningActive || self.angularSpeedWarningActive) {
        return [CD3DGSPitchCalibration warningToastTextWithPitchWarningActive:self.pitchWarningActive
                                                              rollWarningActive:self.rollWarningActive
                                                       angularSpeedWarningActive:self.angularSpeedWarningActive];
    }
    return nil;
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
    UILabel *titleLabel = [self.topBar viewWithTag:300];
    titleLabel.text = @"3DGS拍摄";
}

- (void)toggleRecording {
    if (self.guidanceState.isComplete || self.isFinishingCurrentRecording) {
        return;
    }

    CD3DGSCameraService *cameraService = [CD3DGSCameraService shared];
    if (cameraService.isRecording) {
        self.isFinishingCurrentRecording = YES;
        self.recordButton.enabled = NO;
        [self stopPitchMonitoring];
        [cameraService stopRecording];
        [self updateGuidanceUI];
    } else if (self.isPreparingToRecord) {
        return;
    } else {
        [self beginGuideVideoBeforeRecording];
    }
}

- (void)beginGuideVideoBeforeRecording {
    self.isPreparingToRecord = YES;
    self.recordingDurationLabel.hidden = YES;
    [self updateGuidanceUI];

    NSURL *guideVideoURL = [self currentGuideVideoURL];
    if (!guideVideoURL) {
        [self startCountdownBeforeRecording];
        return;
    }

    self.guideVideoTitleLabel.text = [NSString stringWithFormat:@"%@\n示意视频", self.guidanceState.currentInstruction];
    self.guideVideoFrameView.hidden = NO;
    self.guideVideoSkipButton.hidden = NO;
    self.countdownLabel.hidden = YES;
    self.guideVideoOverlayView.hidden = NO;
    self.guideVideoOverlayView.alpha = 1;

    AVPlayerItem *item = [AVPlayerItem playerItemWithURL:guideVideoURL];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(guideVideoDidFinish:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:item];
    self.guideVideoPlayer = [AVPlayer playerWithPlayerItem:item];
    self.guideVideoPlayer.actionAtItemEnd = AVPlayerActionAtItemEndPause;

    [self.guideVideoPlayerLayer removeFromSuperlayer];
    self.guideVideoPlayerLayer = [AVPlayerLayer playerLayerWithPlayer:self.guideVideoPlayer];
    self.guideVideoPlayerLayer.videoGravity = AVLayerVideoGravityResizeAspect;
    self.guideVideoPlayerLayer.frame = CGRectInset(self.guideVideoFrameView.bounds, 4, 4);
    [self.guideVideoFrameView.layer insertSublayer:self.guideVideoPlayerLayer atIndex:0];

    [self.guideVideoPlayer play];
}

- (void)skipGuideVideoTapped {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:self.guideVideoPlayer.currentItem];
    [self.guideVideoPlayer pause];
    [self startCountdownBeforeRecording];
}

- (NSURL *)currentGuideVideoURL {
    NSString *resourceName = self.guidanceState.guideVideoResourceName;
    NSURL *url = [[NSBundle mainBundle] URLForResource:resourceName withExtension:@"mp4"];
    if (!url) {
        url = [[NSBundle mainBundle] URLForResource:resourceName withExtension:@"MP4"];
    }
    return url;
}

- (void)guideVideoDidFinish:(NSNotification *)notification {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:notification.object];
    [self startCountdownBeforeRecording];
}

- (void)startCountdownBeforeRecording {
    self.guideVideoOverlayView.hidden = NO;
    self.guideVideoOverlayView.alpha = 1;
    self.guideVideoFrameView.hidden = YES;
    self.guideVideoSkipButton.hidden = YES;
    self.guideVideoTitleLabel.text = self.guidanceState.currentInstruction;
    self.countdownLabel.hidden = NO;
    self.countdownValue = 3;
    self.countdownLabel.text = @"3";

    [self.countdownTimer invalidate];
    self.countdownTimer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                           target:self
                                                         selector:@selector(handleCountdownTick)
                                                         userInfo:nil
                                                          repeats:YES];
}

- (void)handleCountdownTick {
    self.countdownValue -= 1;
    if (self.countdownValue > 0) {
        self.countdownLabel.text = [NSString stringWithFormat:@"%ld", (long)self.countdownValue];
        return;
    }

    [self.countdownTimer invalidate];
    self.countdownTimer = nil;
    [self startRecordingAfterPreparation];
}

- (void)startRecordingAfterPreparation {
    [self.guideVideoPlayer pause];
    self.guideVideoPlayer = nil;
    [self.guideVideoPlayerLayer removeFromSuperlayer];
    self.guideVideoPlayerLayer = nil;
    self.guideVideoOverlayView.hidden = YES;
    self.guideVideoSkipButton.hidden = YES;
    self.countdownLabel.hidden = YES;
    self.isPreparingToRecord = NO;

    self.recordingDurationLabel.text = @"00:00.0";
    self.recordingDurationLabel.hidden = NO;
    [[CD3DGSCameraService shared] startRecording];
    [self startPitchMonitoringIfNeeded];
    [self updateGuidanceUI];
}

- (void)cancelPreparationFlow {
    [[NSNotificationCenter defaultCenter] removeObserver:self
                                                    name:AVPlayerItemDidPlayToEndTimeNotification
                                                  object:nil];
    [self.countdownTimer invalidate];
    self.countdownTimer = nil;
    [self.guideVideoPlayer pause];
    self.guideVideoPlayer = nil;
    [self.guideVideoPlayerLayer removeFromSuperlayer];
    self.guideVideoPlayerLayer = nil;
    self.guideVideoOverlayView.hidden = YES;
    self.guideVideoSkipButton.hidden = YES;
    self.countdownLabel.hidden = YES;
    self.isPreparingToRecord = NO;
    [self stopPitchMonitoring];
}

- (void)recordingDidFinish:(NSNotification *)notification {
    NSURL *videoURL = notification.userInfo[CD3DGSCameraRecordingURLKey];
    if (!videoURL) {
        self.isFinishingCurrentRecording = NO;
        self.recordButton.enabled = YES;
        [self updateGuidanceUI];
        return;
    }

    [self.guidanceState completeCurrentStepWithVideoURL:videoURL];
    self.isFinishingCurrentRecording = NO;
    self.recordingDurationLabel.hidden = YES;
    [self stopPitchMonitoring];
    [self updateGuidanceUI];

    if (self.guidanceState.isComplete) {
        CDRoomVideoReviewViewController *reviewVC = [[CDRoomVideoReviewViewController alloc] initWithRoom:[self demoPassedRoom]
                                                                                                videoURLs:self.guidanceState.completedVideoURLs
                                                                                      singleRoomDemoFlow:YES];
        [self.navigationController pushViewController:reviewVC animated:YES];
    }
}

- (CDRoomItem *)demoPassedRoom {
    CDRoomItem *room = [[CDRoomItem alloc] init];
    room.roomId = @"demo_passed_room";
    room.roomName = @"示例房间（已通过）";
    room.captureComplete = YES;
    room.auditStatus = 2;
    room.auditReason = @"";
    return room;
}

- (void)goBack {
    if ([[CD3DGSCameraService shared] isRecording]) {
        [[CD3DGSCameraService shared] stopRecording];
    }
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
