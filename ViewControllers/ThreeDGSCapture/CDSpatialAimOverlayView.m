#import "CDSpatialAimOverlayView.h"

#import "CDSpatialAimSequence.h"

#import <float.h>
#import <GLKit/GLKMath.h>
#import <math.h>

/// 没拿到真实相机视场角前的兜底水平视场角。
static const CGFloat CDSpatialAimDefaultHorizontalFieldOfView = 90.0;
/// 点位距离屏幕中心多少点以内算“对准”。
static const CGFloat CDSpatialAimCenterThresholdPoints = 28.0;
/// 可见橙色点的屏幕尺寸。它是 2D UIKit 视图，不随 3D 远近缩放。
static const CGFloat CDSpatialAimPointViewSize = 46.0;
/// 屏幕中心准星的固定尺寸。
static const CGFloat CDSpatialAimCenterReticleSize = 54.0;

// 姿态数据进入 SceneKit 前必须先校验；一旦相机变换出现 NaN，整个 3D 投影都会异常。
static BOOL CDCoreMotionQuaternionTryNormalize(CMQuaternion quaternion, CMQuaternion *normalizedQuaternion) {
    if (!isfinite(quaternion.x) || !isfinite(quaternion.y) || !isfinite(quaternion.z) || !isfinite(quaternion.w)) {
        return NO;
    }

    double squaredLength = quaternion.x * quaternion.x + quaternion.y * quaternion.y + quaternion.z * quaternion.z + quaternion.w * quaternion.w;
    if (!isfinite(squaredLength)) {
        return NO;
    }

    double length = sqrt(squaredLength);
    if (!isfinite(length) || length <= DBL_EPSILON) {
        return NO;
    }

    CMQuaternion normalized = (CMQuaternion){ quaternion.x / length, quaternion.y / length, quaternion.z / length, quaternion.w / length };
    if (!isfinite(normalized.x) || !isfinite(normalized.y) || !isfinite(normalized.z) || !isfinite(normalized.w)) {
        return NO;
    }

    if (normalizedQuaternion) {
        *normalizedQuaternion = normalized;
    }
    return YES;
}

static BOOL CDCoreMotionRotationMatrixIsFinite(CMRotationMatrix matrix) {
    return isfinite(matrix.m11) && isfinite(matrix.m12) && isfinite(matrix.m13) &&
           isfinite(matrix.m21) && isfinite(matrix.m22) && isfinite(matrix.m23) &&
           isfinite(matrix.m31) && isfinite(matrix.m32) && isfinite(matrix.m33);
}

static GLKMatrix4 CDGLKMatrix4FromCoreMotionRotationMatrix(CMRotationMatrix matrix) {
    // CoreMotion 与 GLKit/SceneKit 的矩阵元素约定不同，这里按 SceneKit 可用的顺序重排。
    return GLKMatrix4Make((float)matrix.m11, (float)matrix.m21, (float)matrix.m31, 0.0f,
                          (float)matrix.m12, (float)matrix.m22, (float)matrix.m32, 0.0f,
                          (float)matrix.m13, (float)matrix.m23, (float)matrix.m33, 0.0f,
                          0.0f,              0.0f,              0.0f,              1.0f);
}

static BOOL CDCoreMotionRotationMatrixFromQuaternion(CMQuaternion quaternion, CMRotationMatrix *rotationMatrix) {
    CMQuaternion normalized;
    if (!CDCoreMotionQuaternionTryNormalize(quaternion, &normalized)) {
        return NO;
    }

    double x = normalized.x;
    double y = normalized.y;
    double z = normalized.z;
    double w = normalized.w;
    CMRotationMatrix matrix = {
        1.0 - 2.0 * (y * y + z * z), 2.0 * (x * y - z * w),       2.0 * (x * z + y * w),
        2.0 * (x * y + z * w),       1.0 - 2.0 * (x * x + z * z), 2.0 * (y * z - x * w),
        2.0 * (x * z - y * w),       2.0 * (y * z + x * w),       1.0 - 2.0 * (x * x + y * y)
    };
    if (!CDCoreMotionRotationMatrixIsFinite(matrix)) {
        return NO;
    }
    if (rotationMatrix) {
        *rotationMatrix = matrix;
    }
    return YES;
}

