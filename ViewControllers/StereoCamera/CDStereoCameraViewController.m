#import "CDStereoCameraViewController.h"
#import "CDPlaceholderViewController.h"

@implementation CDStereoCameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    CDPlaceholderViewController *placeholder = [[CDPlaceholderViewController alloc] initWithTitle:@"双目相机"
                                                                                           message:@"双目相机拍摄页面待接入"];
    [self addChildViewController:placeholder];
    placeholder.view.frame = self.view.bounds;
    placeholder.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:placeholder.view];
    [placeholder didMoveToParentViewController:self];
    self.title = @"双目相机";
}

@end
