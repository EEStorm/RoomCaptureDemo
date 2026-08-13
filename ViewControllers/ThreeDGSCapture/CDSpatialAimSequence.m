#import "CDSpatialAimSequence.h"

@interface CDSpatialAimSequence ()

/// 内部可写版本的固定点位数组，初始化后不再变化。
@property (nonatomic, copy, readwrite) NSArray<NSValue *> *positions;
/// 内部可写版本的当前点位下标。
@property (nonatomic, assign, readwrite) NSInteger currentIndex;
/// 内部可写版本的完成状态。
@property (nonatomic, assign, readwrite, getter=isComplete) BOOL complete;
/// 单个点必须连续停留在中心区域的时长。
@property (nonatomic, assign) NSTimeInterval holdDuration;
/// 当前点第一次进入中心阈值时的时间戳。
@property (nonatomic, assign) NSTimeInterval holdStartTimestamp;
/// 是否已经记录当前点进入中心阈值的起始时间。
@property (nonatomic, assign) BOOL hasHoldStartTimestamp;

@end

@implementation CDSpatialAimSequence

- (instancetype)initWithPointCount:(NSInteger)pointCount
                            radius:(CGFloat)radius
                      holdDuration:(NSTimeInterval)holdDuration {
    self = [super init];
    if (self) {
        NSInteger safePointCount = MAX(pointCount, 0);
        CGFloat safeRadius = MAX(radius, 0.0);
        _holdDuration = MAX(holdDuration, 0.0);

        // 生成一圈水平目标点：index 0 位于 SceneKit 相机默认正前方（负 Z 方向）。
        NSMutableArray<NSValue *> *positions = [NSMutableArray arrayWithCapacity:(NSUInteger)safePointCount];
        for (NSInteger index = 0; index < safePointCount; index++) {
            double yaw = 2.0 * M_PI * (double)index / (double)safePointCount;
            SCNVector3 point = SCNVector3Make((float)(safeRadius * sin(yaw)),
                                              0.0f,
                                              (float)(-safeRadius * cos(yaw)));
            [positions addObject:[NSValue valueWithSCNVector3:point]];
        }
        _positions = [positions copy];
        [self reset];
    }
    return self;
}

- (BOOL)updateCentered:(BOOL)centered timestamp:(NSTimeInterval)timestamp {
    // 状态机只在“连续位于中心区域达到 holdDuration”时推进一次，其余情况返回 NO。
    if (self.isComplete || self.positions.count == 0) {
        return NO;
    }

    if (!centered) {
        // 一旦离开中心区域就取消计时，要求用户连续稳定对准，而不是累计零散停留时间。
        self.hasHoldStartTimestamp = NO;
        return NO;
    }

    if (!self.hasHoldStartTimestamp) {
        self.holdStartTimestamp = timestamp;
        self.hasHoldStartTimestamp = YES;
        return NO;
    }

    if (timestamp - self.holdStartTimestamp + 1e-9 < self.holdDuration) {
        return NO;
    }

    self.currentIndex += 1;
    self.complete = self.currentIndex >= (NSInteger)self.positions.count;
    self.hasHoldStartTimestamp = NO;
    return YES;
}

- (void)reset {
    // 回到初始状态：第一个点、未完成、没有任何中心停留计时。
    self.currentIndex = 0;
    self.complete = self.positions.count == 0;
    self.hasHoldStartTimestamp = NO;
    self.holdStartTimestamp = 0.0;
}

@end
