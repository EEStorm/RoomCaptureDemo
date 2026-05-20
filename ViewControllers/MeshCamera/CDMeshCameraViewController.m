#import "CDMeshCameraViewController.h"

@implementation CDMeshCameraViewController

- (NSString *)captureHostViewControllerClassName {
    return @"CDMeshCaptureHostViewController";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    self.title = @"mesh相机";

    Class hostClass = NSClassFromString([self captureHostViewControllerClassName]);
    UIViewController *hostViewController = hostClass ? [[hostClass alloc] init] : nil;
    if (!hostViewController) {
        return;
    }
    [self addChildViewController:hostViewController];
    hostViewController.view.frame = self.view.bounds;
    hostViewController.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:hostViewController.view];
    [hostViewController didMoveToParentViewController:self];
}

@end