@interface CDSpatialAimCenterReticleView : UIView
@end

@implementation CDSpatialAimCenterReticleView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return;
    }

    CGPoint center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    UIColor *strokeColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    UIColor *shadowColor = [UIColor colorWithWhite:0.0 alpha:0.45];

    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, 1.0), 2.0, shadowColor.CGColor);
    CGContextSetStrokeColorWithColor(context, strokeColor.CGColor);
    CGContextSetLineWidth(context, 2.0);
    CGContextSetLineCap(context, kCGLineCapRound);

    // 中心准星是纯屏幕界面元素：只表示预览中心，不跟随任何 3D 点位移动。
    CGFloat ringRadius = 12.0;
    CGContextStrokeEllipseInRect(context, CGRectMake(center.x - ringRadius,
                                                     center.y - ringRadius,
                                                     ringRadius * 2.0,
                                                     ringRadius * 2.0));

    CGFloat innerGap = 18.0;
    CGFloat outer = 25.0;
    CGContextMoveToPoint(context, center.x, center.y - outer);
    CGContextAddLineToPoint(context, center.x, center.y - innerGap);
    CGContextMoveToPoint(context, center.x, center.y + innerGap);
    CGContextAddLineToPoint(context, center.x, center.y + outer);
    CGContextMoveToPoint(context, center.x - outer, center.y);
    CGContextAddLineToPoint(context, center.x - innerGap, center.y);
    CGContextMoveToPoint(context, center.x + innerGap, center.y);
    CGContextAddLineToPoint(context, center.x + outer, center.y);
    CGContextStrokePath(context);
    CGContextRestoreGState(context);

    CGContextSetFillColorWithColor(context, [UIColor colorWithWhite:1.0 alpha:0.95].CGColor);
    CGContextFillEllipseInRect(context, CGRectMake(center.x - 2.0, center.y - 2.0, 4.0, 4.0));
}

@end

@interface CDSpatialAimPointView : UIView
@end

@implementation CDSpatialAimPointView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.backgroundColor = [UIColor clearColor];
        self.opaque = NO;
        self.userInteractionEnabled = NO;
        self.contentMode = UIViewContentModeRedraw;
    }
    return self;
}

- (void)drawRect:(CGRect)rect {
    CGContextRef context = UIGraphicsGetCurrentContext();
    if (!context) {
        return;
    }

    // 可见点使用 2D 绘制，避免手机旋转时受 SceneKit 透视投影影响而出现大小变化。
    CGRect circleRect = CGRectInset(self.bounds, 1.0, 1.0);
    UIColor *fillColor = [UIColor colorWithRed:1.0 green:0.48 blue:0.05 alpha:0.95];
    UIColor *shadowColor = [UIColor colorWithWhite:0.0 alpha:0.32];

    CGContextSaveGState(context);
    CGContextSetShadowWithColor(context, CGSizeMake(0.0, 2.0), 4.0, shadowColor.CGColor);
    CGContextSetFillColorWithColor(context, fillColor.CGColor);
    CGContextFillEllipseInRect(context, circleRect);
    CGContextRestoreGState(context);
}

@end

@interface CDSpatialAimOverlayView ()

