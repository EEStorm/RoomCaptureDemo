#import "CDCameraSettingsViewController.h"

static NSString * const kCDSettingsFrameRate = @"CDSettingsFrameRate";
static NSString * const kCDSettingsWhiteBalance = @"CDSettingsWhiteBalance";
static NSString * const kCDSettingsShutterSpeed = @"CDSettingsShutterSpeed";
static NSString * const kCDSettingsISO = @"CDSettingsISO";
static NSString * const kCDSettingsExposureMode = @"CDSettingsExposureMode";
static NSString * const kCDSettingsAutoLockSettleSeconds = @"CDSettingsAutoLockSettleSeconds";
static NSString * const kCDSettingsResolution = @"CDSettingsResolution";
static NSString * const kCDSettingsCameraLens = @"CDSettingsCameraLens";
static NSString * const kCDLastLockedExposureSeconds = @"CDLastLockedExposureSeconds";
static NSString * const kCDLastLockedISO = @"CDLastLockedISO";
static NSString * const kCDLastLockedTimestamp = @"CDLastLockedTimestamp";
NSString * const CDSettingsIMUPitchThresholdDegreesKey = @"CDSettingsIMUPitchThresholdDegrees";
NSString * const CDSettingsIMURollThresholdDegreesKey = @"CDSettingsIMURollThresholdDegrees";
NSString * const CDSettingsIMUAngularSpeedThresholdDegreesPerSecondKey = @"CDSettingsIMUAngularSpeedThresholdDegreesPerSecond";
NSString * const CDSettingsIMUMovementSpeedThresholdMetersPerSecondKey = @"CDSettingsIMUMovementSpeedThresholdMetersPerSecond";
NSString * const CDSettingsBlurClearThresholdKey = @"CDSettingsBlurClearThreshold";
NSString * const CDSettingsBlurSoftThresholdKey = @"CDSettingsBlurSoftThreshold";

@interface CDCameraSettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, assign) NSInteger frameRate;
@property (nonatomic, assign) float whiteBalance;
@property (nonatomic, assign) float shutterSpeed;
@property (nonatomic, assign) float iso;
@property (nonatomic, assign) NSInteger exposureMode;
@property (nonatomic, assign) float autoLockSettleSeconds;
@property (nonatomic, assign) NSInteger resolution;
@property (nonatomic, assign) NSInteger cameraLens;
@property (nonatomic, assign) BOOL imuSectionExpanded;
@property (nonatomic, assign) BOOL qualitySectionExpanded;
@property (nonatomic, assign) CGFloat imuPitchThresholdDegrees;
@property (nonatomic, assign) CGFloat imuRollThresholdDegrees;
@property (nonatomic, assign) CGFloat imuAngularSpeedThresholdDegreesPerSecond;
@property (nonatomic, assign) CGFloat imuMovementSpeedThresholdMetersPerSecond;
@property (nonatomic, assign) CGFloat blurClearThreshold;
@property (nonatomic, assign) CGFloat blurSoftThreshold;

@end

@implementation CDCameraSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"相机设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self loadSettings];
    [self setupUI];
    [self setupNavigation];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(exposureDidAutoLock)
                                                 name:@"CDCameraExposureDidAutoLock"
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)exposureDidAutoLock {
    if (self.exposureMode == 2) {
        [self.tableView reloadData];
    }
}

- (void)setupNavigation {
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"重置"
                                                                            style:UIBarButtonItemStylePlain
                                                                           target:self
                                                                           action:@selector(resetTapped)];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"保存"
                                                                              style:UIBarButtonItemStyleDone
                                                                             target:self
                                                                             action:@selector(saveTapped)];
}

- (CGFloat)defaultValueForKey:(NSString *)key fallback:(CGFloat)fallback {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGFloat value = [defaults doubleForKey:key];
    return value > 0 ? value : fallback;
}

- (void)setupUI {
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.tableView.leftAnchor constraintEqualToAnchor:self.view.leftAnchor],
        [self.tableView.rightAnchor constraintEqualToAnchor:self.view.rightAnchor],
        [self.tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
    ]];
}

