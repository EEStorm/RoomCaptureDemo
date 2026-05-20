#import "CDMainTabBarController.h"
#import "CDCameraViewController.h"
#import "CDFeatureHomeViewController.h"
#import "CDMeshCameraViewController.h"
#import "CDPendingTabViewController.h"
#import "CDStereoCameraViewController.h"
#import "CD3DGSCaptureViewController.h"
#import "../RoomShootFlow/CDVideoConfirmViewController.h"
#import "../RoomShootFlow/CDRoomItem.h"
#import "../RoomShootFlow/CDRoomVideoReviewViewController.h"
#import "../ThreeDGSCapture/CD3DGSTrainingResultSummary.h"
#import "../ThreeDGSCapture/CD3DGSTrainingResultViewController.h"

@implementation CDMainTabBarController

- (void)viewDidLoad {
    [super viewDidLoad];
    UINavigationController *roomShootNavigationController = [self.class roomShootDemoNavigationController];

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
        roomShootNavigationController,
        [self navigationControllerWithTitle:@"待定"
                                      image:@"ellipsis.circle"
                         destinationBuilder:^UIViewController *{
                             return [[CD3DGSCaptureViewController alloc] init];
                         }]
    ];
}

- (UINavigationController *)navigationControllerWithTitle:(NSString *)title
                                                    image:(NSString *)imageName
                                       destinationBuilder:(UIViewController *(^)(void))builder {
    return [self navigationControllerWithTitle:title
                                         image:imageName
                                   buttonTitle:@"进入拍摄页面"
                            destinationBuilder:builder];
}

- (UINavigationController *)navigationControllerWithTitle:(NSString *)title
                                                    image:(NSString *)imageName
                                              buttonTitle:(NSString *)buttonTitle
                                       destinationBuilder:(UIViewController *(^)(void))builder {
    CDFeatureHomeViewController *homeViewController = [[CDFeatureHomeViewController alloc] initWithTitle:title
                                                                                                   buttonTitle:buttonTitle
                                                                                          destinationBuilder:builder];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:homeViewController];
    navigationController.tabBarItem.title = title;
    navigationController.tabBarItem.image = [UIImage systemImageNamed:imageName];
    return navigationController;
}

+ (UIViewController *)roomShootDemoHomeViewController {
    NSArray<CDFeatureHomeEntry *> *roomShootEntries = [self roomShootDemoEntries];
    return [[CDFeatureHomeViewController alloc] initWithTitle:@"房间采集Demo"
                                                      entries:roomShootEntries];
}

+ (UINavigationController *)roomShootDemoNavigationController {
    UIViewController *homeViewController = [self roomShootDemoHomeViewController];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:homeViewController];
    navigationController.tabBarItem.title = @"房间采集Demo";
    navigationController.tabBarItem.image = [UIImage systemImageNamed:@"house.fill"];
    return navigationController;
}

+ (NSArray<CDFeatureHomeEntry *> *)roomShootDemoEntries {
    CDFeatureHomeEntry *entry1 = [CDFeatureHomeEntry entryWithTitle:@"单分间完整拍摄演示"
                                                           subtitle:@"进入四步房间采集流程"
                                                              style:CDFeatureHomeEntryStyleBrand
                                                            enabled:YES
                                                              badge:nil
                                                  destinationBuilder:^UIViewController *{
        return [[CD3DGSCaptureViewController alloc] init];
    }];
    CDFeatureHomeEntry *entry2 = [CDFeatureHomeEntry entryWithTitle:@"审核入口"
                                                           subtitle:@"查看采集流程与房间审核状态"
                                                              style:CDFeatureHomeEntryStyleBrand
                                                            enabled:YES
                                                              badge:nil
                                                  destinationBuilder:^UIViewController *{
        return [[CDVideoConfirmViewController alloc] init];
    }];
    CDFeatureHomeEntry *entry3 = [CDFeatureHomeEntry entryWithTitle:@"审核详情"
                                                           subtitle:@"查看“已通过”的示例详情页"
                                                              style:CDFeatureHomeEntryStyleSuccess
                                                            enabled:YES
                                                              badge:nil
                                                  destinationBuilder:^UIViewController *{
        CDRoomItem *room = [[CDRoomItem alloc] init];
        room.roomId = @"demo_passed_room";
        room.roomName = @"示例房间（已通过）";
        room.captureComplete = YES;
        room.auditStatus = 2;
        room.auditReason = @"";
        return [[CDRoomVideoReviewViewController alloc] initWithRoom:room];
    }];
    CDFeatureHomeEntry *entry4 = [CDFeatureHomeEntry entryWithTitle:@"审核详情（审核中）"
                                                           subtitle:@"查看“审核中”的示例详情页"
                                                              style:CDFeatureHomeEntryStyleWarning
                                                            enabled:YES
                                                              badge:nil
                                                  destinationBuilder:^UIViewController *{
        CDRoomItem *room = [[CDRoomItem alloc] init];
        room.roomId = @"demo_reviewing_room";
        room.roomName = @"示例房间（审核中）";
        room.captureComplete = YES;
        room.auditStatus = 1;
        room.auditReason = @"";
        return [[CDRoomVideoReviewViewController alloc] initWithRoom:room];
    }];
    CDFeatureHomeEntry *entry5 = [CDFeatureHomeEntry entryWithTitle:@"审核详情（未通过）"
                                                           subtitle:@"查看“未通过”的示例详情页"
                                                              style:CDFeatureHomeEntryStyleWarning
                                                            enabled:YES
                                                              badge:nil
                                                  destinationBuilder:^UIViewController *{
        CDRoomItem *room = [[CDRoomItem alloc] init];
        room.roomId = @"demo_failed_room";
        room.roomName = @"示例房间（未通过）";
        room.captureComplete = YES;
        room.auditStatus = 3;
        room.auditReason = @"存在明显模糊和覆盖缺口，请重录此房间";
        return [[CDRoomVideoReviewViewController alloc] initWithRoom:room];
    }];
    CDFeatureHomeEntry *entry6 = [CDFeatureHomeEntry entryWithTitle:@"高斯训练结果"
                                                           subtitle:@"查看训练进度与结果示例"
                                                              style:CDFeatureHomeEntryStyleWarning
                                                            enabled:YES
                                                              badge:nil
                                                  destinationBuilder:^UIViewController *{
        CD3DGSTrainingResultSummary *summary = [CD3DGSTrainingResultSummary demoSummary];
        return [[CD3DGSTrainingResultViewController alloc] initWithSummary:summary];
    }];
    CDFeatureHomeEntry *entry7 = [CDFeatureHomeEntry entryWithTitle:@"外展示视频生成列表"
                                                           subtitle:@"查看生成列表（未接入）"
                                                              style:CDFeatureHomeEntryStyleDisabled
                                                            enabled:NO
                                                              badge:@"敬请期待"
                                                  destinationBuilder:nil];
    return @[entry1, entry2, entry3, entry4, entry5, entry6, entry7];
}

@end
