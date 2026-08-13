#import <Foundation/Foundation.h>
#import <SceneKit/SceneKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 空间对点序列：生成一圈水平 3D 目标点，并管理“中心停留一定时间后切下一个点”的状态。
@interface CDSpatialAimSequence : NSObject

/// 固定 3D 点位数组。点位围绕用户初始朝向展开，元素类型为 NSValue 包装的 SCNVector3。
@property (nonatomic, copy, readonly) NSArray<NSValue *> *positions;
/// 当前需要对准的点位下标。
@property (nonatomic, assign, readonly) NSInteger currentIndex;
/// 所有点位都完成连续停留后置为 YES。
@property (nonatomic, assign, readonly, getter=isComplete) BOOL complete;

/// 指定点位数量、半径和单点停留时长。半径为 3D 空间中目标点距离原点的距离。
- (instancetype)initWithPointCount:(NSInteger)pointCount
                            radius:(CGFloat)radius
                      holdDuration:(NSTimeInterval)holdDuration NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// 输入当前帧是否位于屏幕中心阈值内；当且仅当本次调用触发点位推进时返回 YES。
- (BOOL)updateCentered:(BOOL)centered timestamp:(NSTimeInterval)timestamp;
/// 重置回第一个点，并清空连续停留计时。
- (void)reset;

@end

NS_ASSUME_NONNULL_END