- (void)loadSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    self.frameRate = [defaults integerForKey:kCDSettingsFrameRate];
    if (self.frameRate == 0) self.frameRate = 30;

    self.whiteBalance = [defaults floatForKey:kCDSettingsWhiteBalance];
    if (self.whiteBalance == 0) self.whiteBalance = 4500;

    self.shutterSpeed = [defaults floatForKey:kCDSettingsShutterSpeed];
    if (self.shutterSpeed == 0) self.shutterSpeed = 250;

    self.iso = [defaults floatForKey:kCDSettingsISO];
    if (self.iso == 0) self.iso = 320;

    id exposureModeObj = [defaults objectForKey:kCDSettingsExposureMode];
    if (exposureModeObj == nil) {
        BOOL legacyISOAuto = [defaults boolForKey:@"CDSettingsISOAuto"];
        self.exposureMode = legacyISOAuto ? 1 : 0;
    } else {
        self.exposureMode = [defaults integerForKey:kCDSettingsExposureMode];
    }

    self.autoLockSettleSeconds = [defaults floatForKey:kCDSettingsAutoLockSettleSeconds];
    if (self.autoLockSettleSeconds <= 0) self.autoLockSettleSeconds = 1.0f;

    self.resolution = [defaults integerForKey:kCDSettingsResolution];
    if (self.resolution == 0) self.resolution = 1; // 1 = 1080P

    self.cameraLens = [defaults integerForKey:kCDSettingsCameraLens];

    self.imuPitchThresholdDegrees = [self defaultValueForKey:CDSettingsIMUPitchThresholdDegreesKey fallback:8.0];
    self.imuRollThresholdDegrees = [self defaultValueForKey:CDSettingsIMURollThresholdDegreesKey fallback:20.0];
    self.imuAngularSpeedThresholdDegreesPerSecond = [self defaultValueForKey:CDSettingsIMUAngularSpeedThresholdDegreesPerSecondKey fallback:45.0];
    self.imuMovementSpeedThresholdMetersPerSecond = [self defaultValueForKey:CDSettingsIMUMovementSpeedThresholdMetersPerSecondKey fallback:0.5];
    self.blurClearThreshold = [self defaultValueForKey:CDSettingsBlurClearThresholdKey fallback:45.0];
    self.blurSoftThreshold = [self defaultValueForKey:CDSettingsBlurSoftThresholdKey fallback:20.0];
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.frameRate forKey:kCDSettingsFrameRate];
    [defaults setFloat:self.whiteBalance forKey:kCDSettingsWhiteBalance];
    [defaults setFloat:self.shutterSpeed forKey:kCDSettingsShutterSpeed];
    [defaults setFloat:self.iso forKey:kCDSettingsISO];
    [defaults setInteger:self.exposureMode forKey:kCDSettingsExposureMode];
    [defaults setFloat:self.autoLockSettleSeconds forKey:kCDSettingsAutoLockSettleSeconds];
    [defaults setInteger:self.resolution forKey:kCDSettingsResolution];
    [defaults setInteger:self.cameraLens forKey:kCDSettingsCameraLens];
    [defaults setDouble:self.imuPitchThresholdDegrees forKey:CDSettingsIMUPitchThresholdDegreesKey];
    [defaults setDouble:self.imuRollThresholdDegrees forKey:CDSettingsIMURollThresholdDegreesKey];
    [defaults setDouble:self.imuAngularSpeedThresholdDegreesPerSecond forKey:CDSettingsIMUAngularSpeedThresholdDegreesPerSecondKey];
    [defaults setDouble:self.imuMovementSpeedThresholdMetersPerSecond forKey:CDSettingsIMUMovementSpeedThresholdMetersPerSecondKey];
    [defaults setDouble:self.blurClearThreshold forKey:CDSettingsBlurClearThresholdKey];
    [defaults setDouble:self.blurSoftThreshold forKey:CDSettingsBlurSoftThresholdKey];
    [defaults synchronize];
}

