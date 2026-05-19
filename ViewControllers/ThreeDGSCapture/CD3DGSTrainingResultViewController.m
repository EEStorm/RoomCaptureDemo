#import "CD3DGSTrainingResultViewController.h"
#import "CD3DGSTrainingResultSummary.h"
#import "CD3DGSRoomTourViewController.h"

static const CGFloat CD3DGSCardRadius = 8.0;
static const CGFloat CD3DGSScreenMargin = 16.0;

@interface CD3DGSGaussianPreviewView : UIView

@end

@implementation CD3DGSGaussianPreviewView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor colorWithRed:0x18 / 255.0 green:0x22 / 255.0 blue:0x31 / 255.0 alpha:1.0];
        self.layer.cornerRadius = CD3DGSCardRadius;
        self.clipsToBounds = YES;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) {
        return;
    }

    UIColor *floorColor = [UIColor colorWithRed:0x2C / 255.0 green:0x3B / 255.0 blue:0x4C / 255.0 alpha:1.0];
    UIColor *wallColor = [UIColor colorWithRed:0x36 / 255.0 green:0x4E / 255.0 blue:0x68 / 255.0 alpha:1.0];
    UIColor *lineColor = [[UIColor whiteColor] colorWithAlphaComponent:0.20];
    UIColor *pointBlue = [UIColor colorWithRed:0x8A / 255.0 green:0xB5 / 255.0 blue:0xFF / 255.0 alpha:0.92];
    UIColor *pointGreen = [UIColor colorWithRed:0x00 / 255.0 green:0xA6 / 255.0 blue:0x66 / 255.0 alpha:0.72];
    UIColor *pointWarm = [UIColor colorWithRed:0xFA / 255.0 green:0xA2 / 255.0 blue:0x41 / 255.0 alpha:0.70];

    CGRect roomRect = CGRectInset(rect, 24, 24);
    UIBezierPath *floorPath = [UIBezierPath bezierPath];
    [floorPath moveToPoint:CGPointMake(CGRectGetMinX(roomRect) + 36, CGRectGetMaxY(roomRect) - 8)];
    [floorPath addLineToPoint:CGPointMake(CGRectGetMaxX(roomRect) - 24, CGRectGetMaxY(roomRect) - 28)];
    [floorPath addLineToPoint:CGPointMake(CGRectGetMaxX(roomRect) - 56, CGRectGetMinY(roomRect) + 54)];
    [floorPath addLineToPoint:CGPointMake(CGRectGetMinX(roomRect) + 8, CGRectGetMinY(roomRect) + 28)];
    [floorPath closePath];
    [floorColor setFill];
    [floorPath fill];

    UIBezierPath *wallPath = [UIBezierPath bezierPath];
    [wallPath moveToPoint:CGPointMake(CGRectGetMinX(roomRect) + 8, CGRectGetMinY(roomRect) + 28)];
    [wallPath addLineToPoint:CGPointMake(CGRectGetMaxX(roomRect) - 56, CGRectGetMinY(roomRect) + 54)];
    [wallPath addLineToPoint:CGPointMake(CGRectGetMaxX(roomRect) - 24, CGRectGetMaxY(roomRect) - 28)];
    [wallPath addLineToPoint:CGPointMake(CGRectGetMaxX(roomRect) - 16, CGRectGetMinY(roomRect) + 16)];
    [wallPath addLineToPoint:CGPointMake(CGRectGetMinX(roomRect) + 18, CGRectGetMinY(roomRect) + 6)];
    [wallPath closePath];
    [wallColor setFill];
    [wallPath fill];

    CGContextSetStrokeColorWithColor(ctx, lineColor.CGColor);
    CGContextSetLineWidth(ctx, 1.0);
    CGContextMoveToPoint(ctx, CGRectGetMinX(roomRect) + 8, CGRectGetMinY(roomRect) + 28);
    CGContextAddLineToPoint(ctx, CGRectGetMinX(roomRect) + 36, CGRectGetMaxY(roomRect) - 8);
    CGContextMoveToPoint(ctx, CGRectGetMaxX(roomRect) - 56, CGRectGetMinY(roomRect) + 54);
    CGContextAddLineToPoint(ctx, CGRectGetMaxX(roomRect) - 24, CGRectGetMaxY(roomRect) - 28);
    CGContextStrokePath(ctx);

    NSArray<UIColor *> *colors = @[pointBlue, pointGreen, pointWarm];
    for (NSInteger i = 0; i < 96; i++) {
        CGFloat xBase = (CGFloat)((i * 37) % 100) / 100.0;
        CGFloat yBase = (CGFloat)((i * 53) % 100) / 100.0;
        CGFloat x = CGRectGetMinX(roomRect) + 20 + xBase * (CGRectGetWidth(roomRect) - 52);
        CGFloat y = CGRectGetMinY(roomRect) + 22 + yBase * (CGRectGetHeight(roomRect) - 42);
        CGFloat radius = 1.3 + (CGFloat)(i % 4) * 0.35;
        UIColor *dotColor = colors[i % colors.count];
        [dotColor setFill];
        UIBezierPath *dot = [UIBezierPath bezierPathWithOvalInRect:CGRectMake(x, y, radius, radius)];
        [dot fill];
    }
}

