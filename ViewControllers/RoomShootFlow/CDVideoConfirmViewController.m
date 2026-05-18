#import "CDVideoConfirmViewController.h"
#import <WebKit/WebKit.h>

#pragma mark - Data Models

@interface CDRoomItem : NSObject
@property (nonatomic, copy) NSString *roomId;
@property (nonatomic, copy) NSString *roomName;
@property (nonatomic, copy) NSString *totalSteps;
@property (nonatomic, copy) NSString *completedSteps;
@property (nonatomic, assign) NSInteger auditStatus; // 0:待拍摄 1:审核中 2:通过 3:未通过
@property (nonatomic, copy) NSString *auditReason;
@end

@implementation CDRoomItem
@end

#pragma mark - Progress Donut View

@interface CDProgressDonutView : UIView
@property (nonatomic, assign) CGFloat progress; // 0.0 ~ 1.0
@property (nonatomic, strong) UIColor *trackColor;
@property (nonatomic, strong) UIColor *progressColor;
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

    NSString *percentText = [NSString stringWithFormat:@"%.0f%%", self.progress * 100];
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

#pragma mark - Room Card Cell

@interface CDRoomCardCell : UITableViewCell
@property (nonatomic, strong) UIView *cardView;
@property (nonatomic, strong) UIView *thumbView;
@property (nonatomic, strong) UILabel *stepBadge;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIView *statusTag;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UILabel *metaLabel;
@property (nonatomic, strong) UIView *auditBadge;
@property (nonatomic, strong) UILabel *auditIconLabel;
@property (nonatomic, strong) UILabel *auditStatusLabel;
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

    self.statusTag = [[UIView alloc] init];
    self.statusTag.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusTag.layer.cornerRadius = 2;
    self.statusTag.hidden = YES;
    [self.cardView addSubview:self.statusTag];

    self.statusLabel = [[UILabel alloc] init];
    self.statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.statusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [self.statusTag addSubview:self.statusLabel];
    [NSLayoutConstraint activateConstraints:@[
        [self.statusLabel.leadingAnchor constraintEqualToAnchor:self.statusTag.leadingAnchor constant:6],
        [self.statusLabel.trailingAnchor constraintEqualToAnchor:self.statusTag.trailingAnchor constant:-6],
        [self.statusLabel.topAnchor constraintEqualToAnchor:self.statusTag.topAnchor constant:0],
        [self.statusLabel.bottomAnchor constraintEqualToAnchor:self.statusTag.bottomAnchor constant:0],
        [self.statusTag.heightAnchor constraintEqualToConstant:18]
    ]];

    self.metaLabel = [[UILabel alloc] init];
    self.metaLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.metaLabel.font = [UIFont systemFontOfSize:12];
    self.metaLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    [self.cardView addSubview:self.metaLabel];

    // 审核区域
    self.auditBadge = [[UIView alloc] init];
    self.auditBadge.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditBadge.layer.cornerRadius = 10;
    [self.cardView addSubview:self.auditBadge];

    self.auditIconLabel = [[UILabel alloc] init];
    self.auditIconLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditIconLabel.font = [UIFont systemFontOfSize:10 weight:UIFontWeightBold];
    [self.auditBadge addSubview:self.auditIconLabel];

    self.auditStatusLabel = [[UILabel alloc] init];
    self.auditStatusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditStatusLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightBold];
    [self.auditBadge addSubview:self.auditStatusLabel];

    self.auditReasonLabel = [[UILabel alloc] init];
    self.auditReasonLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditReasonLabel.font = [UIFont systemFontOfSize:11];
    self.auditReasonLabel.textColor = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    self.auditReasonLabel.hidden = YES;
    [self.cardView addSubview:self.auditReasonLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.auditIconLabel.leadingAnchor constraintEqualToAnchor:self.auditBadge.leadingAnchor constant:8],
        [self.auditIconLabel.centerYAnchor constraintEqualToAnchor:self.auditBadge.centerYAnchor],
        [self.auditIconLabel.widthAnchor constraintEqualToConstant:14],
        [self.auditIconLabel.heightAnchor constraintEqualToConstant:14],

        [self.auditStatusLabel.leadingAnchor constraintEqualToAnchor:self.auditIconLabel.trailingAnchor constant:2],
        [self.auditStatusLabel.trailingAnchor constraintEqualToAnchor:self.auditBadge.trailingAnchor constant:-8],
        [self.auditStatusLabel.centerYAnchor constraintEqualToAnchor:self.auditBadge.centerYAnchor]
    ]];

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
        [self.titleLabel.trailingAnchor constraintLessThanOrEqualToAnchor:self.statusTag.leadingAnchor constant:-6],

        [self.statusTag.trailingAnchor constraintLessThanOrEqualToAnchor:self.chevronIcon.leadingAnchor constant:-8],
        [self.statusTag.centerYAnchor constraintEqualToAnchor:self.titleLabel.centerYAnchor],

        [self.metaLabel.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.metaLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:4],
        [self.metaLabel.trailingAnchor constraintEqualToAnchor:self.chevronIcon.leadingAnchor constant:-8],

        [self.auditBadge.leadingAnchor constraintEqualToAnchor:self.titleLabel.leadingAnchor],
        [self.auditBadge.topAnchor constraintEqualToAnchor:self.metaLabel.bottomAnchor constant:8],
        [self.auditBadge.heightAnchor constraintEqualToConstant:20],

        [self.auditReasonLabel.leadingAnchor constraintEqualToAnchor:self.auditBadge.trailingAnchor constant:6],
        [self.auditReasonLabel.centerYAnchor constraintEqualToAnchor:self.auditBadge.centerYAnchor],
        [self.auditReasonLabel.trailingAnchor constraintEqualToAnchor:self.chevronIcon.leadingAnchor constant:-8]
    ]];
}

