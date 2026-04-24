#import "CDCameraViewController.h"
#import "CDCameraService.h"
#import "CDVideoListViewController.h"
#import "CDCameraSettingsViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface CDCameraViewController ()

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UILabel *paramsLabel;
@property (nonatomic, strong) UIView *recordingIndicator;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIButton *backButton;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) NSTimer *uiTimer;

@end

@implementation CDCameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"参数相机";
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self setupCamera];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(settingsDidChange)
                                                 name:@"CDCameraSettingsDidChange"
                                               object:nil];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(cameraDidReload)
                                                 name:@"CDCameraDidReload"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)settingsDidChange {
    [self updateSettingsLabels];
}

- (void)cameraDidReload {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *previewContainer = [self.view viewWithTag:100];
        self.previewLayer.frame = previewContainer.bounds;
        [self updateSettingsLabels];
    });
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat screenWidth = self.view.bounds.size.width;

    // Update previewContainer frame
    UIView *previewContainer = [self.view viewWithTag:100];
    previewContainer.frame = self.view.bounds;

    // Update previewLayer frame
    self.previewLayer.frame = previewContainer.bounds;

    // Update topBar frame
    self.topBar.frame = CGRectMake(0, safeTop, screenWidth, 100);

    // Update center container frame
    UIView *centerContainer = self.topBar.subviews.count > 2 ? self.topBar.subviews[2] : nil;
    if (centerContainer) {
        centerContainer.frame = CGRectMake(60, 20, screenWidth - 120, 60);
        UILabel *resLabel = [centerContainer viewWithTag:300];
        if (resLabel) {
            resLabel.frame = CGRectMake(0, 0, centerContainer.bounds.size.width, 25);
        }
        self.paramsLabel.frame = CGRectMake(0, 28, centerContainer.bounds.size.width, 25);
    }

    // Update back button position
    self.backButton.frame = CGRectMake(16, 35, 30, 30);

    // Update settings button position
    self.settingsButton.frame = CGRectMake(screenWidth - 46, 35, 30, 30);

    // Update duration/recording indicator positions
    self.durationLabel.frame = CGRectMake(screenWidth - 120, 64, 90, 24);
    self.recordingIndicator.frame = CGRectMake(screenWidth - 28, 70, 12, 12);

    // Update bottomBar frame
    UIView *bottomBar = [self.view viewWithTag:200];
    if (!bottomBar) {
        bottomBar = [self.view.subviews lastObject];
    }
    if (bottomBar) {
        bottomBar.frame = CGRectMake(0, self.view.bounds.size.height - 180, screenWidth, 180);

        // Update recordButton position
        if (self.recordButton) {
            CGFloat btnSize = 80;
            CGFloat btnX = (screenWidth - btnSize) / 2;
            self.recordButton.frame = CGRectMake(btnX, 50, btnSize, btnSize);
        }
    }

#if DEBUG
    if (self.recordButton) {
        CGPoint localCenter = CGPointMake(CGRectGetMidX(self.recordButton.bounds), CGRectGetMidY(self.recordButton.bounds));
        CGPoint globalCenter = [self.recordButton convertPoint:localCenter toView:self.view];
        UIView *hitView = [self.view hitTest:globalCenter withEvent:nil];
        NSLog(@"[Debug] recordButton frame=%@ enabled=%d hidden=%d alpha=%.2f userInteraction=%d hitTest=%@",
              NSStringFromCGRect(self.recordButton.frame),
              self.recordButton.enabled,
              self.recordButton.hidden,
              self.recordButton.alpha,
              self.recordButton.userInteractionEnabled,
              hitView);
    }
