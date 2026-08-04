#import <CoreMotion/CoreMotion.h>
#import <SceneKit/SceneKit.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CDSpatialAimOverlayView : UIView

@property (nonatomic, assign) CGFloat horizontalFieldOfView;
@property (nonatomic, assign, getter=isAdvancementEnabled) BOOL advancementEnabled;
@property (nonatomic, assign, readonly) BOOL hasValidAttitude;
@property (nonatomic, assign, readonly, getter=isRendering) BOOL rendering;

- (void)updateWithDeviceMotion:(CMDeviceMotion *)motion;
- (void)updateWithCoreMotionQuaternion:(CMQuaternion)quaternion;
- (void)updateWithCoreMotionRotationMatrix:(CMRotationMatrix)rotationMatrix;
- (void)resetAttitudeCalibration;
- (void)reset;
- (void)startRendering;
- (void)stopRendering;

+ (SCNMatrix4)cameraTransformForInitialCoreMotionRotationMatrix:(CMRotationMatrix)initialRotationMatrix
                                       currentCoreMotionRotationMatrix:(CMRotationMatrix)currentRotationMatrix;

@end

NS_ASSUME_NONNULL_END
