# Panorama Camera Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a fourth-tab panorama camera that feels close to iPhone native panorama capture, supports portrait-held left-to-right panning, generates a correctly oriented panorama image, previews it in-app, and saves it to Photos.

**Architecture:** Keep AVFoundation preview and sample-buffer capture in `CDPanoramaCameraViewController`, but move guidance, frame-selection, orientation normalization, and stitching decisions into small focused classes so they can be tested outside hardware. The controller becomes the orchestrator for page state, while pure logic units own progress, key-frame admission, and overlap-based panorama assembly.

**Tech Stack:** Objective-C, AVFoundation, CoreMotion, Photos, CoreImage, UIKit, XCTest, XcodeGen

---

## File Structure

### Existing files to modify

- `project.yml`
  Add `CoreMotion.framework` and a new unit-test target so guidance, frame-selection, and stitcher logic can be tested without the camera.
- `ViewControllers/MainTabs/CDMainTabBarController.m`
  Replace the fourth-tab placeholder entry with the panorama camera entry.
- `CaptureDemo/Info.plist`
  Ensure `NSPhotoLibraryAddUsageDescription` copy is acceptable for panorama image saving.

### Existing files to replace or retire

- `ViewControllers/PendingTab/CDPendingTabViewController.m`
  Stop using this controller as the fourth-tab destination. Leave the file alone unless cleanup is needed after the tab swap.

### New production files

- `ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.h`
- `ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.m`
  Own preview, state machine wiring, motion updates, accepted frame intake, result presentation, and photo save flow.
- `ViewControllers/PanoramaCamera/CDPanoramaGuidanceEngine.h`
- `ViewControllers/PanoramaCamera/CDPanoramaGuidanceEngine.m`
  Convert yaw, pitch, roll, and angular speed into progress, guidance text, and completion state.
- `ViewControllers/PanoramaCamera/CDPanoramaFrameSelector.h`
- `ViewControllers/PanoramaCamera/CDPanoramaFrameSelector.m`
  Accept or reject incoming frames based on capture progress thresholds and minimum spacing.
- `ViewControllers/PanoramaCamera/CDPanoramaFrameNormalizer.h`
- `ViewControllers/PanoramaCamera/CDPanoramaFrameNormalizer.m`
  Convert sample buffers into one internal portrait-up `UIImage`.
- `ViewControllers/PanoramaCamera/CDPanoramaComposer.h`
- `ViewControllers/PanoramaCamera/CDPanoramaComposer.m`
  Build a lightweight overlap-stitched panorama from accepted key frames.

### New test files

- `CaptureDemoTests/CDPanoramaGuidanceEngineTests.m`
- `CaptureDemoTests/CDPanoramaFrameSelectorTests.m`
- `CaptureDemoTests/CDPanoramaComposerTests.m`

---

### Task 1: Add Test Harness And Panorama Entry

**Files:**
- Modify: `project.yml`
- Modify: `ViewControllers/MainTabs/CDMainTabBarController.m`
- Create: `ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.h`
- Create: `ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.m`
- Test: `CaptureDemoTests/CDPanoramaGuidanceEngineTests.m`

- [ ] **Step 1: Add a failing unit-test target declaration**

```yaml
targets:
  CaptureDemo:
    type: application
    platform: iOS
    sources:
      - path: App
      - path: CaptureDemo
      - path: Resources
      - path: Services
      - path: ViewControllers
    dependencies:
      - framework: AVFoundation.framework
        embed: false
      - framework: ARKit.framework
        embed: false
      - framework: SceneKit.framework
        embed: false
      - framework: Metal.framework
        embed: false
      - framework: Photos.framework
        embed: false
      - framework: CoreMotion.framework
        embed: false
      - sdk: CoreMedia.framework
        embed: false

  CaptureDemoTests:
    type: bundle.unit-test
    platform: iOS
    sources:
      - path: CaptureDemoTests
    dependencies:
      - target: CaptureDemo
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.captureDemoTests
        GENERATE_INFOPLIST_FILE: YES
```

- [ ] **Step 2: Regenerate the Xcode project and verify tests fail because the panorama guidance files do not exist yet**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test`

Expected: FAIL with compiler errors for missing panorama guidance headers or test symbols.

- [ ] **Step 3: Swap the fourth tab entry to a panorama camera destination**

```objc
#import "CDPanoramaCameraViewController.h"

        [self navigationControllerWithTitle:@"全景相机"
                                      image:@"pano"
                         destinationBuilder:^UIViewController *{
                             return [[CDPanoramaCameraViewController alloc] init];
                         }]
