#import "CDCameraViewController.h"
#import "CDCameraService.h"
#import "CDVideoListViewController.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

@interface CDCameraViewController ()

@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
@property (nonatomic, strong) UIView *topBar;
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIView *recordingIndicator;
@property (nonatomic, strong) UIButton *recordButton;
@property (nonatomic, strong) UILabel *hintLabel;
@property (nonatomic, strong) NSTimer *uiTimer;

@end

@implementation CDCameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupUI];
    [self setupCamera];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    // Update previewContainer frame
    UIView *previewContainer = [self.view viewWithTag:100];
    previewContainer.frame = self.view.bounds;

    // Update previewLayer frame
    self.previewLayer.frame = previewContainer.bounds;

    // Update topBar frame
    self.topBar.frame = CGRectMake(0, 0, self.view.bounds.size.width, 100);

    // Update bottomBar frame
    UIView *bottomBar = [self.view viewWithTag:200];
    if (!bottomBar) {
        bottomBar = [self.view.subviews lastObject];
    }
    if (bottomBar) {
        bottomBar.frame = CGRectMake(0, self.view.bounds.size.height - 180, self.view.bounds.size.width, 180);

        // Update recordButton position
        if (self.recordButton) {
            CGFloat screenWidth = self.view.bounds.size.width;
            CGFloat btnSize = 80;
            CGFloat btnX = (screenWidth - btnSize) / 2;
            self.recordButton.frame = CGRectMake(btnX, 50, btnSize, btnSize);
        }
    }

    // Update duration/recording indicator positions
    self.durationLabel.frame = CGRectMake(self.view.bounds.size.width - 120, 25, 100, 30);
    self.recordingIndicator.frame = CGRectMake(self.view.bounds.size.width - 145, 32, 12, 12);

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
    [[CDCameraService shared] startSession];
    [self startUITimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [[CDCameraService shared] stopSession];
    [self stopUITimer];
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)setupUI {
    // Preview Container
    UIView *previewContainer = [[UIView alloc] init];
    previewContainer.frame = self.view.bounds;
    previewContainer.backgroundColor = [UIColor blackColor];
    previewContainer.tag = 100;
    [self.view addSubview:previewContainer];

    // Top Bar
    self.topBar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 100)];
    [self.view addSubview:self.topBar];

    // Resolution Label
    UILabel *resLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 20, 100, 25)];
    resLabel.text = @"1080P 30fps";
    resLabel.textColor = [UIColor whiteColor];
    resLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.topBar addSubview:resLabel];

    // Params Label
    UILabel *paramsLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 50, 250, 40)];
    paramsLabel.text = @"0.5x广角 | 4500K | 1/250 | ISO320";
    paramsLabel.textColor = [[UIColor whiteColor] colorWithAlphaComponent:0.8];
    paramsLabel.font = [UIFont systemFontOfSize:12];
    [self.topBar addSubview:paramsLabel];

    // Duration Label
    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 120, 25, 100, 30)];
    self.durationLabel.text = @"00:00.0";
    self.durationLabel.textColor = [UIColor whiteColor];
    self.durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
    self.durationLabel.textAlignment = NSTextAlignmentRight;
    self.durationLabel.hidden = YES;
    [self.topBar addSubview:self.durationLabel];

    // Recording Indicator
    self.recordingIndicator = [[UIView alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 145, 32, 12, 12)];
    self.recordingIndicator.backgroundColor = [UIColor redColor];
    self.recordingIndicator.layer.cornerRadius = 6;
    self.recordingIndicator.hidden = YES;
    [self.topBar addSubview:self.recordingIndicator];

    // Bottom Bar
    UIView *bottomBar = [[UIView alloc] initWithFrame:CGRectMake(0, self.view.bounds.size.height - 180, self.view.bounds.size.width, 180)];
    bottomBar.tag = 200;
    [self.view addSubview:bottomBar];

    // Hint Label
    self.hintLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, self.view.bounds.size.width, 20)];
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
    self.recordButton = [UIButton buttonWithType:UIButtonTypeCustom];
    CGFloat screenWidth = self.view.bounds.size.width;
    CGFloat btnSize = 80;
    CGFloat btnX = (screenWidth - btnSize) / 2;
    CGFloat btnY = 50;
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

- (void)showVideoList {
    CDVideoListViewController *listVC = [[CDVideoListViewController alloc] init];
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