- (void)cancelTapped {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)resetTapped {
    // Reset to default values
    self.cameraLens = 0;      // 超广角 (0.5x)
    self.resolution = 1;      // 1080P
    self.frameRate = 30;      // 30 fps
    self.whiteBalance = 4500;  // 4500K
    self.shutterSpeed = 250;   // 1/250
    self.iso = 320;           // ISO 320
    self.exposureMode = 0;     // Manual
    self.autoLockSettleSeconds = 1.0f; // 1s settle then lock
    self.imuPitchThresholdDegrees = 8.0;
    self.imuRollThresholdDegrees = 20.0;
    self.imuAngularSpeedThresholdDegreesPerSecond = 45.0;
    self.imuMovementSpeedThresholdMetersPerSecond = 0.5;
    self.blurClearThreshold = 45.0;
    self.blurSoftThreshold = 20.0;
    self.imuSectionExpanded = NO;
    self.qualitySectionExpanded = NO;

    [self.tableView reloadData];
}

- (void)saveTapped {
    [self saveSettings];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDCameraSettingsDidChange" object:nil];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 8;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1;
        case 1: return 1;
        case 2: return 1;
        case 3: return 1;
        case 4: return 1;
        case 5: return (self.exposureMode == 2) ? 4 : 2;
        case 6: return self.imuSectionExpanded ? 4 : 0;
        case 7: return self.qualitySectionExpanded ? 2 : 0;
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"摄像头";
        case 1: return @"分辨率";
        case 2: return @"帧率";
        case 3: return @"白平衡 (K)";
        case 4:
            if (self.exposureMode == 0) return @"快门速度";
            return @"快门速度上限 (防拖影)";
        case 5: return @"曝光/ISO";
        default: return nil;
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    if (section < 6) {
        return nil;
    }

    NSString *title = section == 6 ? @"IMU 限制" : @"画面质量";
    BOOL expanded = (section == 6) ? self.imuSectionExpanded : self.qualitySectionExpanded;

    UIControl *container = [[UIControl alloc] initWithFrame:CGRectZero];
    container.backgroundColor = [UIColor clearColor];
    container.tag = 600 + section;
    [container addTarget:self action:@selector(sectionHeaderTapped:) forControlEvents:UIControlEventTouchUpInside];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:15];
    label.textColor = [UIColor labelColor];
    [container addSubview:label];

    UIImageView *chevron = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:(expanded ? @"chevron.down" : @"chevron.right")]];
    chevron.translatesAutoresizingMaskIntoConstraints = NO;
    chevron.tintColor = [UIColor systemGrayColor];
    chevron.contentMode = UIViewContentModeScaleAspectFit;
    chevron.tag = 700 + section;
    [container addSubview:chevron];

    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
        [label.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [chevron.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
        [chevron.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [chevron.widthAnchor constraintEqualToConstant:12],
        [chevron.heightAnchor constraintEqualToConstant:12],
    ]];

    return container;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return section < 6 ? 28.0 : 44.0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section {
    return 0.01;
}

- (NSString *)exposureModeName:(NSInteger)mode {
    switch (mode) {
        case 0: return @"手动 (固定快门+ISO)";
        case 1: return @"快门上限 + ISO自适应";
        case 2: return @"自动测光后锁定";
        default: return @"未知";
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        // Camera lens
        cell.textLabel.text = @"镜头";
        NSArray *lensNames = @[@"超广角 (0.5x)", @"广角 (1.0x)"];
        cell.detailTextLabel.text = lensNames[self.cameraLens];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        // Resolution
        cell.textLabel.text = @"分辨率";
        NSArray *resolutions = @[@"720P", @"1080P", @"4K"];
        cell.detailTextLabel.text = resolutions[self.resolution];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2) {
        // Frame rate
        cell.textLabel.text = @"帧率";
        NSArray *rates = @[@"24 fps", @"30 fps", @"60 fps"];
        NSArray *rateValues = @[@24, @30, @60];
        NSInteger idx = [rateValues indexOfObject:@(self.frameRate)];
        if (idx == NSNotFound) idx = 1;
        cell.detailTextLabel.text = rates[idx];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 3) {
        // White balance
        cell.textLabel.text = [NSString stringWithFormat:@"%.0fK", self.whiteBalance];

        UIStepper *stepper = [[UIStepper alloc] init];
        stepper.minimumValue = 2700;
        stepper.maximumValue = 7500;
        stepper.stepValue = 100;
        stepper.value = self.whiteBalance;
        stepper.translatesAutoresizingMaskIntoConstraints = NO;
        stepper.tag = 301;
        [stepper addTarget:self action:@selector(whiteBalanceChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:stepper];
        [NSLayoutConstraint activateConstraints:@[
            [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
        ]];
    } else if (indexPath.section == 4) {
        // Shutter speed
        if (self.exposureMode == 0) {
            cell.textLabel.text = [NSString stringWithFormat:@"1/%.0f", self.shutterSpeed];
        } else {
            cell.textLabel.text = [NSString stringWithFormat:@"≤ 1/%.0f", self.shutterSpeed];
        }

        UIStepper *stepper = [[UIStepper alloc] init];
        stepper.minimumValue = 30;
        stepper.maximumValue = 1000;
        stepper.stepValue = 10;
        stepper.value = self.shutterSpeed;
        stepper.translatesAutoresizingMaskIntoConstraints = NO;
        stepper.tag = 302;
        [stepper addTarget:self action:@selector(shutterSpeedChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:stepper];
        [NSLayoutConstraint activateConstraints:@[
            [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
        ]];
    } else if (indexPath.section == 5) {
        if (indexPath.row == 0) {
            cell.textLabel.text = @"曝光策略";
            cell.detailTextLabel.text = [self exposureModeName:self.exposureMode];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        } else if (indexPath.row == 1) {
            BOOL isoEditable = (self.exposureMode == 0);
            cell.textLabel.text = isoEditable ? [NSString stringWithFormat:@"ISO %.0f", self.iso] : @"ISO 自动";
            cell.textLabel.textColor = isoEditable ? [UIColor labelColor] : [UIColor systemGrayColor];

            if (isoEditable) {
                UIStepper *stepper = [[UIStepper alloc] init];
                stepper.minimumValue = 50;
                stepper.maximumValue = 2000;
                stepper.stepValue = 10;
                stepper.value = self.iso;
                stepper.translatesAutoresizingMaskIntoConstraints = NO;
                stepper.tag = 303;
                [stepper addTarget:self action:@selector(isoChanged:) forControlEvents:UIControlEventValueChanged];
                [cell.contentView addSubview:stepper];
                [NSLayoutConstraint activateConstraints:@[
                    [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                    [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
                ]];
            }
        } else if (indexPath.row == 2) {
            cell.textLabel.text = [NSString stringWithFormat:@"锁定等待 %.1fs", self.autoLockSettleSeconds];

            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = 0.2;
            stepper.maximumValue = 5.0;
            stepper.stepValue = 0.2;
            stepper.value = self.autoLockSettleSeconds;
            stepper.translatesAutoresizingMaskIntoConstraints = NO;
            stepper.tag = 304;
            [stepper addTarget:self action:@selector(autoLockSettleChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:stepper];
            [NSLayoutConstraint activateConstraints:@[
                [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
            ]];
        } else if (indexPath.row == 3) {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSTimeInterval lockedSeconds = [defaults doubleForKey:kCDLastLockedExposureSeconds];
            float lockedISO = [defaults floatForKey:kCDLastLockedISO];
            NSTimeInterval ts = [defaults doubleForKey:kCDLastLockedTimestamp];

            if (lockedSeconds > 0 && lockedISO > 0) {
                double denom = 1.0 / lockedSeconds;
                NSInteger roundedDenom = (NSInteger)llround(denom);
                NSString *timeText = @"";
                if (ts > 0) {
                    NSDate *date = [NSDate dateWithTimeIntervalSince1970:ts];
                    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
                    fmt.dateFormat = @"HH:mm:ss";
                    timeText = [NSString stringWithFormat:@" (%@)", [fmt stringFromDate:date]];
                }
                cell.textLabel.text = [NSString stringWithFormat:@"已锁定 1/%ld | ISO %.0f%@", (long)roundedDenom, lockedISO, timeText];
            } else {
                cell.textLabel.text = @"已锁定 --";
                cell.textLabel.textColor = [UIColor systemGrayColor];
            }
        }
    } else if (indexPath.section == 6) {
        if (indexPath.row == 0) {
            cell.textLabel.text = [NSString stringWithFormat:@"俯仰角阈值 %.0f°", self.imuPitchThresholdDegrees];
            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = 4;
            stepper.maximumValue = 20;
            stepper.stepValue = 1;
            stepper.value = self.imuPitchThresholdDegrees;
            stepper.translatesAutoresizingMaskIntoConstraints = NO;
            stepper.tag = 401;
            [stepper addTarget:self action:@selector(imuPitchThresholdChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:stepper];
            [NSLayoutConstraint activateConstraints:@[
                [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
            ]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = [NSString stringWithFormat:@"侧倾角阈值 %.0f°", self.imuRollThresholdDegrees];
            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = 5;
            stepper.maximumValue = 45;
            stepper.stepValue = 1;
            stepper.value = self.imuRollThresholdDegrees;
            stepper.translatesAutoresizingMaskIntoConstraints = NO;
            stepper.tag = 402;
            [stepper addTarget:self action:@selector(imuRollThresholdChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:stepper];
            [NSLayoutConstraint activateConstraints:@[
                [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
            ]];
        } else if (indexPath.row == 2) {
            cell.textLabel.text = [NSString stringWithFormat:@"角速度阈值 %.0f°/s", self.imuAngularSpeedThresholdDegreesPerSecond];
            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = 10;
            stepper.maximumValue = 120;
            stepper.stepValue = 1;
            stepper.value = self.imuAngularSpeedThresholdDegreesPerSecond;
            stepper.translatesAutoresizingMaskIntoConstraints = NO;
            stepper.tag = 403;
            [stepper addTarget:self action:@selector(imuAngularSpeedThresholdChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:stepper];
            [NSLayoutConstraint activateConstraints:@[
                [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
            ]];
        } else if (indexPath.row == 3) {
            cell.textLabel.text = [NSString stringWithFormat:@"移动速度阈值 %.1fm/s", self.imuMovementSpeedThresholdMetersPerSecond];
            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = 0.2;
            stepper.maximumValue = 2.0;
            stepper.stepValue = 0.1;
            stepper.value = self.imuMovementSpeedThresholdMetersPerSecond;
            stepper.translatesAutoresizingMaskIntoConstraints = NO;
            stepper.tag = 404;
            [stepper addTarget:self action:@selector(imuMovementThresholdChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:stepper];
            [NSLayoutConstraint activateConstraints:@[
                [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
            ]];
        }
    } else if (indexPath.section == 7) {
        if (indexPath.row == 0) {
            cell.textLabel.text = [NSString stringWithFormat:@"清晰阈值 %.0f", self.blurClearThreshold];
            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = 10;
            stepper.maximumValue = 120;
            stepper.stepValue = 1;
            stepper.value = self.blurClearThreshold;
            stepper.translatesAutoresizingMaskIntoConstraints = NO;
            stepper.tag = 501;
            [stepper addTarget:self action:@selector(blurClearThresholdChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:stepper];
            [NSLayoutConstraint activateConstraints:@[
                [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
            ]];
        } else if (indexPath.row == 1) {
            cell.textLabel.text = [NSString stringWithFormat:@"偏糊阈值 %.0f", self.blurSoftThreshold];
            UIStepper *stepper = [[UIStepper alloc] init];
            stepper.minimumValue = 5;
            stepper.maximumValue = 80;
            stepper.stepValue = 1;
            stepper.value = self.blurSoftThreshold;
            stepper.translatesAutoresizingMaskIntoConstraints = NO;
            stepper.tag = 502;
            [stepper addTarget:self action:@selector(blurSoftThresholdChanged:) forControlEvents:UIControlEventValueChanged];
            [cell.contentView addSubview:stepper];
            [NSLayoutConstraint activateConstraints:@[
                [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
                [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
            ]];
        }
    }

    return cell;
}

- (void)sectionHeaderTapped:(UIControl *)sender {
    NSInteger section = sender.tag - 600;
    if (section == 6) {
        self.imuSectionExpanded = !self.imuSectionExpanded;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:6] withRowAnimation:UITableViewRowAnimationAutomatic];
    } else if (section == 7) {
        self.qualitySectionExpanded = !self.qualitySectionExpanded;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:7] withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

- (void)whiteBalanceChanged:(UIStepper *)stepper {
    self.whiteBalance = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:3]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)shutterSpeedChanged:(UIStepper *)stepper {
    self.shutterSpeed = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:4]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)isoChanged:(UIStepper *)stepper {
    self.iso = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:5]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)autoLockSettleChanged:(UIStepper *)stepper {
    self.autoLockSettleSeconds = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:5]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)imuPitchThresholdChanged:(UIStepper *)stepper {
    self.imuPitchThresholdDegrees = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:6]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)imuRollThresholdChanged:(UIStepper *)stepper {
    self.imuRollThresholdDegrees = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:6]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)imuAngularSpeedThresholdChanged:(UIStepper *)stepper {
    self.imuAngularSpeedThresholdDegreesPerSecond = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:6]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)imuMovementThresholdChanged:(UIStepper *)stepper {
    self.imuMovementSpeedThresholdMetersPerSecond = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:3 inSection:6]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)blurClearThresholdChanged:(UIStepper *)stepper {
    self.blurClearThreshold = stepper.value;
    if (self.blurSoftThreshold >= self.blurClearThreshold) {
        self.blurSoftThreshold = MAX(5.0, self.blurClearThreshold - 1.0);
    }
    [self.tableView reloadData];
}

- (void)blurSoftThresholdChanged:(UIStepper *)stepper {
    self.blurSoftThreshold = MIN(stepper.value, self.blurClearThreshold - 1.0);
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:7]] withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self showCameraLensPicker];
    } else if (indexPath.section == 1) {
        [self showResolutionPicker];
    } else if (indexPath.section == 2) {
        [self showFrameRatePicker];
    } else if (indexPath.section == 5 && indexPath.row == 0) {
        [self showExposureModePicker];
    }
}

- (void)showExposureModePicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择曝光策略"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray<NSNumber *> *modes = @[@0, @1, @2];
    for (NSNumber *modeObj in modes) {
        NSInteger mode = modeObj.integerValue;
        UIAlertAction *action = [UIAlertAction actionWithTitle:[self exposureModeName:mode]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            self.exposureMode = mode;
            [self.tableView reloadData];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showCameraLensPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择镜头"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *lensNames = @[@"超广角 (0.5x)", @"广角 (1.0x)"];
    for (NSInteger i = 0; i < lensNames.count; i++) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:lensNames[i]
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
            self.cameraLens = i;
            [self.tableView reloadData];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showResolutionPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择分辨率"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *resolutions = @[@"720P", @"1080P", @"4K"];
    for (NSInteger i = 0; i < resolutions.count; i++) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:resolutions[i]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            self.resolution = i;
            [self.tableView reloadData];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showFrameRatePicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择帧率"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *rates = @[@"24 fps", @"30 fps", @"60 fps"];
    NSArray *values = @[@24, @30, @60];
    for (NSInteger i = 0; i < rates.count; i++) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:rates[i]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *action) {
            self.frameRate = [values[i] integerValue];
            [self.tableView reloadData];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
