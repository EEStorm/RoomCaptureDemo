#import "CDCapturePlanViewController.h"
#import "CDReshootShootViewController.h"
#import "CDSShapeShootViewController.h"
#import "CDWallOrbitShootViewController.h"

typedef NS_ENUM(NSInteger, CDCapturePlanMode) {
    CDCapturePlanModeWallOrbit = 0,
    CDCapturePlanModeSShape,
    CDCapturePlanModeReshoot,
};

@interface CDCapturePlanViewController ()

@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *subtitleLabel;
@property (nonatomic, strong) UILabel *statusLabel;
@property (nonatomic, strong) UIButton *wallOrbitButton;
@property (nonatomic, strong) UIButton *sShapeButton;
@property (nonatomic, strong) UIButton *reshootButton;
@property (nonatomic, assign) CDCapturePlanMode selectedMode;

@end

@implementation CDCapturePlanViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"拍摄方案";
    self.tabBarItem.title = @"拍摄方案";

    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.titleLabel.text = @"拍摄方案";
    self.titleLabel.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.textColor = [UIColor labelColor];
    self.titleLabel.numberOfLines = 1;
    [self.view addSubview:self.titleLabel];

    self.subtitleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.subtitleLabel.text = @"先定下采集路径，再开始录制。";
    self.subtitleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
    self.subtitleLabel.textAlignment = NSTextAlignmentCenter;
    self.subtitleLabel.textColor = [UIColor secondaryLabelColor];
    self.subtitleLabel.numberOfLines = 2;
    [self.view addSubview:self.subtitleLabel];

    self.wallOrbitButton = [self modeButtonWithTitle:@"沿墙环绕拍摄"
                                         symbolName:@"arrow.triangle.2.circlepath"
                                              action:@selector(handleWallOrbitButton)];
    self.sShapeButton = [self modeButtonWithTitle:@"S型拍摄"
                                       symbolName:@"scribble.variable"
                                            action:@selector(handleSShapeButton)];
    self.reshootButton = [self modeButtonWithTitle:@"补拍"
                                        symbolName:@"camera.viewfinder"
                                             action:@selector(handleReshootButton)];

    [self.view addSubview:self.wallOrbitButton];
    [self.view addSubview:self.sShapeButton];
    [self.view addSubview:self.reshootButton];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.statusLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.textColor = [UIColor secondaryLabelColor];
    self.statusLabel.numberOfLines = 2;
    [self.view addSubview:self.statusLabel];

    self.selectedMode = CDCapturePlanModeWallOrbit;
    [self refreshSelection];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGFloat width = self.view.bounds.size.width - 48.0;
    CGFloat top = self.view.safeAreaInsets.top + 24.0;
    CGFloat buttonHeight = 58.0;

    self.titleLabel.frame = CGRectMake(24.0, top, width, 36.0);
    self.subtitleLabel.frame = CGRectMake(24.0, CGRectGetMaxY(self.titleLabel.frame) + 8.0, width, 42.0);

    CGFloat buttonY = CGRectGetMaxY(self.subtitleLabel.frame) + 28.0;
    self.wallOrbitButton.frame = CGRectMake(24.0, buttonY, width, buttonHeight);
    self.sShapeButton.frame = CGRectMake(24.0, CGRectGetMaxY(self.wallOrbitButton.frame) + 14.0, width, buttonHeight);
    self.reshootButton.frame = CGRectMake(24.0, CGRectGetMaxY(self.sShapeButton.frame) + 14.0, width, buttonHeight);
    self.statusLabel.frame = CGRectMake(24.0, CGRectGetMaxY(self.reshootButton.frame) + 24.0, width, 42.0);
}

- (UIButton *)modeButtonWithTitle:(NSString *)title
                        symbolName:(NSString *)symbolName
                             action:(SEL)action {
    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    button.tag = [self tagForModeTitle:title];
    button.configuration = [self configurationForModeButtonTitle:title
                                                       symbolName:symbolName
                                                         selected:NO];
    button.semanticContentAttribute = UISemanticContentAttributeForceLeftToRight;
    [button addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return button;
}

- (void)handleWallOrbitButton {
    self.selectedMode = CDCapturePlanModeWallOrbit;
    [self refreshSelection];

    CDWallOrbitShootViewController *wallOrbitViewController = [[CDWallOrbitShootViewController alloc] init];
    wallOrbitViewController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:wallOrbitViewController animated:YES];
}

