#import "CDSpatialAimOverlayView.h"

#import "CDSpatialAimSequence.h"

#import <float.h>
#import <GLKit/GLKMath.h>
#import <math.h>

static const CGFloat CDSpatialAimDefaultHorizontalFieldOfView = 90.0;
static const CGFloat CDSpatialAimCenterThresholdPoints = 28.0;
static const CGFloat CDSpatialAimPointViewSize = 46.0;
static const CGFloat CDSpatialAimCenterReticleSize = 54.0;

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

@property (nonatomic, strong) SCNView *sceneView;
@property (nonatomic, strong) UIView *aimPointView;
@property (nonatomic, strong) UIView *centerReticleView;
@property (nonatomic, strong) SCNNode *cameraNode;
@property (nonatomic, strong) SCNNode *aimRootNode;
@property (nonatomic, strong) CDSpatialAimSequence *sequence;
@property (nonatomic, copy) NSArray<SCNNode *> *aimNodes;
@property (nonatomic, strong, nullable) SCNNode *currentNode;
@property (nonatomic, strong, nullable) CADisplayLink *displayLink;
@property (nonatomic, assign, readwrite) BOOL hasValidAttitude;
@property (nonatomic, assign, readwrite, getter=isRendering) BOOL rendering;
@property (nonatomic, assign) CMRotationMatrix initialCoreMotionRotationMatrix;
@property (atomic, assign) NSUInteger attitudeGeneration;
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
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;
    self.hidden = YES;
    _advancementEnabled = YES;
    _horizontalFieldOfView = CDSpatialAimDefaultHorizontalFieldOfView;

    SCNView *sceneView = [[SCNView alloc] initWithFrame:self.bounds options:nil];
    sceneView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    sceneView.backgroundColor = [UIColor clearColor];
    sceneView.opaque = NO;
    sceneView.userInteractionEnabled = NO;
    sceneView.rendersContinuously = NO;
    sceneView.preferredFramesPerSecond = 60;
    [self addSubview:sceneView];
    self.sceneView = sceneView;

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

    GLKVector4 initialForward = GLKMatrix4MultiplyVector4(initialCameraMatrix, GLKVector4Make(0.0f, 0.0f, -1.0f, 0.0f));
    float horizontalLength = hypotf(initialForward.x, initialForward.z);
    float yawCorrectionRadians = horizontalLength > FLT_EPSILON
        ? atan2f(-initialForward.x, -initialForward.z)
        : 0.0f;
    GLKMatrix4 yawCorrection = GLKMatrix4MakeYRotation(yawCorrectionRadians);

    GLKMatrix4 currentSensorMatrix = CDGLKMatrix4FromCoreMotionRotationMatrix(currentRotationMatrix);
    GLKMatrix4 currentViewMatrix = GLKMatrix4RotateX(currentSensorMatrix, (float)M_PI_2);
    currentViewMatrix = GLKMatrix4Multiply(currentViewMatrix, yawCorrection);
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
        [self.sequence updateCentered:NO timestamp:0.0];
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    self.sceneView.frame = self.bounds;
    self.aimPointView.bounds = CGRectMake(0.0, 0.0, CDSpatialAimPointViewSize, CDSpatialAimPointViewSize);
    self.centerReticleView.bounds = CGRectMake(0.0, 0.0, CDSpatialAimCenterReticleSize, CDSpatialAimCenterReticleSize);
    self.centerReticleView.center = CGPointMake(CGRectGetMidX(self.bounds), CGRectGetMidY(self.bounds));
    [self bringSubviewToFront:self.aimPointView];
    [self bringSubviewToFront:self.centerReticleView];
}

- (void)rebuildAimNodes {
    NSMutableArray<SCNNode *> *nodes = [NSMutableArray arrayWithCapacity:self.sequence.positions.count];
    for (NSValue *value in self.sequence.positions) {
        SCNNode *node = [SCNNode node];
        node.position = value.SCNVector3Value;
        [nodes addObject:node];
    }
    self.aimNodes = [nodes copy];
}

- (void)revealCurrentNode {
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

    NSUInteger attitudeGeneration = self.attitudeGeneration;
    dispatch_block_t update = ^{
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
    self.attitudeGeneration += 1;
    self.hasValidAttitude = NO;
    self.initialCoreMotionRotationMatrix = (CMRotationMatrix){ 1, 0, 0, 0, 1, 0, 0, 0, 1 };
    self.cameraNode.transform = SCNMatrix4Identity;
    self.aimPointView.hidden = YES;
    self.hidden = YES;
    [self.sequence updateCentered:NO timestamp:0.0];
}

- (void)reset {
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
    SCNNode *node = self.currentNode;
    if (!self.hasValidAttitude || !node || self.advancementAnimationInProgress || !self.isAdvancementEnabled) {
        [self.sequence updateCentered:NO timestamp:displayLink.timestamp];
        self.aimPointView.hidden = YES;
        return;
    }

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
