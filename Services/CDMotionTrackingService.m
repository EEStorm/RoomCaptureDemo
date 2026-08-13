#import "CDMotionTrackingService.h"

static const NSTimeInterval CDMotionTrackingDefaultUpdateInterval = 1.0 / 60.0;

@interface CDMotionTrackingService ()

/// CoreMotion 管理对象，真正负责启动/停止设备姿态采样。
@property (nonatomic, strong) CMMotionManager *motionManager;
/// 串行队列，保证姿态回调按顺序处理，避免多个回调并发更新界面状态。
@property (nonatomic, strong) NSOperationQueue *motionQueue;
/// 每次停止采样时递增，用来丢弃停止之后 CoreMotion 可能补发的旧回调。
@property (atomic, assign) NSUInteger motionGeneration;

@end

@implementation CDMotionTrackingService

- (instancetype)init {
    self = [super init];
    if (self) {
        // 统一使用一个 CMMotionManager 和一个串行队列，保证采样频率和回调顺序稳定。
        _motionManager = [[CMMotionManager alloc] init];
        _motionQueue = [[NSOperationQueue alloc] init];
        _motionQueue.name = @"com.roomcapture.spatial-aim-motion";
        _motionQueue.maxConcurrentOperationCount = 1;
        _motionManager.deviceMotionUpdateInterval = CDMotionTrackingDefaultUpdateInterval;
    }
    return self;
}

- (NSTimeInterval)updateInterval {
    return CDMotionTrackingDefaultUpdateInterval;
}

- (BOOL)isActive {
    return self.motionManager.isDeviceMotionActive;
}

- (void)start {
    if (self.motionManager.isDeviceMotionActive || !self.motionManager.isDeviceMotionAvailable) {
        return;
    }

    // 记录本次开始采样的代数；如果停止后又重新开始，旧回调会因为代数不一致被丢弃。
    NSUInteger motionGeneration = self.motionGeneration;
    self.motionManager.deviceMotionUpdateInterval = self.updateInterval;
    __weak typeof(self) weakSelf = self;
    [self.motionManager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
                                                            toQueue:self.motionQueue
                                                        withHandler:^(CMDeviceMotion * _Nullable motion, NSError * _Nullable error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !motion || error) {
            return;
        }
        @synchronized (self) {
            // CoreMotion 停止后仍可能补发一次回调，这里先校验代数再调用外部界面逻辑。
            if (motionGeneration != self.motionGeneration) {
                return;
            }
            CDMotionTrackingUpdateHandler handler = self.updateHandler;
            if (!handler) {
                return;
            }
            handler(motion);
        }
    }];
}

- (void)stop {
    // 停止方法可以被重复调用；每次都递增代数，让所有旧回调自然失效。
    @synchronized (self) {
        self.motionGeneration += 1;
        if (self.motionManager.isDeviceMotionActive) {
            [self.motionManager stopDeviceMotionUpdates];
        }
    }
}

- (void)dealloc {
    [self stop];
    [self.motionQueue cancelAllOperations];
}

@end