#endif
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [[CDCameraService shared] startSession];
    [self startUITimer];
    [self updateSettingsLabels];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [[CDCameraService shared] stopSession];
    [self stopUITimer];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)setupUI {
    CGFloat safeTop = self.view.safeAreaInsets.top;
    CGFloat screenWidth = self.view.bounds.size.width;

    // Preview Container
    UIView *previewContainer = [[UIView alloc] init];
    previewContainer.frame = self.view.bounds;
    previewContainer.backgroundColor = [UIColor blackColor];
    previewContainer.tag = 100;
    [self.view addSubview:previewContainer];

    // Top Bar - below safe area
    self.topBar = [[UIView alloc] initWithFrame:CGRectMake(0, safeTop, screenWidth, 100)];
    [self.view addSubview:self.topBar];

    // Back Button - left side, vertically centered in top bar
    self.backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.backButton.frame = CGRectMake(16, 35, 30, 30);
    UIImage *backImg = [UIImage systemImageNamed:@"chevron.left"];
    [self.backButton setImage:backImg forState:UIControlStateNormal];
    self.backButton.tintColor = [UIColor whiteColor];
    [self.backButton addTarget:self action:@selector(goBack) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.backButton];

    // Settings Button - right side, vertically centered in top bar
    self.settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.settingsButton.frame = CGRectMake(screenWidth - 46, 35, 30, 30);
    UIImage *gearImg = [UIImage systemImageNamed:@"gearshape.fill"];
    [self.settingsButton setImage:gearImg forState:UIControlStateNormal];
    self.settingsButton.tintColor = [UIColor whiteColor];
    [self.settingsButton addTarget:self action:@selector(showSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.topBar addSubview:self.settingsButton];

    // Center container for labels
    UIView *centerContainer = [[UIView alloc] init];
    centerContainer.frame = CGRectMake(60, 20, screenWidth - 120, 60);
    [self.topBar addSubview:centerContainer];

    // Resolution Label - top center
    UILabel *resLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, centerContainer.bounds.size.width, 25)];
    resLabel.text = @"1080P 30fps";
    resLabel.textColor = [UIColor whiteColor];
    resLabel.font = [UIFont boldSystemFontOfSize:14];
    resLabel.textAlignment = NSTextAlignmentCenter;
    resLabel.tag = 300;
    [centerContainer addSubview:resLabel];

    // Params Label - below resolution
    self.paramsLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 28, centerContainer.bounds.size.width, 25)];
    self.paramsLabel.text = @"0.5x广角 | 4500K | 1/250 | ISO320";
    self.paramsLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.paramsLabel.font = [UIFont systemFontOfSize:12];
    self.paramsLabel.textAlignment = NSTextAlignmentCenter;
    [centerContainer addSubview:self.paramsLabel];

    // Recording Indicator - right side
    self.recordingIndicator = [[UIView alloc] initWithFrame:CGRectMake(screenWidth - 28, 70, 12, 12)];
    self.recordingIndicator.backgroundColor = [UIColor redColor];
    self.recordingIndicator.layer.cornerRadius = 6;
    self.recordingIndicator.hidden = YES;
    [self.topBar addSubview:self.recordingIndicator];

    // Duration Label - left of recording indicator
    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(screenWidth - 120, 64, 90, 24)];
    self.durationLabel.text = @"00:00.0";
    self.durationLabel.textColor = [UIColor whiteColor];
    self.durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:16 weight:UIFontWeightMedium];
    self.durationLabel.textAlignment = NSTextAlignmentRight;
    self.durationLabel.hidden = YES;
    [self.topBar addSubview:self.durationLabel];

    // Bottom Bar
    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 180, screenWidth, 180)];
    bottomBar.tag = 200;
    [self.view addSubview:bottomBar];

    // Hint Label
    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, screenWidth, 20)];
    self.hintLabel.text = @"点击录制按钮开始采集";
    self.hintLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    self.hintLabel.font = [UIFont systemFontOfSize:13];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    [bottomBar addSubview:self.hintLabel];

    // Video List Button
    UIButton *listBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    listBtn.frame = CGRectMake(50, 60, 60, 70);
    UIImage *folderImg = [UIImage systemImageNamed:@"folder.fill"];
    [listBtn setImage:folderImg forState:UIControlStateNormal];
    listBtn.tintColor = [UIColor whiteColor];
    [listBtn setTitle:@"视频" forState:UIControlStateNormal];
    listBtn.titleLabel.font = [UIFont systemFontOfSize:11];
    [listBtn addTarget:self action:@selector(showVideoList) forControlEvents:UIControlEventTouchUpInside];
    [bottomBar addSubview:listBtn];

    // Record Button
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
}

- (void)setupCamera {
    dispatch_async(dispatch_get_main_queue(), ^{
        AVCaptureVideoPreviewLayer *preview = [[CDCameraService shared] setupCamera];
        if (!preview) {
            [self showAlert:@"相机错误" message:@"无法初始化相机"];
            return;
        }

        self.previewLayer = preview;
        preview.frame = self.view.bounds;

        UIView *container = [self.view viewWithTag:100];
        [container.layer addSublayer:preview];

        [[CDCameraService shared] startSession];
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
    BOOL isRecording = [[CDCameraService shared] isRecording];
    NSTimeInterval duration = [[CDCameraService shared] recordingDuration];

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

    // Remove existing shape layers (except border)
    for (CALayer *layer in [self.recordButton.layer.sublayers copy]) {
        if ([layer isKindOfClass:[CAShapeLayer class]]) {
            [layer removeFromSuperlayer];
        }
    }

    // Create inner shape layer
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

    // Update resolution & fps label
    UILabel *resLabel = [self.topBar viewWithTag:300];
    NSInteger resolution = [defaults integerForKey:@"CDSettingsResolution"];
    NSArray *resolutions = @[@"720P", @"1080P", @"4K"];
    NSInteger frameRate = [defaults integerForKey:@"CDSettingsFrameRate"];
    if (frameRate == 0) frameRate = 30;
    resLabel.text = [NSString stringWithFormat:@"%@ %ldfps", resolutions[resolution], (long)frameRate];

    // Update params label
    NSInteger cameraLens = [defaults integerForKey:@"CDSettingsCameraLens"];
    NSArray *lensNames = @[@"0.5x广角", @"1.0x广角"];
    float whiteBalance = [defaults floatForKey:@"CDSettingsWhiteBalance"];
    if (whiteBalance == 0) whiteBalance = 4500;
    float shutterSpeed = [defaults floatForKey:@"CDSettingsShutterSpeed"];
    if (shutterSpeed == 0) shutterSpeed = 250;
    float iso = [defaults floatForKey:@"CDSettingsISO"];
    if (iso == 0) iso = 320;
    BOOL isoAuto = [defaults boolForKey:@"CDSettingsISOAuto"];

    if (isoAuto) {
        self.paramsLabel.text = [NSString stringWithFormat:@"%@ | %.0fK | 1/%.0f | ISO自动",
                                lensNames[cameraLens], whiteBalance, shutterSpeed];
    } else {
        self.paramsLabel.text = [NSString stringWithFormat:@"%@ | %.0fK | 1/%.0f | ISO%.0f",
                                lensNames[cameraLens], whiteBalance, shutterSpeed, iso];
    }
}

- (void)toggleRecording {
    NSLog(@"toggleRecording called");
    if ([[CDCameraService shared] isRecording]) {
        NSLog(@"Stopping recording...");
        [[CDCameraService shared] stopRecording];
    } else {
        NSLog(@"Starting recording...");
        [[CDCameraService shared] startRecording];
    }
}

- (void)goBack {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showVideoList {
    CDVideoListViewController *listVC = [[CDVideoListViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:listVC];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)showSettings {
    CDCameraSettingsViewController *settingsVC = [[CDCameraSettingsViewController alloc] init];
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:settingsVC];
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
