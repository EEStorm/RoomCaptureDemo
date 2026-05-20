#import "CDSShapeShootViewController.h"

@implementation CDSShapeShootViewController

- (NSString *)captureHostViewControllerClassName {
    return @"CDSShapeCaptureHostViewController";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = nil;

    if (@available(iOS 14.0, *)) {
        self.navigationItem.backButtonDisplayMode = UINavigationItemBackButtonDisplayModeMinimal;
    }
}

@end
