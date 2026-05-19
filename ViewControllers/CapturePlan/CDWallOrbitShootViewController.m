#import "CDWallOrbitShootViewController.h"

@implementation CDWallOrbitShootViewController

- (NSString *)captureHostViewControllerClassName {
    return @"CDWallOrbitCaptureHostViewController";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = nil;

    if (@available(iOS 14.0, *)) {
        self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    }
}

@end
