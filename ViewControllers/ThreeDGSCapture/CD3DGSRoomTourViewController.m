#import "CD3DGSRoomTourViewController.h"
#import "AppDelegate.h"

static const CGFloat CD3DGSTourControlSize = 52.0;
static const CGFloat CD3DGSTourPanelRadius = 8.0;

typedef NS_ENUM(NSInteger, CD3DGSTourDirection) {
    CD3DGSTourDirectionForward,
    CD3DGSTourDirectionBackward,
    CD3DGSTourDirectionLeft,
    CD3DGSTourDirectionRight,
    CD3DGSTourDirectionUp,
    CD3DGSTourDirectionDown
};

@interface CD3DGSRoomTourViewController ()

@property (nonatomic, copy) NSString *roomName;
@property (nonatomic, strong) UIImageView *backgroundImageView;
@property (nonatomic, strong) UIView *fallbackRoomView;
@property (nonatomic, strong) UIView *topOverlayView;
@property (nonatomic, strong) UIView *directionPadView;
@property (nonatomic, strong) UIButton *autoTourButton;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) CADisplayLink *displayLink;
@property (nonatomic, assign) CGPoint sceneOffset;
@property (nonatomic, assign) CGFloat sceneScale;
@property (nonatomic, assign) CGPoint movementVector;
@property (nonatomic, assign, getter=isAutoTouring) BOOL autoTouring;
@property (nonatomic, assign) CFTimeInterval autoTourStartTime;

@end

@implementation CD3DGSRoomTourViewController

- (instancetype)initWithRoomName:(NSString *)roomName {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _roomName = [roomName copy];
        _sceneScale = 1.08;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    [self setupScene];
    [self setupTopOverlay];
    [self setupMovementControls];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    [self applyLandscapeRightOrientation];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    [self startDisplayLinkIfNeeded];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    [self layoutTourInterface];
    [self applySceneTransformAnimated:NO];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    [self stopDisplayLink];
    [self restorePortraitOrientation];
}

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskLandscapeRight;
}

- (UIInterfaceOrientation)preferredInterfaceOrientationForPresentation {
    return UIInterfaceOrientationLandscapeRight;
}

- (BOOL)prefersStatusBarHidden {
    return YES;
}

- (void)setupScene {
    self.backgroundImageView = [[UIImageView alloc] initWithFrame:CGRectZero];
    self.backgroundImageView.image = [UIImage imageNamed:@"living_room_bg"];
    self.backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.backgroundImageView.clipsToBounds = NO;
    [self.view addSubview:self.backgroundImageView];

    self.fallbackRoomView = [[UIView alloc] initWithFrame:CGRectZero];
    self.fallbackRoomView.hidden = self.backgroundImageView.image != nil;
    [self.view insertSubview:self.fallbackRoomView belowSubview:self.backgroundImageView];
    [self buildFallbackLivingRoomScene];

    UIView *shadeView = [[UIView alloc] initWithFrame:CGRectZero];
    shadeView.tag = 9001;
    shadeView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.14];
    [self.view addSubview:shadeView];
}

- (void)setupTopOverlay {
    self.topOverlayView = [[UIView alloc] initWithFrame:CGRectZero];
    self.topOverlayView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.32];
    self.topOverlayView.layer.cornerRadius = CD3DGSTourPanelRadius;
    self.topOverlayView.clipsToBounds = YES;
    [self.view addSubview:self.topOverlayView];

    UIButton *backButton = [UIButton buttonWithType:UIButtonTypeSystem];
    backButton.tag = 1001;
    [backButton setImage:[UIImage systemImageNamed:@"chevron.left"] forState:UIControlStateNormal];
    [backButton setTitle:@"返回" forState:UIControlStateNormal];
    [backButton setTintColor:[UIColor whiteColor]];
    [backButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    backButton.titleLabel.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    backButton.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    [backButton addTarget:self action:@selector(backTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.topOverlayView addSubview:backButton];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    titleLabel.tag = 1002;
    titleLabel.text = [NSString stringWithFormat:@"%@ 3D漫游", self.roomName ?: @"客厅"];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont systemFontOfSize:15.0 weight:UIFontWeightSemibold];
    [self.topOverlayView addSubview:titleLabel];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.text = @"手动漫游";
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor colorWithRed:0x1A / 255.0 green:0x66 / 255.0 blue:0xFF / 255.0 alpha:1.0];
    self.statusLabel.font = [UIFont systemFontOfSize:11.0 weight:UIFontWeightMedium];
    self.statusLabel.backgroundColor = [UIColor colorWithRed:0xE0 / 255.0 green:0xED / 255.0 blue:0xFF / 255.0 alpha:0.96];
    self.statusLabel.layer.cornerRadius = 2.0;
    self.statusLabel.clipsToBounds = YES;
    [self.topOverlayView addSubview:self.statusLabel];
}