```

- [ ] **Step 4: Add the minimal panorama controller skeleton**

```objc
// CDPanoramaCameraViewController.h
#import <UIKit/UIKit.h>

@interface CDPanoramaCameraViewController : UIViewController
@end

// CDPanoramaCameraViewController.m
#import "CDPanoramaCameraViewController.h"

@implementation CDPanoramaCameraViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"全景相机";
}

@end
```

- [ ] **Step 5: Re-run generation and app build**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo -sdk iphonesimulator -configuration Debug build`

Expected: PASS, with the fourth tab now compiling against the panorama controller.

- [ ] **Step 6: Commit the wiring baseline**

```bash
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo add project.yml ViewControllers/MainTabs/CDMainTabBarController.m ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.h ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.m
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo commit -m "Add panorama camera entry and test target"
```

### Task 2: Build The Guidance Engine With TDD

**Files:**
- Create: `ViewControllers/PanoramaCamera/CDPanoramaGuidanceEngine.h`
- Create: `ViewControllers/PanoramaCamera/CDPanoramaGuidanceEngine.m`
- Test: `CaptureDemoTests/CDPanoramaGuidanceEngineTests.m`

- [ ] **Step 1: Write failing tests for progress, speed guidance, and completion**

```objc
#import <XCTest/XCTest.h>
#import "CDPanoramaGuidanceEngine.h"

@interface CDPanoramaGuidanceEngineTests : XCTestCase
@end

@implementation CDPanoramaGuidanceEngineTests

- (void)testFirstUpdateCalibratesEngine {
    CDPanoramaGuidanceEngine *engine = [[CDPanoramaGuidanceEngine alloc] init];
    CDPanoramaGuidanceState state = [engine updateWithYaw:0.40
                                                    pitch:0.0
                                                     roll:0.0
                                                timestamp:1.0];
    XCTAssertTrue(state.isCalibrating);
    XCTAssertEqualWithAccuracy(state.progress, 0.0, 0.001);
}

- (void)testMovingRightAdvancesProgress {
    CDPanoramaGuidanceEngine *engine = [[CDPanoramaGuidanceEngine alloc] init];
    [engine updateWithYaw:0.10 pitch:0.0 roll:0.0 timestamp:1.0];
    CDPanoramaGuidanceState state = [engine updateWithYaw:0.80 pitch:0.0 roll:0.0 timestamp:2.0];
    XCTAssertGreaterThan(state.progress, 0.0);
    XCTAssertEqualObjects(state.hintText, @"沿中线向右移动");
}

- (void)testFastMovementRequestsSlowDown {
    CDPanoramaGuidanceEngine *engine = [[CDPanoramaGuidanceEngine alloc] init];
    [engine updateWithYaw:0.10 pitch:0.0 roll:0.0 timestamp:1.0];
    CDPanoramaGuidanceState state = [engine updateWithYaw:1.20 pitch:0.0 roll:0.0 timestamp:1.1];
    XCTAssertEqualObjects(state.hintText, @"移动太快，请放慢");
}

- (void)testLargePitchRequestsVerticalCorrection {
    CDPanoramaGuidanceEngine *engine = [[CDPanoramaGuidanceEngine alloc] init];
    [engine updateWithYaw:0.10 pitch:0.0 roll:0.0 timestamp:1.0];
    CDPanoramaGuidanceState state = [engine updateWithYaw:0.40 pitch:0.45 roll:0.0 timestamp:2.0];
    XCTAssertEqualObjects(state.hintText, @"请稍微压低手机");
}

- (void)testReachingTargetMarksCaptureComplete {
    CDPanoramaGuidanceEngine *engine = [[CDPanoramaGuidanceEngine alloc] init];
    [engine updateWithYaw:0.10 pitch:0.0 roll:0.0 timestamp:1.0];
    CDPanoramaGuidanceState state = [engine updateWithYaw:1.80 pitch:0.0 roll:0.0 timestamp:2.0];
    XCTAssertTrue(state.shouldFinishCapture);
}

@end
```