@end

@interface CD3DGSTrainingResultViewController ()

@property (nonatomic, strong) CD3DGSTrainingResultSummary *summary;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIStackView *contentStack;
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, assign) BOOL singleRoomDemoFlow;

@end

@implementation CD3DGSTrainingResultViewController

- (instancetype)initWithSummary:(CD3DGSTrainingResultSummary *)summary {
    return [self initWithSummary:summary singleRoomDemoFlow:NO];
}

- (instancetype)initWithSummary:(CD3DGSTrainingResultSummary *)summary singleRoomDemoFlow:(BOOL)singleRoomDemoFlow {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _summary = summary;
        _singleRoomDemoFlow = singleRoomDemoFlow;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = self.summary.title;
    self.view.backgroundColor = [self colorWithHex:0xF5F5F5];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"反馈"
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(feedbackTapped)];

    [self setupScrollContent];
    [self setupBottomBar];
    [self buildContent];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self applyReadableNavigationBarStyle];
}

- (void)applyReadableNavigationBarStyle {
    [self.navigationController setNavigationBarHidden:NO animated:NO];
    self.navigationController.navigationBar.prefersLargeTitles = NO;
    self.navigationController.navigationBar.tintColor = [self colorWithHex:0x1A66FF];

    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor whiteColor];
        appearance.shadowColor = [self colorWithHex:0xEEEEEE];
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [self colorWithHex:0x222222],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:17.0]
        };
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
        self.navigationController.navigationBar.compactAppearance = appearance;
    } else {
        self.navigationController.navigationBar.barTintColor = [UIColor whiteColor];
        self.navigationController.navigationBar.titleTextAttributes = @{
            NSForegroundColorAttributeName: [self colorWithHex:0x222222],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:17.0]
        };
    }
}

- (void)setupScrollContent {
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    self.scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    self.contentStack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.contentStack.translatesAutoresizingMaskIntoConstraints = NO;
    self.contentStack.axis = UILayoutConstraintAxisVertical;
    self.contentStack.spacing = 12.0;
    [self.scrollView addSubview:self.contentStack];

    [NSLayoutConstraint activateConstraints:@[
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.contentStack.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor constant:12.0],
        [self.contentStack.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor constant:CD3DGSScreenMargin],
        [self.contentStack.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor constant:-CD3DGSScreenMargin],
        [self.contentStack.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor constant:-116.0]
    ]];
}

