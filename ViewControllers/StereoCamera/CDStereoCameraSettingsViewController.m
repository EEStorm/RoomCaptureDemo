#import "CDStereoCameraSettingsViewController.h"

NSString * const CDStereoCameraSettingsDidChangeNotification = @"CDStereoCameraSettingsDidChange";
NSString * const CDStereoSettingsFrameRateKey = @"CDStereoSettingsFrameRate";
NSString * const CDStereoSettingsWhiteBalanceKey = @"CDStereoSettingsWhiteBalance";
NSString * const CDStereoSettingsShutterSpeedKey = @"CDStereoSettingsShutterSpeed";
NSString * const CDStereoSettingsISOKey = @"CDStereoSettingsISO";
NSString * const CDStereoSettingsResolutionKey = @"CDStereoSettingsResolution";

@interface CDStereoCameraSettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, assign) NSInteger frameRate;
@property (nonatomic, assign) float whiteBalance;
@property (nonatomic, assign) float shutterSpeed;
@property (nonatomic, assign) float iso;
@property (nonatomic, assign) NSInteger resolution;

@end

@implementation CDStereoCameraSettingsViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"双目相机设置";
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

    self.frameRate = [defaults integerForKey:CDStereoSettingsFrameRateKey];
    if (self.frameRate == 0) self.frameRate = 30;

    self.whiteBalance = [defaults floatForKey:CDStereoSettingsWhiteBalanceKey];
    if (self.whiteBalance == 0) self.whiteBalance = 4500;

    self.shutterSpeed = [defaults floatForKey:CDStereoSettingsShutterSpeedKey];
    if (self.shutterSpeed == 0) self.shutterSpeed = 250;

    self.iso = [defaults floatForKey:CDStereoSettingsISOKey];
    if (self.iso == 0) self.iso = 320;

    self.resolution = [defaults integerForKey:CDStereoSettingsResolutionKey];
    if (self.resolution == 0) self.resolution = 1;
}

- (void)saveSettings {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.frameRate forKey:CDStereoSettingsFrameRateKey];
    [defaults setFloat:self.whiteBalance forKey:CDStereoSettingsWhiteBalanceKey];
    [defaults setFloat:self.shutterSpeed forKey:CDStereoSettingsShutterSpeedKey];
    [defaults setFloat:self.iso forKey:CDStereoSettingsISOKey];
    [defaults setInteger:self.resolution forKey:CDStereoSettingsResolutionKey];
    [defaults synchronize];
}

- (void)resetTapped {
    self.resolution = 1;
    self.frameRate = 30;
    self.whiteBalance = 4500;
    self.shutterSpeed = 250;
    self.iso = 320;
    [self.tableView reloadData];
}

- (void)saveTapped {
    [self saveSettings];
    [[NSNotificationCenter defaultCenter] postNotificationName:CDStereoCameraSettingsDidChangeNotification object:nil];
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return @"分辨率";
        case 1: return @"帧率";
        case 2: return @"白平衡 (K)";
        case 3: return @"快门速度";
        case 4: return @"ISO";
        default: return nil;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    if (indexPath.section == 0) {
        cell.textLabel.text = @"分辨率";
        NSArray *resolutions = @[@"720P", @"1080P", @"4K"];
        cell.detailTextLabel.text = resolutions[self.resolution];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 1) {
        cell.textLabel.text = @"帧率";
        NSArray *rates = @[@"24 fps", @"30 fps", @"60 fps"];
        NSArray *rateValues = @[@24, @30, @60];
        NSInteger idx = [rateValues indexOfObject:@(self.frameRate)];
        if (idx == NSNotFound) idx = 1;
        cell.detailTextLabel.text = rates[idx];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if (indexPath.section == 2) {
        cell.textLabel.text = [NSString stringWithFormat:@"%.0fK", self.whiteBalance];

        UIStepper *stepper = [[UIStepper alloc] init];
        stepper.minimumValue = 2700;
        stepper.maximumValue = 7500;
        stepper.stepValue = 100;
        stepper.value = self.whiteBalance;
        stepper.translatesAutoresizingMaskIntoConstraints = NO;
        [stepper addTarget:self action:@selector(whiteBalanceChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:stepper];
        [NSLayoutConstraint activateConstraints:@[
            [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
        ]];
    } else if (indexPath.section == 3) {
        cell.textLabel.text = [NSString stringWithFormat:@"1/%.0f", self.shutterSpeed];

        UIStepper *stepper = [[UIStepper alloc] init];
        stepper.minimumValue = 30;
        stepper.maximumValue = 1000;
        stepper.stepValue = 10;
        stepper.value = self.shutterSpeed;
        stepper.translatesAutoresizingMaskIntoConstraints = NO;
        [stepper addTarget:self action:@selector(shutterSpeedChanged:) forControlEvents:UIControlEventValueChanged];
        [cell.contentView addSubview:stepper];
        [NSLayoutConstraint activateConstraints:@[
            [stepper.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [stepper.rightAnchor constraintEqualToAnchor:cell.contentView.rightAnchor constant:-16],
        ]];
    } else if (indexPath.section == 4) {
        cell.textLabel.text = [NSString stringWithFormat:@"%.0f", self.iso];

        UIStepper *stepper = [[UIStepper alloc] init];
        stepper.minimumValue = 50;
        stepper.maximumValue = 2000;
        stepper.stepValue = 10;
        stepper.value = self.iso;
        stepper.translatesAutoresizingMaskIntoConstraints = NO;
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
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:2]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)shutterSpeedChanged:(UIStepper *)stepper {
    self.shutterSpeed = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:3]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)isoChanged:(UIStepper *)stepper {
    self.iso = stepper.value;
    [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:4]] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    if (indexPath.section == 0) {
        [self showResolutionPicker];
    } else if (indexPath.section == 1) {
        [self showFrameRatePicker];
    }
}

- (void)showResolutionPicker {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"选择分辨率"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    NSArray *resolutions = @[@"720P", @"1080P", @"4K"];
    for (NSInteger i = 0; i < resolutions.count; i++) {
        UIAlertAction *action = [UIAlertAction actionWithTitle:resolutions[i]
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction * _Nonnull action) {
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
                                                       handler:^(UIAlertAction * _Nonnull action) {
            self.frameRate = [values[i] integerValue];
            [self.tableView reloadData];
        }];
        [alert addAction:action];
    }
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