- [ ] **Step 2: Run only the guidance tests to verify they fail**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test -only-testing:CaptureDemoTests/CDPanoramaGuidanceEngineTests`

Expected: FAIL because `CDPanoramaGuidanceEngine` and `CDPanoramaGuidanceState` are not implemented yet.

- [ ] **Step 3: Implement the minimal guidance engine**

```objc
// CDPanoramaGuidanceEngine.h
#import <Foundation/Foundation.h>

typedef struct {
    BOOL isCalibrating;
    BOOL shouldFinishCapture;
    CGFloat progress;
    __unsafe_unretained NSString *hintText;
    __unsafe_unretained NSString *statusText;
} CDPanoramaGuidanceState;

@interface CDPanoramaGuidanceEngine : NSObject
- (void)reset;
- (CDPanoramaGuidanceState)updateWithYaw:(CGFloat)yaw
                                   pitch:(CGFloat)pitch
                                    roll:(CGFloat)roll
                               timestamp:(CFTimeInterval)timestamp;
@end

// CDPanoramaGuidanceEngine.m
#import "CDPanoramaGuidanceEngine.h"

static const CGFloat kTargetYawDelta = 1.55;
static const CGFloat kFastSpeedThreshold = 0.85;
static const CGFloat kPitchThreshold = 0.28;
static const CGFloat kRollThreshold = 0.28;

@interface CDPanoramaGuidanceEngine ()
@property (nonatomic, assign) BOOL calibrated;
@property (nonatomic, assign) CGFloat startYaw;
@property (nonatomic, assign) CGFloat lastProgressYaw;
@property (nonatomic, assign) CFTimeInterval lastTimestamp;
@end

@implementation CDPanoramaGuidanceEngine

- (void)reset {
    self.calibrated = NO;
    self.startYaw = 0.0;
    self.lastProgressYaw = 0.0;
    self.lastTimestamp = 0.0;
}

- (CDPanoramaGuidanceState)updateWithYaw:(CGFloat)yaw
                                   pitch:(CGFloat)pitch
                                    roll:(CGFloat)roll
                               timestamp:(CFTimeInterval)timestamp {
    if (!self.calibrated) {
        self.calibrated = YES;
        self.startYaw = yaw;
        self.lastTimestamp = timestamp;
        return (CDPanoramaGuidanceState){ YES, NO, 0.0, @"保持准备", @"正在校准" };
    }

    CGFloat delta = MAX(0.0, yaw - self.startYaw);
    CGFloat progress = MIN(MAX(delta / kTargetYawDelta, 0.0), 1.0);
    CGFloat dt = MAX(0.016, timestamp - self.lastTimestamp);
    CGFloat speed = fabs((delta - self.lastProgressYaw) / dt);
    self.lastTimestamp = timestamp;
    self.lastProgressYaw = delta;

    NSString *hint = @"沿中线向右移动";
    NSString *status = @"继续缓慢移动";
    if (fabs(pitch) > kPitchThreshold) {
        hint = pitch > 0 ? @"请稍微压低手机" : @"请稍微抬高手机";
        status = @"调整竖直角度";
    } else if (fabs(roll) > kRollThreshold) {
        hint = @"请保持手机竖直";
        status = @"调整手机姿态";
    } else if (speed > kFastSpeedThreshold) {
        hint = @"移动太快，请放慢";
        status = @"请放慢移动速度";
    }

    return (CDPanoramaGuidanceState){ NO, delta >= kTargetYawDelta, progress, hint, status };
}

@end
```

- [ ] **Step 4: Re-run the guidance tests**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test -only-testing:CaptureDemoTests/CDPanoramaGuidanceEngineTests`

Expected: PASS

- [ ] **Step 5: Commit the guidance engine**

```bash
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo add ViewControllers/PanoramaCamera/CDPanoramaGuidanceEngine.h ViewControllers/PanoramaCamera/CDPanoramaGuidanceEngine.m CaptureDemoTests/CDPanoramaGuidanceEngineTests.m project.yml
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo commit -m "Add panorama guidance engine"
```

### Task 3: Build The Progress-Driven Frame Selector With TDD

**Files:**
- Create: `ViewControllers/PanoramaCamera/CDPanoramaFrameSelector.h`
- Create: `ViewControllers/PanoramaCamera/CDPanoramaFrameSelector.m`
- Test: `CaptureDemoTests/CDPanoramaFrameSelectorTests.m`

