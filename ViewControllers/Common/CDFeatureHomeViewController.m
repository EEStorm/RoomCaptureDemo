#import "CDFeatureHomeViewController.h"

@interface CDFeatureHomeViewController ()

@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, copy, nullable) NSString *buttonTitle;
@property (nonatomic, copy, nullable) CDDestinationBuilder destinationBuilder;
@property (nonatomic, copy, nullable) NSArray<CDFeatureHomeEntry *> *entries;
@property (nonatomic, strong) UIButton *enterButton;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UIStackView *stack;

@end

@implementation CDFeatureHomeEntry

+ (instancetype)entryWithTitle:(NSString *)title
                      subtitle:(NSString *)subtitle
                         style:(CDFeatureHomeEntryStyle)style
                       enabled:(BOOL)enabled
                         badge:(NSString *)badge
           destinationBuilder:(CDDestinationBuilder)destinationBuilder {
    CDFeatureHomeEntry *entry = [[CDFeatureHomeEntry alloc] init];
    entry.title = title ?: @"";
    entry.subtitle = subtitle ?: @"";
    entry.style = style;
    entry.enabled = enabled;
    entry.badge = badge;
    entry.destinationBuilder = [destinationBuilder copy];
    return entry;
}

@end

@implementation CDFeatureHomeViewController

- (instancetype)initWithTitle:(NSString *)title
                  buttonTitle:(NSString *)buttonTitle
           destinationBuilder:(CDDestinationBuilder)destinationBuilder {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _pageTitle = [title copy];
        _buttonTitle = [buttonTitle copy];
        _destinationBuilder = [destinationBuilder copy];
        self.title = title;
        self.tabBarItem.title = title;
    }
    return self;
}

- (instancetype)initWithTitle:(NSString *)title entries:(NSArray<CDFeatureHomeEntry *> *)entries {
    self = [super initWithNibName:nil bundle:nil];
    if (self) {
        _pageTitle = [title copy];
        _entries = [entries copy];
        self.title = title;
        self.tabBarItem.title = title;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    if (self.entries.count > 0) {
        self.view.backgroundColor = [UIColor colorWithRed:245/255.0 green:245/255.0 blue:245/255.0 alpha:1.0];
        [self setupEntryList];
        return;
    }

    self.view.backgroundColor = [UIColor systemBackgroundColor];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.text = [NSString stringWithFormat:@"%@首页", self.pageTitle];
    self.subtitleLabel.font = [UIFont boldSystemFontOfSize:28];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.subtitleLabel];

    self.enterButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.enterButton setTitle:self.buttonTitle forState:UIControlStateNormal];
    self.enterButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.enterButton.backgroundColor = [UIColor systemBlueColor];
    [self.enterButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.enterButton.layer.cornerRadius = 14;
    [self.enterButton addTarget:self action:@selector(openDestinationPage) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.enterButton];
}

- (void)setupEntryList {
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
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
        [self.scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],

        [self.contentView.topAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.topAnchor],
        [self.contentView.leadingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.leadingAnchor],
        [self.contentView.trailingAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.trailingAnchor],
        [self.contentView.bottomAnchor constraintEqualToAnchor:self.scrollView.contentLayoutGuide.bottomAnchor],
        [self.contentView.widthAnchor constraintEqualToAnchor:self.scrollView.frameLayoutGuide.widthAnchor]
    ]];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectZero];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    title.font = [UIFont systemFontOfSize:22 weight:UIFontWeightHeavy];
    title.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    title.text = self.pageTitle ?: @"";
    [self.contentView addSubview:title];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectZero];
    subtitle.translatesAutoresizingMaskIntoConstraints = NO;
    subtitle.font = [UIFont systemFontOfSize:13];
    subtitle.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    subtitle.numberOfLines = 0;
    subtitle.text = @"请选择入口：顶部为完整流程演示，下方为单独页面展示";
    [self.contentView addSubview:subtitle];

    self.stack = [[UIStackView alloc] initWithFrame:CGRectZero];
    self.stack.translatesAutoresizingMaskIntoConstraints = NO;
    self.stack.axis = UILayoutConstraintAxisVertical;
    self.stack.spacing = 12;
    [self.contentView addSubview:self.stack];

    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:self.contentView.topAnchor constant:16],
        [title.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [title.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [subtitle.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:6],
        [subtitle.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [subtitle.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],

        [self.stack.topAnchor constraintEqualToAnchor:subtitle.bottomAnchor constant:16],
        [self.stack.leadingAnchor constraintEqualToAnchor:self.contentView.leadingAnchor constant:16],
        [self.stack.trailingAnchor constraintEqualToAnchor:self.contentView.trailingAnchor constant:-16],
        [self.stack.bottomAnchor constraintEqualToAnchor:self.contentView.bottomAnchor constant:-16]
    ]];

    for (NSInteger i = 0; i < (NSInteger)self.entries.count; i++) {
        CDFeatureHomeEntry *entry = self.entries[i];
        UIControl *card = [self entryCardForEntry:entry index:i];
        [self.stack addArrangedSubview:card];
        if (i == 0) {
            [self.stack addArrangedSubview:[self singlePageSectionDivider]];
        }
    }
}

