#import <CoreMotion/CoreMotion.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CDMotionTrackingUpdateHandler)(CMDeviceMotion *motion);

/// 统一封装 CoreMotion 设备姿态采样，供空间对点和原有 IMU 提示共用，避免同一页面启动多路 CMMotionManager。
@interface CDMotionTrackingService : NSObject

/// 设备姿态更新回调。外部在这里同时驱动空间对点和俯仰/横滚/速度提示界面。
@property (nonatomic, copy, nullable) CDMotionTrackingUpdateHandler updateHandler;
/// 当前是否正在接收 CoreMotion 设备姿态数据。
@property (nonatomic, assign, readonly, getter=isActive) BOOL active;
/// 统一采样间隔。移动速度积分也使用这个间隔，避免界面刷新与采样频率不一致。
@property (nonatomic, assign, readonly) NSTimeInterval updateInterval;

/// 开始采样设备姿态，使用 Z 轴竖直稳定的参考系，减少指南针方向变化对对点的影响。
- (void)start;
/// 停止采样，并让已经排队但尚未执行的 CoreMotion 回调失效。
- (void)stop;

@end

NS_ASSUME_NONNULL_END