- [ ] **Step 1: Write failing tests for dead zone, spacing, and minimum frame count**

```objc
#import <XCTest/XCTest.h>
#import "CDPanoramaFrameSelector.h"

@interface CDPanoramaFrameSelectorTests : XCTestCase
@end

@implementation CDPanoramaFrameSelectorTests

- (void)testSelectorRejectsFramesInsideInitialDeadZone {
    CDPanoramaFrameSelector *selector = [[CDPanoramaFrameSelector alloc] init];
    XCTAssertFalse([selector shouldAcceptFrameAtProgress:0.01]);
}

- (void)testSelectorAcceptsFrameAfterProgressAdvances {
    CDPanoramaFrameSelector *selector = [[CDPanoramaFrameSelector alloc] init];
    XCTAssertTrue([selector shouldAcceptFrameAtProgress:0.08]);
    XCTAssertFalse([selector shouldAcceptFrameAtProgress:0.10]);
    XCTAssertTrue([selector shouldAcceptFrameAtProgress:0.17]);
}

- (void)testSelectorRequiresMinimumAcceptedFrames {
    CDPanoramaFrameSelector *selector = [[CDPanoramaFrameSelector alloc] init];
    [selector shouldAcceptFrameAtProgress:0.08];
    [selector shouldAcceptFrameAtProgress:0.17];
    XCTAssertFalse(selector.hasEnoughFramesForPanorama);
}

@end
```

- [ ] **Step 2: Run frame-selector tests to confirm failure**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test -only-testing:CaptureDemoTests/CDPanoramaFrameSelectorTests`

Expected: FAIL because the selector does not exist yet.

- [ ] **Step 3: Implement the minimal progress-driven selector**

```objc
// CDPanoramaFrameSelector.h
#import <Foundation/Foundation.h>

@interface CDPanoramaFrameSelector : NSObject
@property (nonatomic, readonly) NSUInteger acceptedFrameCount;
@property (nonatomic, readonly) BOOL hasEnoughFramesForPanorama;
- (void)reset;
- (BOOL)shouldAcceptFrameAtProgress:(CGFloat)progress;
@end

// CDPanoramaFrameSelector.m
#import "CDPanoramaFrameSelector.h"

static const CGFloat kInitialDeadZone = 0.03;
static const CGFloat kProgressSpacing = 0.08;
static const NSUInteger kMinimumFrameCount = 6;

@interface CDPanoramaFrameSelector ()
@property (nonatomic, assign) CGFloat lastAcceptedProgress;
@property (nonatomic, assign) NSUInteger acceptedFrameCount;
@end

@implementation CDPanoramaFrameSelector

- (void)reset {
    self.lastAcceptedProgress = 0.0;
    self.acceptedFrameCount = 0;
}

- (BOOL)hasEnoughFramesForPanorama {
    return self.acceptedFrameCount >= kMinimumFrameCount;
}

- (BOOL)shouldAcceptFrameAtProgress:(CGFloat)progress {
    if (progress < kInitialDeadZone) {
        return NO;
    }
    if (self.acceptedFrameCount > 0 && (progress - self.lastAcceptedProgress) < kProgressSpacing) {
        return NO;
    }

    self.lastAcceptedProgress = progress;
    self.acceptedFrameCount += 1;
    return YES;
}

@end
```

- [ ] **Step 4: Re-run the selector tests**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test -only-testing:CaptureDemoTests/CDPanoramaFrameSelectorTests`

Expected: PASS

- [ ] **Step 5: Commit the frame selector**

```bash
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo add ViewControllers/PanoramaCamera/CDPanoramaFrameSelector.h ViewControllers/PanoramaCamera/CDPanoramaFrameSelector.m CaptureDemoTests/CDPanoramaFrameSelectorTests.m
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo commit -m "Add panorama frame selector"
```

### Task 4: Replace Narrow-Strip Stitching With Overlap Stitching

**Files:**
- Create: `ViewControllers/PanoramaCamera/CDPanoramaComposer.h`
- Create: `ViewControllers/PanoramaCamera/CDPanoramaComposer.m`
- Test: `CaptureDemoTests/CDPanoramaComposerTests.m`