- (void)handleSShapeButton {
    self.selectedMode = CDCapturePlanModeSShape;
    [self refreshSelection];

    CDSShapeShootViewController *sShapeViewController = [[CDSShapeShootViewController alloc] init];
    sShapeViewController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:sShapeViewController animated:YES];
}

- (void)handleReshootButton {
    self.selectedMode = CDCapturePlanModeReshoot;
    [self refreshSelection];

    CDReshootShootViewController *reshootViewController = [[CDReshootShootViewController alloc] init];
    reshootViewController.hidesBottomBarWhenPushed = YES;
    [self.navigationController pushViewController:reshootViewController animated:YES];
}

- (void)refreshSelection {
    [self updateButton:self.wallOrbitButton selected:(self.selectedMode == CDCapturePlanModeWallOrbit)];
    [self updateButton:self.sShapeButton selected:(self.selectedMode == CDCapturePlanModeSShape)];
    [self updateButton:self.reshootButton selected:(self.selectedMode == CDCapturePlanModeReshoot)];
    self.statusLabel.text = [NSString stringWithFormat:@"当前选择：%@", [self titleForMode:self.selectedMode]];
}

- (void)updateButton:(UIButton *)button selected:(BOOL)selected {
    button.selected = selected;
    button.configuration = [self configurationForModeButtonTitle:[self titleForMode:(CDCapturePlanMode)button.tag]
                                                       symbolName:[self symbolNameForMode:(CDCapturePlanMode)button.tag]
                                                         selected:selected];
}

- (NSString *)titleForMode:(CDCapturePlanMode)mode {
    switch (mode) {
        case CDCapturePlanModeWallOrbit:
            return @"沿墙环绕拍摄";
        case CDCapturePlanModeSShape:
            return @"S型拍摄";
        case CDCapturePlanModeReshoot:
            return @"补拍";
    }
    return @"";
}

- (NSString *)symbolNameForMode:(CDCapturePlanMode)mode {
    switch (mode) {
        case CDCapturePlanModeWallOrbit:
            return @"arrow.triangle.2.circlepath";
        case CDCapturePlanModeSShape:
            return @"scribble.variable";
        case CDCapturePlanModeReshoot:
            return @"camera.viewfinder";
    }
    return @"circle";
}

- (NSInteger)tagForModeTitle:(NSString *)title {
    if ([title isEqualToString:@"沿墙环绕拍摄"]) {
        return CDCapturePlanModeWallOrbit;
    }
    if ([title isEqualToString:@"S型拍摄"]) {
        return CDCapturePlanModeSShape;
    }
    return CDCapturePlanModeReshoot;
}

- (UIButtonConfiguration *)configurationForModeButtonTitle:(NSString *)title
                                                symbolName:(NSString *)symbolName
                                                  selected:(BOOL)selected {
    UIButtonConfiguration *configuration = [UIButtonConfiguration grayButtonConfiguration];
    configuration.title = title;
    configuration.titleLineBreakMode = NSLineBreakByTruncatingTail;
    configuration.image = [UIImage systemImageNamed:symbolName];
    configuration.imagePlacement = NSDirectionalRectEdgeLeading;
    configuration.imagePadding = 10.0;
    configuration.contentInsets = NSDirectionalEdgeInsetsMake(0.0, 18.0, 0.0, 18.0);
    configuration.titleAlignment = UIButtonConfigurationTitleAlignmentLeading;
    configuration.baseForegroundColor = selected ? [UIColor systemBlueColor] : [UIColor labelColor];
    configuration.cornerStyle = UIButtonConfigurationCornerStyleLarge;
    configuration.background.cornerRadius = 14.0;
    configuration.background.backgroundColor = selected ? [[UIColor systemBlueColor] colorWithAlphaComponent:0.12] : [UIColor secondarySystemBackgroundColor];
    configuration.background.strokeWidth = 1.0;
    configuration.background.strokeColor = selected ? [UIColor systemBlueColor] : [UIColor separatorColor];
    configuration.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> * _Nonnull incoming) {
        NSMutableDictionary<NSAttributedStringKey, id> *attributes = [incoming mutableCopy];
        attributes[NSFontAttributeName] = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        return attributes;
    };
    return configuration;
}

@end