/// 透明 SceneKit 视图，只负责 3D 相机和点位投影，不直接绘制可见圆点。
@property (nonatomic, strong) SCNView *sceneView;
/// 可见橙色圆点。它的位置来自 SceneKit 投影，大小固定为屏幕点。
@property (nonatomic, strong) UIView *aimPointView;
/// 屏幕中心准星，帮助用户把点对到中心位置。
@property (nonatomic, strong) UIView *centerReticleView;
/// SceneKit 相机节点，姿态由 CoreMotion 转换得到。
@property (nonatomic, strong) SCNNode *cameraNode;
/// 空间点位的根节点。当前实现保持不动，用于承载所有相对点位。
@property (nonatomic, strong) SCNNode *aimRootNode;
/// 点位序列状态机，管理当前点、完成状态和连续停留计时。
@property (nonatomic, strong) CDSpatialAimSequence *sequence;
/// 点位锚点数组。节点没有几何体，只作为 3D 坐标锚点。
@property (nonatomic, copy) NSArray<SCNNode *> *aimNodes;
/// 当前正在显示/等待对准的锚点。
@property (nonatomic, strong, nullable) SCNNode *currentNode;
/// 每帧刷新投影位置和连续停留判断的屏幕刷新定时器。
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
/// 是否已经采集到本轮第一帧有效姿态。
@property (nonatomic, assign, readwrite) BOOL hasValidAttitude;
/// 是否正在渲染空间对点浮层。
@property (nonatomic, assign, readwrite, getter=isRendering) BOOL rendering;
/// 本轮第一帧有效姿态，作为相对零点。
@property (nonatomic, assign) CMRotationMatrix initialCoreMotionRotationMatrix;
/// 重置时递增，避免后台线程里排队的旧姿态回调重新校准新一轮采集。
@property (atomic, assign) NSUInteger attitudeGeneration;
/// 点位完成动画期间置为 YES，避免动画未结束时重复推进。
@property (nonatomic, assign) BOOL advancementAnimationInProgress;

@end

@implementation CDSpatialAimOverlayView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    // 初始化透明叠加层：不拦截触摸，默认隐藏，等拿到有效姿态后再显示。
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.hidden = YES;
    _advancementEnabled = YES;
    _horizontalFieldOfView = CDSpatialAimDefaultHorizontalFieldOfView;

    // 方案说明：SceneKit 只保留相机和不可见 3D 锚点；UIKit 负责绘制可见圆点。
    // 这样圆点能跟随 3D 投影移动，同时大小固定在屏幕坐标系里。
    SCNView *sceneView = [[SCNView alloc] initWithFrame:self.bounds options:nil];
    sceneView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sceneView.backgroundColor = [UIColor clearColor];
    sceneView.opaque = NO;
    sceneView.userInteractionEnabled = NO;
    sceneView.rendersContinuously = NO;
    sceneView.preferredFramesPerSecond = 60;
    [self addSubview:sceneView];
    self.sceneView = sceneView;

    // 可见对点圆点。对应的 SCNNode 只提供 3D 坐标，不再承担绘制。
    UIView *aimPointView = [[CDSpatialAimPointView alloc] initWithFrame:CGRectMake(0.0, 0.0, CDSpatialAimPointViewSize, CDSpatialAimPointViewSize)];
    aimPointView.hidden = YES;
    [self addSubview:aimPointView];
    self.aimPointView = aimPointView;

    UIView *centerReticleView = [[CDSpatialAimCenterReticleView alloc] initWithFrame:CGRectMake(0.0, 0.0, CDSpatialAimCenterReticleSize, CDSpatialAimCenterReticleSize)];
    centerReticleView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin |
                                         UIViewAutoresizingFlexibleRightMargin |
                                         UIViewAutoresizingFlexibleTopMargin |
                                         UIViewAutoresizingFlexibleBottomMargin;
    [self addSubview:centerReticleView];
    self.centerReticleView = centerReticleView;

    SCNScene *scene = [SCNScene scene];
    self.sceneView.scene = scene;

    SCNNode *cameraNode = [SCNNode node];
    cameraNode.camera = [SCNCamera camera];
    cameraNode.camera.zNear = 0.01;
    cameraNode.camera.zFar = 100.0;
    cameraNode.camera.projectionDirection = SCNCameraProjectionDirectionHorizontal;
    cameraNode.camera.fieldOfView = self.horizontalFieldOfView;
    cameraNode.position = SCNVector3Zero;
    [scene.rootNode addChildNode:cameraNode];
    sceneView.pointOfView = cameraNode;
    self.cameraNode = cameraNode;

    self.aimRootNode = [SCNNode node];
    [scene.rootNode addChildNode:self.aimRootNode];

    self.sequence = [[CDSpatialAimSequence alloc] initWithPointCount:8 radius:2.5 holdDuration:0.8];
    [self rebuildAimNodes];
    [self revealCurrentNode];
}