- [ ] **Step 1: Write failing stitcher tests for output continuity and minimum frame usage**

```objc
#import <XCTest/XCTest.h>
#import "CDPanoramaComposer.h"

@interface CDPanoramaComposerTests : XCTestCase
@end

@implementation CDPanoramaComposerTests

- (UIImage *)imageWithColor:(UIColor *)color size:(CGSize)size {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:size];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [color setFill];
        [context fillRect:CGRectMake(0, 0, size.width, size.height)];
    }];
}

- (void)testComposerReturnsNilWithoutFrames {
    CDPanoramaComposer *composer = [[CDPanoramaComposer alloc] init];
    XCTAssertNil([composer buildPanoramaImage]);
}

- (void)testComposerBuildsPanoramaWiderThanSingleFrame {
    CDPanoramaComposer *composer = [[CDPanoramaComposer alloc] init];
    [composer appendFrameImage:[self imageWithColor:UIColor.redColor size:CGSizeMake(360, 640)]];
    [composer appendFrameImage:[self imageWithColor:UIColor.greenColor size:CGSizeMake(360, 640)]];
    [composer appendFrameImage:[self imageWithColor:UIColor.blueColor size:CGSizeMake(360, 640)]];

    UIImage *image = [composer buildPanoramaImage];
    XCTAssertNotNil(image);
    XCTAssertGreaterThan(image.size.width, 360.0);
}

@end
```

- [ ] **Step 2: Run stitcher tests to confirm failure**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test -only-testing:CaptureDemoTests/CDPanoramaComposerTests`

Expected: FAIL because the composer does not exist yet.

- [ ] **Step 3: Implement the overlap-based stitcher**

```objc
// CDPanoramaComposer.h
#import <UIKit/UIKit.h>

@interface CDPanoramaComposer : NSObject
- (void)reset;
- (BOOL)appendFrameImage:(UIImage *)image;
- (nullable UIImage *)buildPanoramaImage;
@end

// CDPanoramaComposer.m
#import "CDPanoramaComposer.h"

static const CGFloat kWorkingWidth = 360.0;
static const CGFloat kWorkingHeight = 640.0;
static const CGFloat kVisibleSliceWidth = 120.0;
static const CGFloat kOverlapWidth = 32.0;

@interface CDPanoramaComposer ()
@property (nonatomic, strong) NSMutableArray<UIImage *> *frames;
@end

@implementation CDPanoramaComposer

- (instancetype)init {
    self = [super init];
    if (self) {
        _frames = [NSMutableArray array];
    }
    return self;
}

- (void)reset {
    [self.frames removeAllObjects];
}

- (BOOL)appendFrameImage:(UIImage *)image {
    if (!image) {
        return NO;
    }
    [self.frames addObject:image];
    return YES;
}

- (UIImage *)buildPanoramaImage {
    if (self.frames.count == 0) {
        return nil;
    }

    CGFloat stride = kVisibleSliceWidth - kOverlapWidth;
    CGFloat width = kVisibleSliceWidth + MAX(0, ((NSInteger)self.frames.count - 1)) * stride;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(width, kWorkingHeight)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        CGFloat x = 0.0;
        for (UIImage *frame in self.frames) {
            CGRect sourceRect = CGRectMake((frame.size.width - kVisibleSliceWidth) / 2.0, 0, kVisibleSliceWidth, MIN(frame.size.height, kWorkingHeight));
            CGImageRef source = CGImageCreateWithImageInRect(frame.CGImage, CGRectMake(sourceRect.origin.x * frame.scale,
                                                                                      sourceRect.origin.y * frame.scale,
                                                                                      sourceRect.size.width * frame.scale,
                                                                                      sourceRect.size.height * frame.scale));
            UIImage *slice = [UIImage imageWithCGImage:source scale:frame.scale orientation:UIImageOrientationUp];
            CGImageRelease(source);
            [slice drawInRect:CGRectMake(x, 0, kVisibleSliceWidth, kWorkingHeight) blendMode:kCGBlendModeNormal alpha:1.0];
            x += stride;
        }
    }];
}

@end
```

- [ ] **Step 4: Re-run stitcher tests**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test -only-testing:CaptureDemoTests/CDPanoramaComposerTests`

Expected: PASS

- [ ] **Step 5: Commit the new stitcher**

