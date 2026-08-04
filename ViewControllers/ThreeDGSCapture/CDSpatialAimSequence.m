#import "CDSpatialAimSequence.h"

@interface CDSpatialAimSequence ()

@property (nonatomic, copy, readwrite) NSArray<NSValue *> *positions;
@property (nonatomic, assign, readwrite) NSInteger currentIndex;
@property (nonatomic, assign, readwrite, getter=isComplete) BOOL complete;
@property (nonatomic, assign) NSTimeInterval holdDuration;
@property (nonatomic, assign) NSTimeInterval holdStartTimestamp;
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
    if (self.isComplete || self.positions.count == 0) {
        return NO;
    }

    if (!centered) {
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
    self.currentIndex = 0;
    self.complete = self.positions.count == 0;
    self.hasHoldStartTimestamp = NO;
    self.holdStartTimestamp = 0.0;
}

@end
