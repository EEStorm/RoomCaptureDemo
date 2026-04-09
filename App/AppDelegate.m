#import "AppDelegate.h"
#import "CDCameraViewController.h"

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    self.window.rootViewController = [[CDCameraViewController alloc] init];
    [self.window makeKeyAndVisible];
    return YES;
}

@end