```bash
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo add ViewControllers/PanoramaCamera/CDPanoramaComposer.h ViewControllers/PanoramaCamera/CDPanoramaComposer.m CaptureDemoTests/CDPanoramaComposerTests.m
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo commit -m "Add overlap-based panorama composer"
```

### Task 5: Integrate Camera, Motion, Orientation, And Result Flow

**Files:**
- Modify: `ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.m`
- Create: `ViewControllers/PanoramaCamera/CDPanoramaFrameNormalizer.h`
- Create: `ViewControllers/PanoramaCamera/CDPanoramaFrameNormalizer.m`
- Modify: `CaptureDemo/Info.plist`

- [ ] **Step 1: Write a failing controller-level test for state transitions if the project can host a lightweight logic test; otherwise document the manual check and proceed**

```objc
- (void)testIdleToCapturingToProcessingStateTransitions {
    CDPanoramaCameraViewController *controller = [[CDPanoramaCameraViewController alloc] init];
    XCTAssertEqual(controller.captureState, CDPanoramaCaptureStateIdle);
}
```

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test`

Expected: Either a failing logic assertion for missing state exposure or a note that controller hardware wiring will be verified manually instead.

- [ ] **Step 2: Add a frame normalizer that fixes orientation once**

```objc
// CDPanoramaFrameNormalizer.h
#import <UIKit/UIKit.h>
#import <CoreMedia/CoreMedia.h>

@interface CDPanoramaFrameNormalizer : NSObject
- (instancetype)initWithCIContext:(CIContext *)ciContext;
- (nullable UIImage *)portraitImageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer;
@end

// CDPanoramaFrameNormalizer.m
#import "CDPanoramaFrameNormalizer.h"
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

@interface CDPanoramaFrameNormalizer ()
@property (nonatomic, strong) CIContext *ciContext;
@end

@implementation CDPanoramaFrameNormalizer

- (instancetype)initWithCIContext:(CIContext *)ciContext {
    self = [super init];
    if (self) {
        _ciContext = ciContext;
    }
    return self;
}

- (UIImage *)portraitImageFromSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) {
        return nil;
    }

    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    ciImage = [ciImage imageByApplyingOrientation:kCGImagePropertyOrientationRight];
    CGImageRef cgImage = [self.ciContext createCGImage:ciImage fromRect:CGRectIntegral(ciImage.extent)];
    if (!cgImage) {
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:cgImage scale:[UIScreen mainScreen].scale orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return image;
}

@end
```

- [ ] **Step 3: Integrate guidance engine, selector, normalizer, and composer into the controller**

```objc
@property (nonatomic, strong) CDPanoramaGuidanceEngine *guidanceEngine;
@property (nonatomic, strong) CDPanoramaFrameSelector *frameSelector;
@property (nonatomic, strong) CDPanoramaFrameNormalizer *frameNormalizer;
@property (nonatomic, strong) CDPanoramaComposer *composer;

- (void)startPanoramaCapture {
    [self.guidanceEngine reset];
    [self.frameSelector reset];
    [self.composer reset];
    self.captureState = CDPanoramaCaptureStateCalibrating;
    [self startMotionTracking];
}

- (void)handleDeviceMotion:(CMDeviceMotion *)motion {
    CDPanoramaGuidanceState state = [self.guidanceEngine updateWithYaw:motion.attitude.yaw
                                                                 pitch:motion.attitude.pitch
                                                                  roll:motion.attitude.roll
                                                             timestamp:CACurrentMediaTime()];
    self.hintLabel.text = state.hintText;
    self.statusLabel.text = state.statusText;
    [self updateProgressUI:state.progress];

    if (state.isCalibrating) {
        return;
    }

    self.captureState = CDPanoramaCaptureStateCapturing;
    if (state.shouldFinishCapture) {
        [self finishPanoramaCapture];
    }
}