- (void)setupMovementControls {
    self.directionPadView = [[UIView alloc] initWithFrame:CGRectZero];
    self.directionPadView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
    self.directionPadView.layer.cornerRadius = CD3DGSTourPanelRadius;
    self.directionPadView.clipsToBounds = YES;
    [self.view addSubview:self.directionPadView];

    [self addDirectionButtonWithSymbol:@"arrow.up" direction:CD3DGSTourDirectionUp tag:2001];
    [self addDirectionButtonWithSymbol:@"arrow.left" direction:CD3DGSTourDirectionLeft tag:2002];
    [self addDirectionButtonWithSymbol:@"arrow.right" direction:CD3DGSTourDirectionRight tag:2003];
    [self addDirectionButtonWithSymbol:@"arrow.down" direction:CD3DGSTourDirectionDown tag:2004];

    UIView *depthPanel = [[UIView alloc] initWithFrame:CGRectZero];
    depthPanel.tag = 3000;
    depthPanel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.28];
    depthPanel.layer.cornerRadius = CD3DGSTourPanelRadius;
    depthPanel.clipsToBounds = YES;
    [self.view addSubview:depthPanel];

    UIButton *forwardButton = [self movementButtonWithSymbol:@"plus.magnifyingglass" title:@"前进"];
    forwardButton.tag = 3001;
    [forwardButton addTarget:self action:@selector(forwardTapped) forControlEvents:UIControlEventTouchUpInside];
    [depthPanel addSubview:forwardButton];

    UIButton *backwardButton = [self movementButtonWithSymbol:@"minus.magnifyingglass" title:@"后退"];
    backwardButton.tag = 3002;
    [backwardButton addTarget:self action:@selector(backwardTapped) forControlEvents:UIControlEventTouchUpInside];
    [depthPanel addSubview:backwardButton];

    self.autoTourButton = [self movementButtonWithSymbol:@"play.fill" title:@"自动"];
    self.autoTourButton.tag = 3003;
    [self.autoTourButton addTarget:self action:@selector(autoTourTapped) forControlEvents:UIControlEventTouchUpInside];
    [depthPanel addSubview:self.autoTourButton];
}

- (void)addDirectionButtonWithSymbol:(NSString *)symbol direction:(CD3DGSTourDirection)direction tag:(NSInteger)tag {
    UIButton *button = [self iconButtonWithSymbol:symbol];
    button.tag = tag;
    button.accessibilityIdentifier = [NSString stringWithFormat:@"tour_direction_%ld", (long)direction];
    [button addTarget:self action:@selector(directionButtonTouched:) forControlEvents:UIControlEventTouchDown];
    [button addTarget:self action:@selector(directionButtonReleased:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [self.directionPadView addSubview:button];
}

- (UIButton *)iconButtonWithSymbol:(NSString *)symbol {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.92];
    button.tintColor = [UIColor colorWithRed:0x22 / 255.0 green:0x22 / 255.0 blue:0x22 / 255.0 alpha:1.0];
    button.layer.cornerRadius = 4.0;
    [button setImage:[UIImage systemImageNamed:symbol] forState:UIControlStateNormal];
    return button;
}

- (UIButton *)movementButtonWithSymbol:(NSString *)symbol title:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.92];
    button.layer.cornerRadius = 4.0;
    UIButtonConfiguration *configuration = [UIButtonConfiguration plainButtonConfiguration];
    configuration.image = [UIImage systemImageNamed:symbol];
    configuration.title = title;
    configuration.imagePlacement = NSDirectionalRectEdgeTop;
    configuration.imagePadding = 2.0;
    configuration.baseForegroundColor = [UIColor colorWithRed:0x22 / 255.0 green:0x22 / 255.0 blue:0x22 / 255.0 alpha:1.0];
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey,id> * _Nonnull(NSDictionary<NSAttributedStringKey,id> * _Nonnull textAttributes) {
        NSMutableDictionary<NSAttributedStringKey, id> *attributes = [textAttributes mutableCopy];
        attributes[NSFontAttributeName] = [UIFont systemFontOfSize:12.0 weight:UIFontWeightMedium];
        return attributes;
    };
    button.configuration = configuration;
    return button;
}