- (void)dealloc {
    [self.displayLink invalidate];
}

+ (SCNMatrix4)cameraTransformForInitialCoreMotionRotationMatrix:(CMRotationMatrix)initialRotationMatrix
                                       currentCoreMotionRotationMatrix:(CMRotationMatrix)currentRotationMatrix {
    if (!CDCoreMotionRotationMatrixIsFinite(initialRotationMatrix) ||
        !CDCoreMotionRotationMatrixIsFinite(currentRotationMatrix)) {
        return SCNMatrix4Identity;
    }

    GLKMatrix4 initialSensorMatrix = CDGLKMatrix4FromCoreMotionRotationMatrix(initialRotationMatrix);
    GLKMatrix4 initialViewMatrix = GLKMatrix4RotateX(initialSensorMatrix, (float)M_PI_2);
    bool initialViewIsInvertible = false;
    GLKMatrix4 initialCameraMatrix = GLKMatrix4Invert(initialViewMatrix, &initialViewIsInvertible);
    if (!initialViewIsInvertible) {
        return SCNMatrix4Identity;
    }

    // 第一帧有效姿态作为本轮采集的相对零点，只校正水平偏航角。
    // 这样用户不需要朝固定罗盘方向开始，但俯仰/横滚仍然能真实反映手机姿态。
    GLKVector4 initialForward = GLKMatrix4MultiplyVector4(initialCameraMatrix, GLKVector4Make(0.0f, 0.0f, -1.0f, 0.0f));
    float horizontalLength = hypotf(initialForward.x, initialForward.z);
    float yawCorrectionRadians = horizontalLength > FLT_EPSILON
        ? atan2f(-initialForward.x, -initialForward.z)
        : 0.0f;
    GLKMatrix4 yawCorrection = GLKMatrix4MakeYRotation(yawCorrectionRadians);

    GLKMatrix4 currentSensorMatrix = CDGLKMatrix4FromCoreMotionRotationMatrix(currentRotationMatrix);
    GLKMatrix4 currentViewMatrix = GLKMatrix4RotateX(currentSensorMatrix, (float)M_PI_2);
    currentViewMatrix = GLKMatrix4Multiply(currentViewMatrix, yawCorrection);
    // SceneKit 相机节点需要“相机到世界坐标”的变换，这里将视图矩阵取逆后赋给相机节点。
    bool currentViewIsInvertible = false;
    GLKMatrix4 cameraMatrix = GLKMatrix4Invert(currentViewMatrix, &currentViewIsInvertible);
    return currentViewIsInvertible ? SCNMatrix4FromGLKMatrix4(cameraMatrix) : SCNMatrix4Identity;
}

- (void)setHorizontalFieldOfView:(CGFloat)horizontalFieldOfView {
    CGFloat safeFieldOfView = horizontalFieldOfView > 1.0 ? horizontalFieldOfView : CDSpatialAimDefaultHorizontalFieldOfView;
    _horizontalFieldOfView = safeFieldOfView;
    self.cameraNode.camera.fieldOfView = safeFieldOfView;
}

