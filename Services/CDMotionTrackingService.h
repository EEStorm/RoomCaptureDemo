#import <CoreMotion/CoreMotion.h>
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^CDMotionTrackingUpdateHandler)(CMDeviceMotion *motion);

@interface CDMotionTrackingService : NSObject

@property (nonatomic, copy, nullable) CDMotionTrackingUpdateHandler updateHandler;
@property (nonatomic, assign, readonly, getter=isActive) BOOL active;
@property (nonatomic, assign, readonly) NSTimeInterval updateInterval;

- (void)start;
- (void)stop;

@end

NS_ASSUME_NONNULL_END