- (void)layoutTourInterface {
    CGRect bounds = self.view.bounds;
    if (CGRectIsEmpty(bounds)) {
        return;
    }

    UIView *shadeView = [self.view viewWithTag:9001];
    shadeView.frame = bounds;
    self.backgroundImageView.frame = CGRectInset(bounds, -80.0, -48.0);
    self.fallbackRoomView.frame = self.backgroundImageView.frame;

    CGFloat topInset = self.view.safeAreaInsets.top;
    self.topOverlayView.frame = CGRectMake(16.0, topInset + 12.0, MIN(360.0, CGRectGetWidth(bounds) - 32.0), 48.0);
    UIButton *backButton = [self.topOverlayView viewWithTag:1001];
    UILabel *titleLabel = [self.topOverlayView viewWithTag:1002];
    backButton.frame = CGRectMake(8.0, 4.0, 72.0, 40.0);
    titleLabel.frame = CGRectMake(CGRectGetMaxX(backButton.frame) + 4.0, 0, 154.0, 48.0);
    self.statusLabel.frame = CGRectMake(CGRectGetWidth(self.topOverlayView.bounds) - 80.0, 13.0, 64.0, 22.0);

    CGFloat bottomInset = MAX(self.view.safeAreaInsets.bottom, 12.0);
    self.directionPadView.frame = CGRectMake(24.0, CGRectGetHeight(bounds) - 176.0 - bottomInset, 176.0, 152.0);

    UIButton *upButton = [self.directionPadView viewWithTag:2001];
    UIButton *leftButton = [self.directionPadView viewWithTag:2002];
    UIButton *rightButton = [self.directionPadView viewWithTag:2003];
    UIButton *downButton = [self.directionPadView viewWithTag:2004];
    upButton.frame = CGRectMake(62.0, 12.0, CD3DGSTourControlSize, 40.0);
    leftButton.frame = CGRectMake(12.0, 56.0, CD3DGSTourControlSize, CD3DGSTourControlSize);
    rightButton.frame = CGRectMake(112.0, 56.0, CD3DGSTourControlSize, CD3DGSTourControlSize);
    downButton.frame = CGRectMake(62.0, 100.0, CD3DGSTourControlSize, 40.0);

    UIView *depthPanel = [self.view viewWithTag:3000];
    CGFloat depthW = 212.0;
    depthPanel.frame = CGRectMake(CGRectGetWidth(bounds) - depthW - 24.0, CGRectGetHeight(bounds) - 88.0 - bottomInset, depthW, 64.0);
    UIButton *forwardButton = [depthPanel viewWithTag:3001];
    UIButton *backwardButton = [depthPanel viewWithTag:3002];
    UIButton *autoButton = [depthPanel viewWithTag:3003];
    forwardButton.frame = CGRectMake(8.0, 8.0, 60.0, 48.0);
    backwardButton.frame = CGRectMake(76.0, 8.0, 60.0, 48.0);
    autoButton.frame = CGRectMake(144.0, 8.0, 60.0, 48.0);
}

