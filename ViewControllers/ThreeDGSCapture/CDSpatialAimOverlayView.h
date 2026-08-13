#import <CoreMotion/CoreMotion.h>
#import <SceneKit/SceneKit.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 空间对点浮层：用 SceneKit 做 3D 点位投影，用 UIKit 绘制固定屏幕尺寸的点和中心准星。
@interface CDSpatialAimOverlayView : UIView

/// 当前相机水平视场角。需要与 AVCaptureDevice.activeFormat.videoFieldOfView 同步，保证投影位置贴合预览画面。
@property (nonatomic, assign) CGFloat horizontalFieldOfView;
/// 是否允许“停留后切下一个点”。引导视频/倒计时遮挡预览时置为 NO，避免用户看不到点却推进进度。
@property (nonatomic, assign, getter=isAdvancementEnabled) BOOL advancementEnabled;
/// 是否已经拿到第一帧有效姿态。第一帧会作为本次采集的相对零点。
@property (nonatomic, assign, readonly) BOOL hasValidAttitude;
/// 是否正在渲染。为 YES 表示屏幕刷新定时器和透明 SceneKit 视图正在更新投影位置。
@property (nonatomic, assign, readonly, getter=isRendering) BOOL rendering;

/// 生产环境入口：接收 CoreMotion 输出的设备姿态。
- (void)updateWithDeviceMotion:(CMDeviceMotion *)motion;
/// 测试入口：用确定性的四元数驱动姿态，避免测试依赖真实传感器。
- (void)updateWithCoreMotionQuaternion:(CMQuaternion)quaternion;
/// 应用经过校验的 CoreMotion 旋转矩阵，并更新 SceneKit 相机姿态。
- (void)updateWithCoreMotionRotationMatrix:(CMRotationMatrix)rotationMatrix;
/// 只清除姿态零点，不重置已经完成的点位进度。用于前后台切换后重新校准。
- (void)resetAttitudeCalibration;
/// 完整重置：清除姿态零点，并把点位序列回到第一个点。
- (void)reset;
/// 开始渲染和投影更新。未拿到有效姿态前，浮层仍保持隐藏。
- (void)startRendering;
/// 停止渲染并隐藏所有对点界面元素。
- (void)stopRendering;

/// 将 CoreMotion 姿态转换为 SceneKit 相机变换，并以第一帧姿态作为相对参考。
+ (SCNMatrix4)cameraTransformForInitialCoreMotionRotationMatrix:(CMRotationMatrix)initialRotationMatrix
                                       currentCoreMotionRotationMatrix:(CMRotationMatrix)currentRotationMatrix;

@end

NS_ASSUME_NONNULL_END