- (UIView *)singlePageSectionDivider {
    UIView *container = [[UIView alloc] initWithFrame:CGRectZero];
    container.translatesAutoresizingMaskIntoConstraints = NO;

    UIView *line = [[UIView alloc] initWithFrame:CGRectZero];
    line.translatesAutoresizingMaskIntoConstraints = NO;
    line.backgroundColor = [UIColor colorWithRed:216/255.0 green:216/255.0 blue:216/255.0 alpha:1.0];
    [container addSubview:line];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    label.textColor = [UIColor colorWithRed:153/255.0 green:153/255.0 blue:153/255.0 alpha:1.0];
    label.text = @"以下为单独页面展示";
    [container addSubview:label];

    [NSLayoutConstraint activateConstraints:@[
        [container.heightAnchor constraintEqualToConstant:34],
        [line.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [line.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [line.topAnchor constraintEqualToAnchor:container.topAnchor constant:8],
        [line.heightAnchor constraintEqualToConstant:1],
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [label.topAnchor constraintEqualToAnchor:line.bottomAnchor constant:8],
        [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [label.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor]
    ]];

    return container;
}

- (UIColor *)iconBgForStyle:(CDFeatureHomeEntryStyle)style {
    switch (style) {
        case CDFeatureHomeEntryStyleBrand:
            return [UIColor colorWithRed:224/255.0 green:237/255.0 blue:255/255.0 alpha:1.0]; // #E0EDFF
        case CDFeatureHomeEntryStyleSuccess:
            return [UIColor colorWithRed:235/255.0 green:255/255.0 blue:247/255.0 alpha:1.0]; // #EBFFF7
        case CDFeatureHomeEntryStyleWarning:
            return [UIColor colorWithRed:255/255.0 green:243/255.0 blue:224/255.0 alpha:1.0]; // #FFF3E0
        case CDFeatureHomeEntryStyleDisabled:
        default:
            return [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0]; // #EEE
    }
}

- (UILabel *)badgeLabelWithText:(NSString *)text {
    UILabel *pill = [[UILabel alloc] initWithFrame:CGRectZero];
    pill.translatesAutoresizingMaskIntoConstraints = NO;
    pill.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    pill.textAlignment = NSTextAlignmentCenter;
    pill.text = text ?: @"";
    pill.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    pill.backgroundColor = [UIColor colorWithRed:238/255.0 green:238/255.0 blue:238/255.0 alpha:1.0];
    pill.layer.cornerRadius = 11;
    pill.clipsToBounds = YES;
    [NSLayoutConstraint activateConstraints:@[
        [pill.heightAnchor constraintEqualToConstant:22]
    ]];
    return pill;
}

- (UIControl *)entryCardForEntry:(CDFeatureHomeEntry *)entry index:(NSInteger)index {
    UIControl *card = [[UIControl alloc] initWithFrame:CGRectZero];
    card.translatesAutoresizingMaskIntoConstraints = NO;
    card.backgroundColor = [UIColor whiteColor];
    card.layer.cornerRadius = 12;
    card.layer.shadowColor = [UIColor colorWithWhite:0 alpha:1].CGColor;
    card.layer.shadowOpacity = 0.06;
    card.layer.shadowOffset = CGSizeMake(0, 1);
    card.layer.shadowRadius = 4;
    card.clipsToBounds = NO;

    UIView *inner = [[UIView alloc] initWithFrame:CGRectZero];
    inner.translatesAutoresizingMaskIntoConstraints = NO;
    inner.userInteractionEnabled = NO;
    [card addSubview:inner];
    [NSLayoutConstraint activateConstraints:@[
        [inner.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:12],
        [inner.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-12],
        [inner.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [inner.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]
    ]];

    UIView *icon = [[UIView alloc] initWithFrame:CGRectZero];
    icon.translatesAutoresizingMaskIntoConstraints = NO;
    icon.userInteractionEnabled = NO;
    icon.backgroundColor = [self iconBgForStyle:entry.style];
    icon.layer.cornerRadius = 8;
    [inner addSubview:icon];

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectZero];
    t.translatesAutoresizingMaskIntoConstraints = NO;
    t.userInteractionEnabled = NO;
    t.font = [UIFont systemFontOfSize:16 weight:UIFontWeightHeavy];
    t.textColor = [UIColor colorWithRed:34/255.0 green:34/255.0 blue:34/255.0 alpha:1.0];
    t.text = entry.title ?: @"";
    [inner addSubview:t];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectZero];
    sub.translatesAutoresizingMaskIntoConstraints = NO;
    sub.userInteractionEnabled = NO;
    sub.font = [UIFont systemFontOfSize:12];
    sub.textColor = [UIColor colorWithRed:102/255.0 green:102/255.0 blue:102/255.0 alpha:1.0];
    sub.numberOfLines = 0;
    sub.text = entry.subtitle ?: @"";
    [inner addSubview:sub];

    UIView *right = [[UIView alloc] initWithFrame:CGRectZero];
    right.translatesAutoresizingMaskIntoConstraints = NO;
    right.userInteractionEnabled = NO;
    [inner addSubview:right];

    UILabel *chevron = [[UILabel alloc] initWithFrame:CGRectZero];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.userInteractionEnabled = NO;
    chevron.text = @"›";
    chevron.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    chevron.textColor = [UIColor colorWithRed:204/255.0 green:204/255.0 blue:204/255.0 alpha:1.0];
    [right addSubview:chevron];

    UILabel *badge = nil;
    if (entry.badge.length > 0) {
        badge = [self badgeLabelWithText:entry.badge];
        badge.userInteractionEnabled = NO;
        [right addSubview:badge];
        chevron.hidden = YES;
    }

    [NSLayoutConstraint activateConstraints:@[
        [icon.leadingAnchor constraintEqualToAnchor:inner.leadingAnchor],
        [icon.topAnchor constraintEqualToAnchor:inner.topAnchor],
        [icon.widthAnchor constraintEqualToConstant:28],
        [icon.heightAnchor constraintEqualToConstant:28],

        [t.leadingAnchor constraintEqualToAnchor:icon.trailingAnchor constant:10],
        [t.topAnchor constraintEqualToAnchor:inner.topAnchor],
        [t.trailingAnchor constraintLessThanOrEqualToAnchor:right.leadingAnchor constant:-10],

        [sub.leadingAnchor constraintEqualToAnchor:t.leadingAnchor],
        [sub.topAnchor constraintEqualToAnchor:t.bottomAnchor constant:4],
        [sub.trailingAnchor constraintLessThanOrEqualToAnchor:right.leadingAnchor constant:-10],
        [sub.bottomAnchor constraintEqualToAnchor:inner.bottomAnchor],

        [right.trailingAnchor constraintEqualToAnchor:inner.trailingAnchor],
        [right.centerYAnchor constraintEqualToAnchor:inner.centerYAnchor]
    ]];

    if (badge) {
        [NSLayoutConstraint activateConstraints:@[
            [badge.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
            [badge.centerYAnchor constraintEqualToAnchor:right.centerYAnchor]
        ]];
    } else {
        [NSLayoutConstraint activateConstraints:@[
            [chevron.trailingAnchor constraintEqualToAnchor:right.trailingAnchor],
            [chevron.centerYAnchor constraintEqualToAnchor:right.centerYAnchor]
        ]];
    }

    card.tag = index;
    card.userInteractionEnabled = entry.enabled;
    if (entry.enabled) {
        [card addTarget:self action:@selector(entryTapped:) forControlEvents:UIControlEventTouchUpInside];
    } else {
        card.alpha = 0.55;
    }
    return card;
}

- (void)entryTapped:(UIControl *)sender {
    NSInteger idx = sender.tag;
    if (idx < 0 || idx >= (NSInteger)self.entries.count) return;
    CDFeatureHomeEntry *entry = self.entries[idx];
    if (!entry.enabled || !entry.destinationBuilder) return;
    UIViewController *destination = entry.destinationBuilder();
    destination.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:destination animated:YES];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    if (self.entries.count > 0) {
        return;
    }

    UIEdgeInsets insets = self.view.safeAreaInsets;
    CGFloat width = self.view.bounds.size.width;
    CGFloat labelWidth = width - 48.0;
    CGFloat buttonWidth = MIN(width - 48.0, 260.0);
    CGFloat centerY = CGRectGetMidY(self.view.bounds);

    self.subtitleLabel.frame = CGRectMake(24.0, centerY - 90.0, labelWidth, 34.0);
    self.enterButton.frame = CGRectMake((width - buttonWidth) / 2.0, CGRectGetMaxY(self.subtitleLabel.frame) + 28.0, buttonWidth, 54.0);

    if (insets.bottom > 0) {
        self.enterButton.frame = CGRectOffset(self.enterButton.frame, 0, -insets.bottom / 4.0);
    }
}

- (void)openDestinationPage {
    if (!self.destinationBuilder) return;
    UIViewController *destination = self.destinationBuilder();
    destination.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:destination animated:YES];
}

@end