- (void)buildFallbackLivingRoomScene {
    CAGradientLayer *wallLayer = [CAGradientLayer layer];
    wallLayer.name = @"wall";
    wallLayer.colors = @[
        (id)[UIColor colorWithRed:0xE9 / 255.0 green:0xEE / 255.0 blue:0xF5 / 255.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0xC9 / 255.0 green:0xD6 / 255.0 blue:0xE6 / 255.0 alpha:1.0].CGColor
    ];
    wallLayer.startPoint = CGPointMake(0.5, 0.0);
    wallLayer.endPoint = CGPointMake(0.5, 1.0);
    [self.fallbackRoomView.layer addSublayer:wallLayer];

    NSArray<UIView *> *objects = @[
        [self sceneBlockWithColor:[UIColor colorWithRed:0x60 / 255.0 green:0x70 / 255.0 blue:0x7F / 255.0 alpha:1.0] radius:10.0 tag:4101],
        [self sceneBlockWithColor:[UIColor colorWithRed:0x29 / 255.0 green:0x37 / 255.0 blue:0x46 / 255.0 alpha:1.0] radius:6.0 tag:4102],
        [self sceneBlockWithColor:[UIColor colorWithRed:0xF3 / 255.0 green:0xF0 / 255.0 blue:0xE8 / 255.0 alpha:1.0] radius:8.0 tag:4103],
        [self sceneBlockWithColor:[UIColor colorWithRed:0xB7 / 255.0 green:0xC3 / 255.0 blue:0xD0 / 255.0 alpha:1.0] radius:4.0 tag:4104]
    ];
    for (UIView *view in objects) {
        [self.fallbackRoomView addSubview:view];
    }
}

- (UIView *)sceneBlockWithColor:(UIColor *)color radius:(CGFloat)radius tag:(NSInteger)tag {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];
    view.backgroundColor = color;
    view.layer.cornerRadius = radius;
    view.tag = tag;
    return view;
}

- (void)layoutFallbackSceneIfNeeded {
    CGRect bounds = self.fallbackRoomView.bounds;
    CAGradientLayer *wallLayer = (CAGradientLayer *)[self.fallbackRoomView.layer.sublayers firstObject];
    wallLayer.frame = bounds;

    UIView *sofa = [self.fallbackRoomView viewWithTag:4101];
    UIView *tv = [self.fallbackRoomView viewWithTag:4102];
    UIView *rug = [self.fallbackRoomView viewWithTag:4103];
    UIView *window = [self.fallbackRoomView viewWithTag:4104];
    sofa.frame = CGRectMake(CGRectGetWidth(bounds) * 0.18, CGRectGetHeight(bounds) * 0.55, CGRectGetWidth(bounds) * 0.32, CGRectGetHeight(bounds) * 0.18);
    tv.frame = CGRectMake(CGRectGetWidth(bounds) * 0.62, CGRectGetHeight(bounds) * 0.34, CGRectGetWidth(bounds) * 0.18, CGRectGetHeight(bounds) * 0.12);
    rug.frame = CGRectMake(CGRectGetWidth(bounds) * 0.38, CGRectGetHeight(bounds) * 0.70, CGRectGetWidth(bounds) * 0.28, CGRectGetHeight(bounds) * 0.12);
    window.frame = CGRectMake(CGRectGetWidth(bounds) * 0.18, CGRectGetHeight(bounds) * 0.18, CGRectGetWidth(bounds) * 0.22, CGRectGetHeight(bounds) * 0.18);
}

- (void)directionButtonTouched:(UIButton *)sender {
    [self stopAutoTour];
    switch (sender.tag) {
        case 2001:
            self.movementVector = CGPointMake(0.0, 1.0);
            self.statusLabel.text = @"向上";
            break;
        case 2002:
            self.movementVector = CGPointMake(1.0, 0.0);
            self.statusLabel.text = @"向左";
            break;
        case 2003:
            self.movementVector = CGPointMake(-1.0, 0.0);
            self.statusLabel.text = @"向右";
            break;
        case 2004:
            self.movementVector = CGPointMake(0.0, -1.0);
            self.statusLabel.text = @"向下";
            break;
        default:
            self.movementVector = CGPointZero;
            break;
    }
}

- (void)directionButtonReleased:(UIButton *)sender {
    self.movementVector = CGPointZero;
    self.statusLabel.text = @"手动漫游";
}

- (void)forwardTapped {
    [self stopAutoTour];
    self.sceneScale = MIN(1.20, self.sceneScale + 0.04);
    self.statusLabel.text = @"前进";
    [self applySceneTransformAnimated:YES];
}

- (void)backwardTapped {
    [self stopAutoTour];
    self.sceneScale = MAX(1.0, self.sceneScale - 0.04);
    self.statusLabel.text = @"后退";
    [self applySceneTransformAnimated:YES];
}