- (void)configWithRoom:(CDRoomItem *)room {
    self.titleLabel.text = room.roomName;

    NSString *stepText = [NSString stringWithFormat:@"%@/%@", room.completedSteps, room.totalSteps];
    self.stepBadge.text = [NSString stringWithFormat:@" %@ ", stepText];

    self.metaLabel.text = [NSString stringWithFormat:@"%@ 个步骤，已拍摄 %@ 个", room.totalSteps, room.completedSteps];

    // 状态标签
    if (room.auditStatus == 0) {
        self.statusTag.hidden = NO;
        self.statusTag.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
        self.statusLabel.text = @"待处理";
        self.statusLabel.textColor = [UIColor colorWithRed:153/255.0 green:153/255.0 blue:153/255.0 alpha:1.0];
    } else if (room.auditStatus == 1) {
        self.statusTag.hidden = NO;
        self.statusTag.backgroundColor = [UIColor colorWithRed:224/255.0 green:237/255.0 blue:255/255.0 alpha:1.0];
        self.statusLabel.text = @"进行中";
        self.statusLabel.textColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    } else {
        self.statusTag.hidden = YES;
    }

    // 审核标签
    self.auditReasonLabel.text = @"";
    self.auditReasonLabel.hidden = YES;
    self.auditBadge.layer.borderWidth = 0;
    self.auditBadge.layer.borderColor = nil;

    switch (room.auditStatus) {
        case 0: { // 待拍摄
            self.auditBadge.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
            self.auditBadge.layer.borderWidth = 1;
            self.auditBadge.layer.borderColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0].CGColor;
            self.auditIconLabel.text = @"⏱";
            self.auditIconLabel.textColor = [UIColor colorWithRed:153/255.0 green:153/255.0 blue:153/255.0 alpha:1.0];
            self.auditStatusLabel.text = @"待拍摄";
            self.auditStatusLabel.textColor = [UIColor colorWithRed:153/255.0 green:153/255.0 blue:153/255.0 alpha:1.0];
            break;
        }
        case 1: { // 审核中
            self.auditBadge.backgroundColor = [UIColor colorWithRed:232/255.0 green:240/255.0 blue:255/255.0 alpha:1.0];
            self.auditIconLabel.text = @"⏳";
            self.auditIconLabel.textColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
            self.auditStatusLabel.text = @"审核中";
            self.auditStatusLabel.textColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
            break;
        }
        case 2: { // 通过
            self.auditBadge.backgroundColor = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
            self.auditIconLabel.text = @"✓";
            self.auditIconLabel.textColor = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
            self.auditStatusLabel.text = @"已通过";
            self.auditStatusLabel.textColor = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
            break;
        }
        case 3: { // 未通过
            self.auditBadge.backgroundColor = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
            self.auditIconLabel.text = @"✗";
            self.auditIconLabel.textColor = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
            self.auditStatusLabel.text = @"未通过";
            self.auditStatusLabel.textColor = [UIColor colorWithRed:232/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
            self.auditReasonLabel.text = room.auditReason;
            self.auditReasonLabel.hidden = NO;
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

// 审核 Banner
@property (nonatomic, strong) UIView *auditBanner;
@property (nonatomic, strong) UILabel *auditBannerIcon;
@property (nonatomic, strong) UILabel *auditTitleLabel;
@property (nonatomic, strong) UILabel *auditDescLabel;

// 房间列表
@property (nonatomic, strong) UILabel *sectionTitle;
@property (nonatomic, strong) UILabel *roomCountLabel;
@property (nonatomic, strong) UITableView *roomTableView;
@property (nonatomic, strong) NSLayoutConstraint *roomTableHeightConstraint;
@property (nonatomic, strong) NSMutableArray<CDRoomItem *> *roomList;

// 底部提交
@property (nonatomic, strong) UIView *bottomBar;
@property (nonatomic, strong) UIButton *submitBtn;
@property (nonatomic, strong) NSLayoutConstraint *bottomBarHeightConstraint;

// 数据
@property (nonatomic, assign) NSInteger totalRooms;
@property (nonatomic, assign) NSInteger passedRooms;
@property (nonatomic, assign) CGFloat overallProgress;
@property (nonatomic, copy) NSString *globalAuditReason;

@end

@implementation CDVideoConfirmViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
    self.title = @"分间采集";

    [self setupNavigationBar];
    [self setupMockData];
    [self setupViews];
    [self updateAuditBanner];
    [self updateRoomTableHeight];
    [self.roomTableView reloadData];
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
    self.totalRooms = 5;
    self.passedRooms = 3;
    self.overallProgress = 0.6; // 60%
    self.globalAuditReason = @"主卧光线不足 · 次卧画面抖动";

    self.roomList = [NSMutableArray array];

    CDRoomItem *room1 = [[CDRoomItem alloc] init];
    room1.roomId = @"1";
    room1.roomName = @"主卧";
    room1.totalSteps = @"5";
    room1.completedSteps = @"5";
    room1.auditStatus = 3; // 未通过
    room1.auditReason = @"光线严重不足";
    [self.roomList addObject:room1];

    CDRoomItem *room2 = [[CDRoomItem alloc] init];
    room2.roomId = @"2";
    room2.roomName = @"次卧";
    room2.totalSteps = @"5";
    room2.completedSteps = @"5";
    room2.auditStatus = 3; // 未通过
    room2.auditReason = @"画面剧烈抖动";
    [self.roomList addObject:room2];

    CDRoomItem *room3 = [[CDRoomItem alloc] init];
    room3.roomId = @"3";
    room3.roomName = @"客厅";
    room3.totalSteps = @"6";
    room3.completedSteps = @"3";
    room3.auditStatus = 1; // 审核中
    room3.auditReason = @"";
    [self.roomList addObject:room3];

    CDRoomItem *room4 = [[CDRoomItem alloc] init];
    room4.roomId = @"4";
    room4.roomName = @"厨房";
    room4.totalSteps = @"6";
    room4.completedSteps = @"0";
    room4.auditStatus = 0; // 待拍摄
    room4.auditReason = @"";
    [self.roomList addObject:room4];

    CDRoomItem *room5 = [[CDRoomItem alloc] init];
    room5.roomId = @"5";
    room5.roomName = @"卫生间";
    room5.totalSteps = @"6";
    room5.completedSteps = @"0";
    room5.auditStatus = 0; // 待拍摄
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
    [self setupAuditBanner];
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
        [self.floorplanContainer.heightAnchor constraintEqualToConstant:242] // 220 + 22(进度卡片溢出)
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
    self.progressDonut.progress = self.overallProgress;
    [self.progressCard addSubview:self.progressDonut];
    [NSLayoutConstraint activateConstraints:@[
        [self.progressDonut.centerXAnchor constraintEqualToAnchor:self.progressCard.centerXAnchor],
        [self.progressDonut.centerYAnchor constraintEqualToAnchor:self.progressCard.centerYAnchor],
        [self.progressDonut.widthAnchor constraintEqualToConstant:48],
        [self.progressDonut.heightAnchor constraintEqualToConstant:48]
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

- (void)setupAuditBanner {
    self.auditBanner = [[UIView alloc] initWithFrame:CGRectZero];
    self.auditBanner.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditBanner.backgroundColor = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
    self.auditBanner.layer.cornerRadius = 8;
    self.auditBanner.layer.borderWidth = 1;
    self.auditBanner.layer.borderColor = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:0.3].CGColor;
    [self.contentView addSubview:self.auditBanner];
    [NSLayoutConstraint activateConstraints:@[
        [self.auditBanner.topAnchor constraintEqualToAnchor:self.floorplanContainer.bottomAnchor constant:16],
        [self.auditBanner.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.auditBanner.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.auditBanner.heightAnchor constraintEqualToConstant:48]
    ]];

    UIView *innerView = [[UIView alloc] initWithFrame:CGRectZero];
    innerView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.auditBanner addSubview:innerView];
    [NSLayoutConstraint activateConstraints:@[
        [innerView.leadingAnchor constraintEqualToAnchor:self.auditBanner.leadingAnchor constant:12],
        [innerView.trailingAnchor constraintEqualToAnchor:self.auditBanner.trailingAnchor constant:-12],
        [innerView.topAnchor constraintEqualToAnchor:self.auditBanner.topAnchor constant:10],
        [innerView.bottomAnchor constraintEqualToAnchor:self.auditBanner.bottomAnchor constant:-10]
    ]];

    self.auditBannerIcon = [[UILabel alloc] initWithFrame:CGRectZero];
    self.auditBannerIcon.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditBannerIcon.text = @"⚠";
    self.auditBannerIcon.font = [UIFont systemFontOfSize:14];
    self.auditBannerIcon.textColor = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:1.0];
    [innerView addSubview:self.auditBannerIcon];

    self.auditTitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.auditTitleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditTitleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.auditTitleLabel.textColor = [UIColor colorWithRed:204/255.0 green:122/255.0 blue:0/255.0 alpha:1.0];
    [innerView addSubview:self.auditTitleLabel];

    self.auditDescLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.auditDescLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.auditDescLabel.font = [UIFont systemFontOfSize:12];
    self.auditDescLabel.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    [innerView addSubview:self.auditDescLabel];

    [NSLayoutConstraint activateConstraints:@[
        [self.auditBannerIcon.leadingAnchor constraintEqualToAnchor:innerView.leadingAnchor],
        [self.auditBannerIcon.centerYAnchor constraintEqualToAnchor:innerView.centerYAnchor],
        [self.auditBannerIcon.widthAnchor constraintEqualToConstant:20],
        [self.auditBannerIcon.heightAnchor constraintEqualToConstant:20],

        [self.auditTitleLabel.leadingAnchor constraintEqualToAnchor:self.auditBannerIcon.trailingAnchor constant:10],
        [self.auditTitleLabel.topAnchor constraintEqualToAnchor:innerView.topAnchor constant:0],
        [self.auditTitleLabel.trailingAnchor constraintEqualToAnchor:innerView.trailingAnchor],

        [self.auditDescLabel.leadingAnchor constraintEqualToAnchor:self.auditTitleLabel.leadingAnchor],
        [self.auditDescLabel.bottomAnchor constraintEqualToAnchor:innerView.bottomAnchor constant:0],
        [self.auditDescLabel.trailingAnchor constraintEqualToAnchor:innerView.trailingAnchor]
    ]];
}

- (void)setupSectionTitle {
    UIView *sectionHeader = [[UIView alloc] initWithFrame:CGRectZero];
    sectionHeader.translatesAutoresizingMaskIntoConstraints = NO;
    [self.contentView addSubview:sectionHeader];

    [NSLayoutConstraint activateConstraints:@[
        [sectionHeader.topAnchor constraintEqualToAnchor:self.auditBanner.bottomAnchor constant:12],
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

    NSLayoutYAxisAnchor *topAnchor = sectionHeader ? sectionHeader.bottomAnchor : self.auditBanner.bottomAnchor;
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

#pragma mark - StatusBar

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (void)updateAuditBanner {
    NSInteger failCount = 0;
    for (CDRoomItem *room in self.roomList) {
        if (room.auditStatus == 3) failCount++;
    }

    if (failCount == 0) {
        self.auditBanner.backgroundColor = [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0];
        self.auditBanner.layer.borderColor = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:0.2].CGColor;
        self.auditBannerIcon.text = @"✓";
        self.auditBannerIcon.textColor = [UIColor colorWithRed:0/255.0 green:166/255.0 blue:102/255.0 alpha:1.0];
        self.auditTitleLabel.text = [NSString stringWithFormat:@"%ld/%ld 房间检测通过", (long)self.roomList.count, (long)self.roomList.count];
        self.auditTitleLabel.textColor = [UIColor colorWithRed:0/255.0 green:122/255.0 blue:74/255.0 alpha:1.0];
        self.auditDescLabel.text = @"所有房间审核通过，可以提交";
        self.submitBtn.enabled = YES;
        self.submitBtn.backgroundColor = [UIColor colorWithRed:26/255.0 green:102/255.0 blue:255/255.0 alpha:1.0];
    } else {
        self.auditBanner.backgroundColor = [UIColor colorWithRed:255/255.0 green:240/255.0 blue:240/255.0 alpha:1.0];
        self.auditBanner.layer.borderColor = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:0.3].CGColor;
        self.auditBannerIcon.text = @"⚠";
        self.auditBannerIcon.textColor = [UIColor colorWithRed:250/255.0 green:162/255.0 blue:65/255.0 alpha:1.0];
        self.auditTitleLabel.text = [NSString stringWithFormat:@"%ld/%ld 房间检测未通过", (long)failCount, (long)self.roomList.count];
        self.auditTitleLabel.textColor = [UIColor colorWithRed:204/255.0 green:122/255.0 blue:0/255.0 alpha:1.0];
        self.auditDescLabel.text = self.globalAuditReason;
        self.submitBtn.enabled = NO;
        self.submitBtn.backgroundColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
    }
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
