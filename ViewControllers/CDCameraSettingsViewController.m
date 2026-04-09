#import "CDCameraSettingsViewController.h"

static NSString * const kCDSettingsFrameRate = @"CDSettingsFrameRate";
static NSString * const kCDSettingsWhiteBalance = @"CDSettingsWhiteBalance";
static NSString * const kCDSettingsShutterSpeed = @"CDSettingsShutterSpeed";
static NSString * const kCDSettingsISO = @"CDSettingsISO";
static NSString * const kCDSettingsResolution = @"CDSettingsResolution";
static NSString * const kCDSettingsCameraLens = @"CDSettingsCameraLens";

@interface CDCameraSettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;

@property (nonatomic, assign) NSInteger frameRate;
@property (nonatomic, assign) float whiteBalance;
@property (nonatomic, assign) float shutterSpeed;
@property (nonatomic, assign) float iso;
@property (nonatomic, assign) NSInteger resolution;
@property (nonatomic, assign) NSInteger cameraLens;

@end

@implementation CDCameraSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"相机设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];

    [self loadSettings];
    [self setupUI];
    [self setupNavigation];
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

    self.resolution = [defaults integerForKey:kCDSettingsResolution];
    if (self.resolution == 0) self.resolution = 1; // 1 = 1080P

    self.cameraLens = [defaults integerForKey:kCDSettingsCameraLens];
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.frameRate forKey:kCDSettingsFrameRate];
    [defaults setFloat:self.whiteBalance forKey:kCDSettingsWhiteBalance];
    [defaults setFloat:self.shutterSpeed forKey:kCDSettingsShutterSpeed];
    [defaults setFloat:self.iso forKey:kCDSettingsISO];
    [defaults setInteger:self.resolution forKey:kCDSettingsResolution];
    [defaults setInteger:self.cameraLens forKey:kCDSettingsCameraLens];
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

    [self.tableView reloadData];
}

- (void)saveTapped {
    [self saveSettings];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"CDCameraSettingsDidChange" object:nil];
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 6;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 1; // 摄像头
        case 1: return 1; // 分辨率
        case 2: return 1; // 帧率
        case 3: return 1; // 白平衡
        case 4: return 1; // 快门
        case 5: return 1; // ISO
        default: return 0;
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"摄像头";
        case 1: return @"分辨率";
        case 2: return @"帧率";
        case 3: return @"白平衡 (K)";
        case 4: return @"快门速度";
        case 5: return @"ISO";
        default: return nil;
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
        cell.textLabel.text = [NSString stringWithFormat:@"1/%.0f", self.shutterSpeed];

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
        // ISO
        cell.textLabel.text = [NSString stringWithFormat:@"%.0f", self.iso];

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

    return cell;
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
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:5]] withRowAnimation:UITableViewRowAnimationNone];
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
    }
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