- (void)setAdvancementEnabled:(BOOL)advancementEnabled {
    _advancementEnabled = advancementEnabled;
    if (!advancementEnabled) {
        // 暂停推进时清掉当前点的连续停留状态，恢复后需要重新稳定对准。
        [self.sequence updateCentered:NO timestamp:0.0];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    // 所有可见元素都按屏幕坐标布局，避免旋转/投影改变控件尺寸。
    self.sceneView.frame = self.bounds;
    self.aimPointView.bounds = CGRectMake(0.0, 0.0, CDSpatialAimPointViewSize, CDSpatialAimPointViewSize);
    self.centerReticleView.bounds = CGRectMake(0.0, 0.0, CDSpatialAimCenterReticleSize, CDSpatialAimCenterReticleSize);
    self.centerReticleView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self bringSubviewToFront:self.aimPointView];
    [self bringSubviewToFront:self.centerReticleView];
}

- (void)rebuildAimNodes {
    // 根据序列生成所有 3D 锚点。锚点列表初始化后保持稳定，只切换当前生效节点。
    NSMutableArray<SCNNode *> *nodes = [NSMutableArray arrayWithCapacity:self.sequence.positions.count];
    for (NSValue *value in self.sequence.positions) {
        // 不创建几何体，节点只作为稳定 3D 锚点；可见圆点由 aimPointView 渲染。
        SCNNode *node = [SCNNode node];
        node.position = value.SCNVector3Value;
        [nodes addObject:node];
    }
    self.aimNodes = [nodes copy];
}

- (void)revealCurrentNode {
    // 把当前序列下标对应的锚点挂到场景中，并重置 2D 圆点的动画状态。
    if (self.sequence.isComplete || self.sequence.currentIndex >= (NSInteger)self.aimNodes.count) {
        self.currentNode = nil;
        self.advancementAnimationInProgress = NO;
        return;
    }
    SCNNode *node = self.aimNodes[(NSUInteger)self.sequence.currentIndex];
    node.opacity = 1.0;
    node.scale = SCNVector3Make(1.0, 1.0, 1.0);
    [self.aimRootNode addChildNode:node];
    self.currentNode = node;
    self.aimPointView.alpha = 1.0;
    self.aimPointView.transform = CGAffineTransformIdentity;
    self.aimPointView.hidden = YES;
    self.advancementAnimationInProgress = NO;
}

- (void)updateWithDeviceMotion:(CMDeviceMotion *)motion {
    if (motion) {
        [self updateWithCoreMotionRotationMatrix:motion.attitude.rotationMatrix];
    }
}

- (void)updateWithCoreMotionQuaternion:(CMQuaternion)quaternion {
    CMRotationMatrix rotationMatrix;
    if (!CDCoreMotionRotationMatrixFromQuaternion(quaternion, &rotationMatrix)) {
        return;
    }
    [self updateWithCoreMotionRotationMatrix:rotationMatrix];
}

- (void)updateWithCoreMotionRotationMatrix:(CMRotationMatrix)rotationMatrix {
    if (!CDCoreMotionRotationMatrixIsFinite(rotationMatrix)) {
        return;
    }

    // CoreMotion 回调可能来自后台队列，统一切回主线程更新 SceneKit 和 UIKit 状态。
    NSUInteger attitudeGeneration = self.attitudeGeneration;
    dispatch_block_t update = ^{
        // reset 可能发生在后台姿态回调排队之后；代数不一致时丢弃旧回调。
        if (attitudeGeneration != self.attitudeGeneration) {
            return;
        }
        if (!self.hasValidAttitude) {
            self.initialCoreMotionRotationMatrix = rotationMatrix;
            self.hasValidAttitude = YES;
            self.hidden = !self.isRendering;
        }

        self.cameraNode.transform = [CDSpatialAimOverlayView cameraTransformForInitialCoreMotionRotationMatrix:self.initialCoreMotionRotationMatrix
                                                                                 currentCoreMotionRotationMatrix:rotationMatrix];
    };
    if ([NSThread isMainThread]) {
        update();
    } else {
        dispatch_async(dispatch_get_main_queue(), update);
    }
}