- (void)setupBottomBar {
    self.bottomBar = [[UIView alloc] initWithFrame:CGRectZero];
    self.bottomBar.translatesAutoresizingMaskIntoConstraints = NO;
    self.bottomBar.backgroundColor = [UIColor whiteColor];
    [self.view addSubview:self.bottomBar];

    UIView *topLine = [[UIView alloc] initWithFrame:CGRectZero];
    topLine.translatesAutoresizingMaskIntoConstraints = NO;
    topLine.backgroundColor = [self colorWithHex:0xEEEEEE];
    [self.bottomBar addSubview:topLine];

    UIButton *backButton = [self outlineButtonWithTitle:@"返回结果列表"];
    [backButton addTarget:self action:@selector(backToListTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:backButton];

    UIButton *submitButton = [self primaryButtonWithTitle:@"确认提交交付"];
    [submitButton addTarget:self action:@selector(submitTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.bottomBar addSubview:submitButton];

    [NSLayoutConstraint activateConstraints:@[
        [self.bottomBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.bottomBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.bottomBar.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.bottomBar.heightAnchor constraintEqualToConstant:92.0],
        [topLine.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor],
        [topLine.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor],
        [topLine.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor],
        [topLine.heightAnchor constraintEqualToConstant:1.0],
        [backButton.leadingAnchor constraintEqualToAnchor:self.bottomBar.leadingAnchor constant:16.0],
        [backButton.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:12.0],
        [backButton.widthAnchor constraintEqualToConstant:116.0],
        [backButton.heightAnchor constraintEqualToConstant:46.0],
        [submitButton.leadingAnchor constraintEqualToAnchor:backButton.trailingAnchor constant:12.0],
        [submitButton.trailingAnchor constraintEqualToAnchor:self.bottomBar.trailingAnchor constant:-16.0],
        [submitButton.topAnchor constraintEqualToAnchor:self.bottomBar.topAnchor constant:12.0],
        [submitButton.heightAnchor constraintEqualToConstant:46.0]
    ]];
}

- (void)buildContent {
    [self.contentStack addArrangedSubview:[self buildStatusCard]];
    [self.contentStack addArrangedSubview:[self buildPreviewCard]];
    [self.contentStack addArrangedSubview:[self buildQualityCard]];
    if (!self.singleRoomDemoFlow) {
        [self.contentStack addArrangedSubview:[self buildRoomResultCard]];
        [self.contentStack addArrangedSubview:[self buildRiskCard]];
    }
}

- (UIView *)buildStatusCard {
    UIView *card = [self cardView];

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = [self colorWithHex:0x00A666];
    [card addSubview:iconView];

    UILabel *titleLabel = [self labelWithText:self.summary.statusTitle font:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] color:[self colorWithHex:0x222222]];
    [card addSubview:titleLabel];

    UILabel *subtitleLabel = [self labelWithText:self.summary.statusSubtitle font:[UIFont systemFontOfSize:12 weight:UIFontWeightRegular] color:[self colorWithHex:0x666666]];
    subtitleLabel.numberOfLines = 2;
    [card addSubview:subtitleLabel];

    UILabel *tagLabel = [self tagLabelWithText:self.summary.deliveryTagText
                                    textColor:[self colorWithHex:0x00A666]
                              backgroundColor:[self colorWithHex:0xEBFFF7]];
    [card addSubview:tagLabel];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [iconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:18.0],
        [iconView.widthAnchor constraintEqualToConstant:28.0],
        [iconView.heightAnchor constraintEqualToConstant:28.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:12.0],
        [titleLabel.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [tagLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [tagLabel.centerYAnchor constraintEqualToAnchor:titleLabel.centerYAnchor],
        [titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:tagLabel.leadingAnchor constant:-8.0],
        [subtitleLabel.leadingAnchor constraintEqualToAnchor:titleLabel.leadingAnchor],
        [subtitleLabel.topAnchor constraintEqualToAnchor:titleLabel.bottomAnchor constant:4.0],
        [subtitleLabel.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [subtitleLabel.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0],
        [tagLabel.heightAnchor constraintEqualToConstant:22.0]
    ]];

    return card;
}

- (UIView *)buildPreviewCard {
    UIView *card = [self cardView];

    CD3DGSGaussianPreviewView *preview = [[CD3DGSGaussianPreviewView alloc] initWithFrame:CGRectZero];
    preview.translatesAutoresizingMaskIntoConstraints = NO;
    [card addSubview:preview];

    UILabel *roomChip = [self overlayChipWithText:(self.singleRoomDemoFlow ? @"示例房间 · 3D预览" : @"客厅 · 3D预览")];
    [preview addSubview:roomChip];

    UILabel *timeChip = [self overlayChipWithText:self.summary.generatedAtText];
    [preview addSubview:timeChip];

    UIButton *previewButton = [self primaryButtonWithTitle:@"查看3D漫游"];
    [previewButton addTarget:self action:@selector(viewTourTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:previewButton];

    UIButton *retrainButton = [self outlineButtonWithTitle:@"重新训练"];
    [retrainButton addTarget:self action:@selector(retrainTapped) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:retrainButton];

    [NSLayoutConstraint activateConstraints:@[
        [preview.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [preview.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [preview.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [preview.heightAnchor constraintEqualToConstant:164.0],
        [roomChip.leadingAnchor constraintEqualToAnchor:preview.leadingAnchor constant:10.0],
        [roomChip.topAnchor constraintEqualToAnchor:preview.topAnchor constant:10.0],
        [roomChip.heightAnchor constraintEqualToConstant:24.0],
        [timeChip.trailingAnchor constraintEqualToAnchor:preview.trailingAnchor constant:-10.0],
        [timeChip.topAnchor constraintEqualToAnchor:preview.topAnchor constant:10.0],
        [timeChip.heightAnchor constraintEqualToConstant:24.0],
        [previewButton.topAnchor constraintEqualToAnchor:preview.bottomAnchor constant:12.0],
        [previewButton.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [previewButton.heightAnchor constraintEqualToConstant:40.0],
        [retrainButton.leadingAnchor constraintEqualToAnchor:previewButton.trailingAnchor constant:12.0],
        [retrainButton.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [retrainButton.topAnchor constraintEqualToAnchor:previewButton.topAnchor],
        [retrainButton.widthAnchor constraintEqualToConstant:104.0],
        [retrainButton.heightAnchor constraintEqualToAnchor:previewButton.heightAnchor],
        [previewButton.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-16.0]
    ]];

    return card;
}

- (UIView *)buildQualityCard {
    UIView *card = [self cardView];

    UIStackView *header = [[UIStackView alloc] initWithFrame:CGRectZero];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    header.axis = UILayoutConstraintAxisHorizontal;
    header.alignment = UIStackViewAlignmentCenter;
    [card addSubview:header];

    UILabel *titleLabel = [self labelWithText:@"质量概览" font:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] color:[self colorWithHex:0x222222]];
    [header addArrangedSubview:titleLabel];

    UIView *spacer = [[UIView alloc] initWithFrame:CGRectZero];
    [header addArrangedSubview:spacer];

    UILabel *passTag = [self tagLabelWithText:@"通过" textColor:[self colorWithHex:0x00A666] backgroundColor:[self colorWithHex:0xEBFFF7]];
    [header addArrangedSubview:passTag];

    UIStackView *metrics = [[UIStackView alloc] initWithFrame:CGRectZero];
    metrics.translatesAutoresizingMaskIntoConstraints = NO;
    metrics.axis = UILayoutConstraintAxisHorizontal;
    metrics.distribution = UIStackViewDistributionFillEqually;
    metrics.alignment = UIStackViewAlignmentFill;
    [card addSubview:metrics];

    [metrics addArrangedSubview:[self metricViewWithTitle:@"综合评分" value:[NSString stringWithFormat:@"%ld", (long)self.summary.score]]];
    [metrics addArrangedSubview:[self metricViewWithTitle:@"覆盖完整度" value:[NSString stringWithFormat:@"%ld%%", (long)self.summary.coveragePercent]]];
    [metrics addArrangedSubview:[self metricViewWithTitle:@"清晰帧占比" value:[NSString stringWithFormat:@"%ld%%", (long)self.summary.clearFramePercent]]];

    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [header.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [header.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [passTag.heightAnchor constraintEqualToConstant:22.0],
        [metrics.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:12.0],
        [metrics.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:8.0],
        [metrics.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-8.0],
        [metrics.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0]
    ]];

    return card;
}

- (UIView *)buildRoomResultCard {
    UIView *card = [self cardView];

    UIStackView *stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 0;
    [card addSubview:stack];

    UIView *header = [[UIView alloc] initWithFrame:CGRectZero];
    [stack addArrangedSubview:header];

    UILabel *titleLabel = [self labelWithText:@"分间结果" font:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] color:[self colorWithHex:0x222222]];
    [header addSubview:titleLabel];

    UIButton *allButton = [UIButton buttonWithType:UIButtonTypeSystem];
    allButton.translatesAutoresizingMaskIntoConstraints = NO;
    [allButton setTitle:@"查看全部" forState:UIControlStateNormal];
    [allButton setTitleColor:[self colorWithHex:0x1A66FF] forState:UIControlStateNormal];
    allButton.titleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightMedium];
    [allButton addTarget:self action:@selector(viewAllRoomsTapped) forControlEvents:UIControlEventTouchUpInside];
    [header addSubview:allButton];

    [NSLayoutConstraint activateConstraints:@[
        [header.heightAnchor constraintEqualToConstant:40.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:header.leadingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:header.centerYAnchor],
        [allButton.trailingAnchor constraintEqualToAnchor:header.trailingAnchor],
        [allButton.centerYAnchor constraintEqualToAnchor:header.centerYAnchor]
    ]];

    for (NSInteger index = 0; index < self.summary.roomResults.count; index++) {
        CD3DGSTrainingRoomResult *roomResult = self.summary.roomResults[index];
        [stack addArrangedSubview:[self roomRowWithResult:roomResult showsDivider:index > 0]];
    }

    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:8.0],
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:16.0],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-16.0],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-8.0]
    ]];

    return card;
}

