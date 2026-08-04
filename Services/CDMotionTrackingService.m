#import "CDMotionTrackingService.h"

static const NSTimeInterval CDMotionTrackingDefaultUpdateInterval = 1.0 / 60.0;

@interface CDMotionTrackingService ()

@property (nonatomic, strong) CMMotionManager *motionManager;
@property (nonatomic, strong) NSOperationQueue *motionQueue;
@property (atomic, assign) NSUInteger motionGeneration;

@end

@implementation CDMotionTrackingService

- (instancetype)init {
    self = [super init];
    if (self) {
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
