#import "CDPendingTabViewController.h"
#import "CDPlaceholderViewController.h"

@implementation CDPendingTabViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    CDPlaceholderViewController *placeholder = [[CDPlaceholderViewController alloc] initWithTitle:@"待定"
                                                                                           message:@"功能待定"];
    [self addChildViewController:placeholder];
    placeholder.view.frame = self.view.bounds;
    placeholder.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:placeholder.view];
    [placeholder didMoveToParentViewController:self];
    self.title = @"待定";
}

@end