- (void)captureOutput:(AVCaptureOutput *)output
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection {
    if (self.captureState != CDPanoramaCaptureStateCapturing) {
        return;
    }

    CGFloat progress = self.currentProgress;
    if (![self.frameSelector shouldAcceptFrameAtProgress:progress]) {
        return;
    }

    UIImage *image = [self.frameNormalizer portraitImageFromSampleBuffer:sampleBuffer];
    [self.composer appendFrameImage:image];
}
```

- [ ] **Step 4: Add result-preview and save behavior**

```objc
- (void)finishPanoramaCapture {
    self.captureState = CDPanoramaCaptureStateProcessing;
    [self.motionManager stopDeviceMotionUpdates];

    if (!self.frameSelector.hasEnoughFramesForPanorama) {
        [self restoreIdleStateWithStatus:@"拍摄距离不足，请重拍" hint:@"请沿中线完整移动到终点"];
        return;
    }

    dispatch_async(self.captureQueue, ^{
        UIImage *panorama = [self.composer buildPanoramaImage];
        dispatch_async(dispatch_get_main_queue(), ^{
            if (!panorama) {
                [self restoreIdleStateWithStatus:@"全景生成失败，请重拍" hint:@"请保持稳定后重新拍摄"];
                return;
            }
            [self showResultImage:panorama];
            [self savePanoramaToPhotoLibrary:panorama];
        });
    });
}
```

- [ ] **Step 5: Build the app**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo -sdk iphonesimulator -configuration Debug build`

Expected: PASS

- [ ] **Step 6: Commit the integrated panorama flow**

```bash
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo add ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.m ViewControllers/PanoramaCamera/CDPanoramaFrameNormalizer.h ViewControllers/PanoramaCamera/CDPanoramaFrameNormalizer.m CaptureDemo/Info.plist
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo commit -m "Integrate panorama capture flow"
```

### Task 6: Verify On Device And Clean Up UX Details

**Files:**
- Modify: `ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.m`
- Test: manual device validation on the target iPhone

- [ ] **Step 1: Run the full unit-test suite**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodegen generate && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemoTests -sdk iphonesimulator -configuration Debug test`

Expected: PASS

- [ ] **Step 2: Install to device or simulator for smoke validation**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo -configuration Debug -destination 'platform=iOS,id=<DEVICE_ID>' build`

Expected: PASS on the target device.

- [ ] **Step 3: Perform manual device checks**

```text
1. Open the fourth tab and confirm the title is 全景相机.
2. Start capture in portrait orientation.
3. Verify the user can follow the fixed line and moving target point without explanation.
4. Verify moving too fast changes guidance text to a slowdown message.
5. Complete one full left-to-right sweep.
6. Confirm the result preview is horizontal panorama content with the correct portrait-derived orientation.
7. Confirm the result saves to Photos.
```

- [ ] **Step 4: Apply only the smallest UX fixes discovered during validation**

```objc
// Examples of acceptable small follow-up edits in the same task:
// - tighten hint copy
// - tune progress spacing threshold
// - adjust guide line vertical placement
// - tweak finish threshold
```

- [ ] **Step 5: Re-run app build after final polish**

Run: `cd /Users/ouyangqi/Desktop/RoomCaptureDemo && xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo -sdk iphonesimulator -configuration Debug build`

Expected: PASS

- [ ] **Step 6: Commit the validated panorama polish**

```bash
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo add ViewControllers/PanoramaCamera/CDPanoramaCameraViewController.m
git -C /Users/ouyangqi/Desktop/RoomCaptureDemo commit -m "Polish panorama camera experience"
```

---

## Self-Review

### Spec Coverage

- Fourth-tab panorama entry: covered in Task 1
- Native-like guidance line and moving target point: covered in Task 5 and Task 6
- Portrait-only left-to-right motion: covered in Task 2, Task 3, and Task 5
- Progress-driven frame admission: covered in Task 3 and Task 5
- Single orientation normalization path: covered in Task 5
- Replace narrow-strip output with wider overlap stitching: covered in Task 4
- Result preview and Photos save: covered in Task 5
- Real-device acceptance validation: covered in Task 6

### Placeholder Scan

- No `TODO`, `TBD`, or “similar to previous task” placeholders remain.
- The one controller-level test in Task 5 is explicitly marked as optional because hardware wiring may remain manual-validation-only; the plan already requires device validation in Task 6.

### Type Consistency

- `CDPanoramaGuidanceEngine`, `CDPanoramaFrameSelector`, `CDPanoramaFrameNormalizer`, and `CDPanoramaComposer` use the same names in file structure, code samples, and integration steps.
- The controller integration uses `CDPanoramaGuidanceState` consistently with the guidance-engine task.