- (void)resetAttitudeCalibration {
    // 只清空姿态零点，不动序列下标；用于前后台回来后重新确定当前朝向。
    self.attitudeGeneration += 1;
    self.hasValidAttitude = NO;
    self.initialCoreMotionRotationMatrix = (CMRotationMatrix){ 1, 0, 0, 0, 1, 0, 0, 0, 1 };
    self.cameraNode.transform = SCNMatrix4Identity;
    self.aimPointView.hidden = YES;
    self.hidden = YES;
    [self.sequence updateCentered:NO timestamp:0.0];
}

- (void)reset {
    // 完整重置：姿态重新校准、序列回到第一个点、移除场景中残留节点和动画。
    [self resetAttitudeCalibration];
    [self.sequence reset];
    self.advancementAnimationInProgress = NO;
    [self.currentNode removeAllActions];
    [self.currentNode removeFromParentNode];
    for (SCNNode *node in self.aimNodes) {
        [node removeAllActions];
        [node removeFromParentNode];
    }
    [self revealCurrentNode];
}

- (void)startRendering {
    if (self.isRendering) {
        return;
    }
    // 渲染先启动，但视图是否显示取决于是否已经拿到第一帧有效姿态。
    self.rendering = YES;
    self.hidden = !self.hasValidAttitude;
    self.sceneView.rendersContinuously = YES;
    self.sceneView.playing = YES;
    CADisplayLink *displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(handleDisplayLink:)];
    displayLink.preferredFramesPerSecond = 60;
    [displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    self.displayLink = displayLink;
}

- (void)stopRendering {
    // 停止屏幕刷新定时器和 SceneKit 连续渲染，避免页面不可见时继续刷新。
    self.rendering = NO;
    self.hidden = YES;
    self.aimPointView.hidden = YES;
    [self.displayLink invalidate];
    self.displayLink = nil;
    self.sceneView.playing = NO;
    self.sceneView.rendersContinuously = NO;
    [self.sequence updateCentered:NO timestamp:0.0];
}

- (void)handleDisplayLink:(CADisplayLink *)displayLink {
    // 每帧执行三件事：投影当前锚点、判断是否在中心阈值内、满足停留时间后切下一个点。
    SCNNode *node = self.currentNode;
    if (!self.hasValidAttitude || !node || self.advancementAnimationInProgress || !self.isAdvancementEnabled) {
        [self.sequence updateCentered:NO timestamp:displayLink.timestamp];
        self.aimPointView.hidden = YES;
        return;
    }

    // 将当前 3D 锚点通过 SceneKit 相机投影到屏幕坐标，再把固定尺寸的 UIKit 圆点放过去。
    SCNVector3 worldPosition = [node.presentationNode convertPosition:SCNVector3Zero toNode:nil];
    SCNVector3 projected = [self.sceneView projectPoint:worldPosition];
    CGSize size = self.bounds.size;
    CGFloat dx = projected.x - size.width * 0.5;
    CGFloat dy = projected.y - size.height * 0.5;
    BOOL visibleDepth = projected.z >= 0.0 && projected.z <= 1.0;
    self.aimPointView.hidden = !visibleDepth;
    if (visibleDepth) {
        self.aimPointView.center = CGPointMake(projected.x, projected.y);
        self.aimPointView.bounds = CGRectMake(0.0, 0.0, CDSpatialAimPointViewSize, CDSpatialAimPointViewSize);
    }

    BOOL centered = visibleDepth && hypot(dx, dy) <= CDSpatialAimCenterThresholdPoints;
    if (![self.sequence updateCentered:centered timestamp:displayLink.timestamp]) {
        return;
    }

    self.advancementAnimationInProgress = YES;
    // 完成当前点时只动画 2D 圆点；3D 锚点本身保持无缩放，动画结束后切到下一个锚点。
    [UIView animateWithDuration:0.18
                     animations:^{
        self.aimPointView.alpha = 0.0;
        self.aimPointView.transform = CGAffineTransformMakeScale(0.25, 0.25);
    } completion:^(BOOL finished) {
        [node removeFromParentNode];
        if (self.currentNode == node) {
            self.currentNode = nil;
        }
        [self revealCurrentNode];
    }];
}

@end