- (void)autoTourTapped {
    self.autoTouring = !self.isAutoTouring;
    if (self.isAutoTouring) {
        self.autoTourStartTime = CACurrentMediaTime();
        [self updateMovementButton:self.autoTourButton symbol:@"pause.fill" title:@"暂停"];
        self.statusLabel.text = @"自动漫游";
    } else {
        [self stopAutoTour];
    }
}

- (void)updateMovementButton:(UIButton *)button symbol:(NSString *)symbol title:(NSString *)title {
    UIButtonConfiguration *configuration = button.configuration;
    configuration.image = [UIImage systemImageNamed:symbol];
    configuration.title = title;
    button.configuration = configuration;
}

- (void)stopAutoTour {
    if (!self.isAutoTouring) {
        return;
    }
    self.autoTouring = NO;
    [self updateMovementButton:self.autoTourButton symbol:@"play.fill" title:@"自动"];
    self.statusLabel.text = @"手动漫游";
}

- (void)startDisplayLinkIfNeeded {
    if (self.displayLink) {
        return;
    }
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(stepScene)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopDisplayLink {
    [self.displayLink invalidate];
    self.displayLink = nil;
}

- (void)stepScene {
    if (self.isAutoTouring) {
        CFTimeInterval elapsed = CACurrentMediaTime() - self.autoTourStartTime;
        self.sceneOffset = CGPointMake(sin(elapsed * 0.42) * 42.0, cos(elapsed * 0.36) * 28.0);
        self.sceneScale = 1.08 + sin(elapsed * 0.30) * 0.05;
        [self applySceneTransformAnimated:NO];
        return;
    }

    if (CGPointEqualToPoint(self.movementVector, CGPointZero)) {
        return;
    }

    self.sceneOffset = CGPointMake(self.sceneOffset.x + self.movementVector.x * 3.2,
                                   self.sceneOffset.y + self.movementVector.y * 2.6);
    self.sceneOffset = [self clampedSceneOffset:self.sceneOffset];
    [self applySceneTransformAnimated:NO];
}

- (CGPoint)clampedSceneOffset:(CGPoint)offset {
    CGFloat maxX = MAX(32.0, CGRectGetWidth(self.view.bounds) * 0.08);
    CGFloat maxY = MAX(20.0, CGRectGetHeight(self.view.bounds) * 0.08);
    return CGPointMake(MAX(-maxX, MIN(maxX, offset.x)), MAX(-maxY, MIN(maxY, offset.y)));
}

- (void)applySceneTransformAnimated:(BOOL)animated {
    [self layoutFallbackSceneIfNeeded];
    self.sceneOffset = [self clampedSceneOffset:self.sceneOffset];
    CGAffineTransform transform = CGAffineTransformConcat(CGAffineTransformMakeScale(self.sceneScale, self.sceneScale),
                                                          CGAffineTransformMakeTranslation(self.sceneOffset.x, self.sceneOffset.y));
    void (^changes)(void) = ^{
        self.backgroundImageView.transform = transform;
        self.fallbackRoomView.transform = transform;
    };
    if (animated) {
        [UIView animateWithDuration:0.22 delay:0 options:UIViewAnimationOptionCurveEaseOut animations:changes completion:nil];
    } else {
        changes();
    }
}

- (void)applyLandscapeRightOrientation {
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    appDelegate.supportedOrientationMask = UIInterfaceOrientationMaskLandscapeRight;

    [self setNeedsUpdateOfSupportedInterfaceOrientations];
    [self.navigationController setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowScene *windowScene = self.view.window.windowScene;
    if (windowScene) {
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskLandscapeRight];
        [windowScene requestGeometryUpdateWithPreferences:preferences errorHandler:nil];
    }
}

- (void)restorePortraitOrientation {
    AppDelegate *appDelegate = (AppDelegate *)UIApplication.sharedApplication.delegate;
    appDelegate.supportedOrientationMask = UIInterfaceOrientationMaskPortrait;

    [self.navigationController setNeedsUpdateOfSupportedInterfaceOrientations];
    UIWindowScene *windowScene = self.view.window.windowScene;
    if (windowScene) {
        UIWindowSceneGeometryPreferencesIOS *preferences = [[UIWindowSceneGeometryPreferencesIOS alloc] initWithInterfaceOrientations:UIInterfaceOrientationMaskPortrait];
        [windowScene requestGeometryUpdateWithPreferences:preferences errorHandler:nil];
    }
}

- (void)backTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

@end