- (UIView *)buildRiskCard {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [self colorWithHex:0xFFF3E0];
    card.layer.cornerRadius = CD3DGSCardRadius;

    UIImageView *iconView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"exclamationmark.triangle.fill"]];
    iconView.translatesAutoresizingMaskIntoConstraints = NO;
    iconView.tintColor = [self colorWithHex:0xFAA241];
    [card addSubview:iconView];

    UILabel *label = [self labelWithText:self.summary.riskText font:[UIFont systemFontOfSize:13 weight:UIFontWeightRegular] color:[self colorWithHex:0x666666]];
    label.numberOfLines = 0;
    [card addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [iconView.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14.0],
        [iconView.topAnchor constraintEqualToAnchor:card.topAnchor constant:16.0],
        [iconView.widthAnchor constraintEqualToConstant:18.0],
        [iconView.heightAnchor constraintEqualToConstant:18.0],
        [label.leadingAnchor constraintEqualToAnchor:iconView.trailingAnchor constant:10.0],
        [label.topAnchor constraintEqualToAnchor:card.topAnchor constant:14.0],
        [label.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14.0],
        [label.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-14.0]
    ]];

    return card;
}

- (UIView *)metricViewWithTitle:(NSString *)title value:(NSString *)value {
    UIView *view = [[UIView alloc] initWithFrame:CGRectZero];

    UILabel *valueLabel = [self labelWithText:value font:[UIFont monospacedDigitSystemFontOfSize:24 weight:UIFontWeightSemibold] color:[self colorWithHex:0x222222]];
    valueLabel.textAlignment = NSTextAlignmentCenter;
    [view addSubview:valueLabel];

    UILabel *titleLabel = [self labelWithText:title font:[UIFont systemFontOfSize:12 weight:UIFontWeightRegular] color:[self colorWithHex:0x666666]];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [view addSubview:titleLabel];

    [NSLayoutConstraint activateConstraints:@[
        [valueLabel.topAnchor constraintEqualToAnchor:view.topAnchor],
        [valueLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [valueLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [titleLabel.topAnchor constraintEqualToAnchor:valueLabel.bottomAnchor constant:4.0],
        [titleLabel.leadingAnchor constraintEqualToAnchor:view.leadingAnchor],
        [titleLabel.trailingAnchor constraintEqualToAnchor:view.trailingAnchor],
        [titleLabel.bottomAnchor constraintEqualToAnchor:view.bottomAnchor]
    ]];

    return view;
}

- (UIView *)roomRowWithResult:(CD3DGSTrainingRoomResult *)roomResult showsDivider:(BOOL)showsDivider {
    UIView *row = [[UIView alloc] initWithFrame:CGRectZero];

    if (showsDivider) {
        UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
        line.translatesAutoresizingMaskIntoConstraints = NO;
        line.backgroundColor = [self colorWithHex:0xEEEEEE];
        [row addSubview:line];
        [NSLayoutConstraint activateConstraints:@[
            [line.topAnchor constraintEqualToAnchor:row.topAnchor],
            [line.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
            [line.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
            [line.heightAnchor constraintEqualToConstant:1.0]
        ]];
    }

    UILabel *nameLabel = [self labelWithText:roomResult.roomName font:[UIFont systemFontOfSize:15 weight:UIFontWeightMedium] color:[self colorWithHex:0x222222]];
    [row addSubview:nameLabel];

    UILabel *coverageLabel = [self labelWithText:roomResult.coverageText font:[UIFont systemFontOfSize:12 weight:UIFontWeightRegular] color:[self colorWithHex:0x666666]];
    [row addSubview:coverageLabel];

    BOOL passed = roomResult.status == CD3DGSTrainingRoomResultStatusPassed;
    UIColor *tagTextColor = passed ? [self colorWithHex:0x00A666] : [self colorWithHex:0xFAA241];
    UIColor *tagBgColor = passed ? [self colorWithHex:0xEBFFF7] : [self colorWithHex:0xFFF3E0];
    UILabel *tagLabel = [self tagLabelWithText:roomResult.statusText textColor:tagTextColor backgroundColor:tagBgColor];
    [row addSubview:tagLabel];

    [NSLayoutConstraint activateConstraints:@[
        [row.heightAnchor constraintEqualToConstant:48.0],
        [nameLabel.leadingAnchor constraintEqualToAnchor:row.leadingAnchor],
        [nameLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [coverageLabel.trailingAnchor constraintEqualToAnchor:tagLabel.leadingAnchor constant:-10.0],
        [coverageLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [tagLabel.trailingAnchor constraintEqualToAnchor:row.trailingAnchor],
        [tagLabel.centerYAnchor constraintEqualToAnchor:row.centerYAnchor],
        [tagLabel.heightAnchor constraintEqualToConstant:22.0]
    ]];

    return row;
}

- (UIView *)cardView {
    UIView *card = [[UIView alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor whiteColor];
    card.layer.cornerRadius = CD3DGSCardRadius;
    return card;
}

- (UILabel *)labelWithText:(NSString *)text font:(UIFont *)font color:(UIColor *)color {
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = text;
    label.font = font;
    label.textColor = color;
    return label;
}

- (UILabel *)tagLabelWithText:(NSString *)text textColor:(UIColor *)textColor backgroundColor:(UIColor *)backgroundColor {
    UILabel *label = [self labelWithText:text font:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium] color:textColor];
    label.backgroundColor = backgroundColor;
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 2.0;
    label.clipsToBounds = YES;
    [label.widthAnchor constraintGreaterThanOrEqualToConstant:48.0].active = YES;
    return label;
}

- (UILabel *)overlayChipWithText:(NSString *)text {
    UILabel *label = [self labelWithText:text font:[UIFont systemFontOfSize:11 weight:UIFontWeightMedium] color:[UIColor whiteColor]];
    label.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.36];
    label.textAlignment = NSTextAlignmentCenter;
    label.layer.cornerRadius = 12.0;
    label.clipsToBounds = YES;
    [label.widthAnchor constraintGreaterThanOrEqualToConstant:92.0].active = YES;
    return label;
}

- (UIButton *)primaryButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [self colorWithHex:0x1A66FF];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 4.0;
    return button;
}

- (UIButton *)outlineButtonWithTitle:(NSString *)title {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.backgroundColor = [UIColor whiteColor];
    [button setTitle:title forState:UIControlStateNormal];
    [button setTitleColor:[self colorWithHex:0x1A66FF] forState:UIControlStateNormal];
    button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    button.layer.cornerRadius = 4.0;
    button.layer.borderWidth = 1.0;
    button.layer.borderColor = [self colorWithHex:0x1A66FF].CGColor;
    return button;
}

- (UIColor *)colorWithHex:(NSUInteger)hex {
    return [UIColor colorWithRed:((hex >> 16) & 0xFF) / 255.0
                           green:((hex >> 8) & 0xFF) / 255.0
                            blue:(hex & 0xFF) / 255.0
                           alpha:1.0];
}

- (void)feedbackTapped {
    [self presentMessageWithTitle:@"反馈" message:@"已记录当前训练结果反馈入口，后续可接入问题上报。"];
}

- (void)viewTourTapped {
    CD3DGSRoomTourViewController *tourViewController = [[CD3DGSRoomTourViewController alloc] initWithRoomName:@"客厅"];
    tourViewController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:tourViewController animated:YES];
}

- (void)retrainTapped {
    [self presentMessageWithTitle:@"重新训练" message:@"已进入重新训练确认流程，后续可接入训练任务接口。"];
}

- (void)viewAllRoomsTapped {
    [self presentMessageWithTitle:@"分间结果" message:@"这里将展示全部房间的训练明细和复核项。"];
}

- (void)backToListTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)submitTapped {
    [self presentMessageWithTitle:@"提交交付" message:@"训练结果已确认，后续可接入正式交付提交接口。"];
}

- (void)presentMessageWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
