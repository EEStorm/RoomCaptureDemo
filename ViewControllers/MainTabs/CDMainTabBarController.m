#import "CDMainTabBarController.h"
#import "CDCameraViewController.h"
#import "CDFeatureHomeViewController.h"
#import "CDMeshCameraViewController.h"
#import "CDPendingTabViewController.h"
#import "CDStereoCameraViewController.h"

@implementation CDMainTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.viewControllers = @[
        [self navigationControllerWithTitle:@"参数相机"
                                      image:@"camera.aperture"
                         destinationBuilder:^UIViewController *{
                             return [[CDCameraViewController alloc] init];
                         }],
        [self navigationControllerWithTitle:@"mesh相机"
                                      image:@"square.3.layers.3d"
                         destinationBuilder:^UIViewController *{
                             return [[CDMeshCameraViewController alloc] init];
                         }],
        [self navigationControllerWithTitle:@"双目相机"
                                      image:@"camera.metering.matrix"
                         destinationBuilder:^UIViewController *{
                             return [[CDStereoCameraViewController alloc] init];
                         }],
        [self navigationControllerWithTitle:@"待定"
                                      image:@"ellipsis.circle"
                         destinationBuilder:^UIViewController *{
                             return [[CDPendingTabViewController alloc] init];
                         }]
    ];
}

- (UINavigationController *)navigationControllerWithTitle:(NSString *)title
                                                    image:(NSString *)imageName
                                       destinationBuilder:(UIViewController *(^)(void))builder {
    CDFeatureHomeViewController *homeViewController = [[CDFeatureHomeViewController alloc] initWithTitle:title
                                                                                                   buttonTitle:@"进入拍摄页面"
                                                                                          destinationBuilder:builder];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:homeViewController];
    navigationController.tabBarItem.title = title;
    navigationController.tabBarItem.image = [UIImage systemImageNamed:imageName];
    return navigationController;
}

@end
