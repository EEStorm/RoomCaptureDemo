#import "CDReshootShootViewController.h"

@implementation CDReshootShootViewController

- (NSString *)captureHostViewControllerClassName {
    return @"CDReshootCaptureHostViewController";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = nil;

    if (@available(iOS 14.0, *)) {
        self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    }
}

@end
