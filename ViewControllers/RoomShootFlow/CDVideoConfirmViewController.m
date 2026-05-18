#import "CDVideoConfirmViewController.h"
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
    // 点击房间卡片，后续可以跳转到详情页
    NSLog(@"点击了房间: %@", self.roomList[indexPath.row].roomName);
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
