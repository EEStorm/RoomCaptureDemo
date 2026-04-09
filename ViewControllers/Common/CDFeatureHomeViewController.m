#import "CDFeatureHomeViewController.h"

@interface CDFeatureHomeViewController ()

@property (nonatomic, copy) NSString *pageTitle;
@property (nonatomic, copy) NSString *buttonTitle;
@property (nonatomic, copy) CDDestinationBuilder destinationBuilder;
@property (nonatomic, strong) UIButton *enterButton;
@property (nonatomic, strong) UILabel *subtitleLabel;

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

- (void)viewDidLoad {
    [super viewDidLoad];

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

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

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
    UIViewController *destination = self.destinationBuilder();
    destination.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:destination animated:YES];
}

@end
