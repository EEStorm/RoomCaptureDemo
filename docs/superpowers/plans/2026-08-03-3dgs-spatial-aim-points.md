# 3DGS Spatial Aim Points Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a non-AR SceneKit overlay to the 3DGS capture page that guides the user through eight sequential horizontal spatial directions without taking photos or controlling video recording.

**Architecture:** A page-owned `CDMotionTrackingService` is the only `CMMotionManager` owner and distributes 60Hz fused motion samples. `CDSpatialAimOverlayView` owns SceneKit rendering while a small testable `CDSpatialAimSequence` owns point generation and 800ms advancement state. The existing controller forwards the same samples to both the overlay and its current IMU warning calculations.

**Tech Stack:** Objective-C, SceneKit, CoreMotion, AVFoundation, XCTest/Swift tests, XcodeGen, xcodebuild

---

## File Structure

- Create `ViewControllers/ThreeDGSCapture/CDSpatialAimSequence.h`: public point-generation and hold-state API.
- Create `ViewControllers/ThreeDGSCapture/CDSpatialAimSequence.m`: deterministic point queue implementation with no UI lifecycle.
- Create `CaptureDemoTests/ThreeDGSCapture/CDSpatialAimSequenceTests.swift`: coordinates and hold-state regression tests.
- Create `Services/CDMotionTrackingService.h`: page-owned motion stream interface.
- Create `Services/CDMotionTrackingService.m`: one `CMMotionManager`, serial queue, 60Hz updates.
- Create `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.h`: transparent SceneKit overlay interface.
- Create `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.m`: camera orientation, point rendering, projection, animation and sequence advancement.
- Modify `ViewControllers/ThreeDGSCapture/CD3DGSCaptureViewController.m`: layer insertion, shared motion lifecycle and forwarding.
- Modify `CaptureDemo/Info.plist`: add the motion usage description.
- Modify `project.yml`: keep the generated Info.plist configuration consistent.
- Regenerate `CaptureDemo.xcodeproj` with XcodeGen after adding source files.

### Task 1: Test and implement the deterministic eight-point sequence

**Files:**
- Create: `CaptureDemoTests/ThreeDGSCapture/CDSpatialAimSequenceTests.swift`
- Create: `ViewControllers/ThreeDGSCapture/CDSpatialAimSequence.h`
- Create: `ViewControllers/ThreeDGSCapture/CDSpatialAimSequence.m`

- [ ] **Step 1: Write failing coordinate tests**

Create tests that import SceneKit and assert count, radius, height, first point and 45-degree spacing:

```swift
import XCTest
import SceneKit
@testable import CaptureDemo

final class CDSpatialAimSequenceTests: XCTestCase {
    func testEightHorizontalPointsStartInFrontAndStayOnRadius() {
        let sequence = CDSpatialAimSequence(pointCount: 8, radius: 2.5, holdDuration: 0.8)
        XCTAssertEqual(sequence.positions.count, 8)
        for value in sequence.positions {
            let point = value.scnVector3Value
            XCTAssertEqual(point.y, 0, accuracy: 0.0001)
            XCTAssertEqual(hypot(point.x, point.z), 2.5, accuracy: 0.0001)
        }
        XCTAssertEqual(sequence.positions[0].scnVector3Value.x, 0, accuracy: 0.0001)
        XCTAssertEqual(sequence.positions[0].scnVector3Value.z, -2.5, accuracy: 0.0001)
        XCTAssertEqual(sequence.positions[1].scnVector3Value.x, 2.5 * sin(.pi / 4), accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Regenerate the project and verify the new test fails**

Run:

```bash
xcodegen generate
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'platform=iOS Simulator,id=21C02B03-A906-44E6-A938-36A77EE29D88' \
  -only-testing:CaptureDemoTests/CDSpatialAimSequenceTests test
```

Expected: compilation fails because `CDSpatialAimSequence` does not exist.

- [ ] **Step 3: Implement point generation**

Expose this API:

```objc
@interface CDSpatialAimSequence : NSObject
@property (nonatomic, copy, readonly) NSArray<NSValue *> *positions;
@property (nonatomic, assign, readonly) NSInteger currentIndex;
@property (nonatomic, assign, readonly, getter=isComplete) BOOL complete;
- (instancetype)initWithPointCount:(NSInteger)pointCount
                            radius:(CGFloat)radius
                      holdDuration:(NSTimeInterval)holdDuration NS_DESIGNATED_INITIALIZER;
- (BOOL)updateCentered:(BOOL)centered timestamp:(NSTimeInterval)timestamp;
- (void)reset;
@end
```

Generate each `SCNVector3` with:

```objc
double yaw = 2.0 * M_PI * index / pointCount;
SCNVector3 point = SCNVector3Make(radius * sin(yaw), 0.0, -radius * cos(yaw));
```

- [ ] **Step 4: Run coordinate tests and verify they pass**

Run the Task 1 targeted command. Expected: all coordinate assertions pass.

- [ ] **Step 5: Write failing hold-state tests**

Add separate tests for insufficient duration, interrupted duration and final completion:

```swift
func testAdvancesOnlyAfterContinuousHoldDuration() {
    let sequence = CDSpatialAimSequence(pointCount: 8, radius: 2.5, holdDuration: 0.8)
    XCTAssertFalse(sequence.updateCentered(true, timestamp: 10.0))
    XCTAssertFalse(sequence.updateCentered(true, timestamp: 10.79))
    XCTAssertTrue(sequence.updateCentered(true, timestamp: 10.8))
    XCTAssertEqual(sequence.currentIndex, 1)
}

func testLeavingCenterResetsHoldTimer() {
    let sequence = CDSpatialAimSequence(pointCount: 8, radius: 2.5, holdDuration: 0.8)
    XCTAssertFalse(sequence.updateCentered(true, timestamp: 1.0))
    XCTAssertFalse(sequence.updateCentered(false, timestamp: 1.5))
    XCTAssertFalse(sequence.updateCentered(true, timestamp: 2.0))
    XCTAssertFalse(sequence.updateCentered(true, timestamp: 2.79))
}

func testCompletesAfterEighthPointWithoutOverflow() {
    let sequence = CDSpatialAimSequence(pointCount: 8, radius: 2.5, holdDuration: 0.8)
    for index in 0..<8 {
        let start = Double(index) * 2.0
        XCTAssertFalse(sequence.updateCentered(true, timestamp: start))
        XCTAssertTrue(sequence.updateCentered(true, timestamp: start + 0.8))
    }
    XCTAssertTrue(sequence.isComplete)
    XCTAssertFalse(sequence.updateCentered(true, timestamp: 20.0))
}
```

- [ ] **Step 6: Verify hold tests fail, implement the minimal state machine, then verify green**

Use a nullable/negative hold start timestamp. A false `centered` value clears it. Once elapsed time reaches `holdDuration`, increment `currentIndex`, set `complete` when it reaches `positions.count`, clear the timer and return `YES` exactly once.

- [ ] **Step 7: Commit the sequence and tests**

```bash
git add CaptureDemoTests/ThreeDGSCapture/CDSpatialAimSequenceTests.swift \
  ViewControllers/ThreeDGSCapture/CDSpatialAimSequence.h \
  ViewControllers/ThreeDGSCapture/CDSpatialAimSequence.m CaptureDemo.xcodeproj/project.pbxproj
git commit -m "feat: add spatial aim point sequence"
```

### Task 2: Add the single CoreMotion service

**Files:**
- Create: `Services/CDMotionTrackingService.h`
- Create: `Services/CDMotionTrackingService.m`

- [ ] **Step 1: Define the service API**

```objc
typedef void (^CDMotionTrackingUpdateHandler)(CMDeviceMotion *motion);

@interface CDMotionTrackingService : NSObject
@property (nonatomic, copy, nullable) CDMotionTrackingUpdateHandler updateHandler;
@property (nonatomic, assign, readonly, getter=isActive) BOOL active;
@property (nonatomic, assign, readonly) NSTimeInterval updateInterval;
- (void)start;
- (void)stop;
@end
```

- [ ] **Step 2: Implement one manager and one serial queue**

Initialize one `CMMotionManager`, set `deviceMotionUpdateInterval = 1.0 / 60.0`, and call:

```objc
[manager startDeviceMotionUpdatesUsingReferenceFrame:CMAttitudeReferenceFrameXArbitraryZVertical
                                              toQueue:queue
                                          withHandler:^(CMDeviceMotion *motion, NSError *error) {
    if (motion && !error && weakSelf.updateHandler) {
        weakSelf.updateHandler(motion);
    }
}];
```

Make repeated `start` and `stop` calls idempotent. Stop in `dealloc`.

- [ ] **Step 3: Run a compile-only build**

```bash
xcodegen generate
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'generic/platform=iOS Simulator' build
```

Expected: build succeeds with no errors originating from `CDMotionTrackingService`.

- [ ] **Step 4: Commit the service**

```bash
git add Services/CDMotionTrackingService.h Services/CDMotionTrackingService.m CaptureDemo.xcodeproj/project.pbxproj
git commit -m "feat: add shared motion tracking service"
```

### Task 3: Build the SceneKit overlay

**Files:**
- Create: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.h`
- Create: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.m`

- [ ] **Step 1: Define the narrow overlay API**

```objc
@interface CDSpatialAimOverlayView : UIView
@property (nonatomic, assign) CGFloat horizontalFieldOfView;
@property (nonatomic, assign, getter=isAdvancementEnabled) BOOL advancementEnabled;
- (void)updateWithDeviceMotion:(CMDeviceMotion *)motion;
- (void)reset;
- (void)startRendering;
- (void)stopRendering;
@end
```

- [ ] **Step 2: Create the transparent SceneKit scene**

Create an `SCNView` filling the component with clear background, `opaque = NO`, `userInteractionEnabled = NO`, a perspective camera at the origin and a root node for aim points. Set the camera projection direction to horizontal and update `fieldOfView` from `horizontalFieldOfView`.

- [ ] **Step 3: Create the eight queued nodes**

For every sequence position, create an `SCNPlane` with a programmatic circular `UIImage`, emission material, double-sided rendering and a billboard/look-at orientation toward the origin. Add only the node at `currentIndex` to the visible root.

- [ ] **Step 4: Apply relative CoreMotion orientation**

Store the first valid attitude as the session reference. For each sample, copy the attitude and call `multiplyByInverseOfAttitude:` with the reference. Convert the relative quaternion into SceneKit camera orientation using a portrait camera basis correction, and update the camera on the main thread. The first sample must produce the identity camera orientation so `(0, 0, -2.5)` is centered.

- [ ] **Step 5: Project and advance the current node**

In `renderer:updateAtTime:`, project the current node position with `projectPoint:`. Require `z` to be within the visible depth interval and its 2D distance from view center to be at most 28 points. Pass the result and `time` into `CDSpatialAimSequence`. When it advances, animate the visible node:

```objc
[node runAction:[SCNAction group:@[
    [SCNAction scaleTo:0.25 duration:0.18],
    [SCNAction fadeOutWithDuration:0.18]
]] completionHandler:^{
    dispatch_async(dispatch_get_main_queue(), ^{
        [node removeFromParentNode];
        [self revealCurrentNode];
    });
}];
```

Set an animation guard to prevent duplicate advancement. If `advancementEnabled == NO`, reset the in-progress hold by sending `centered = NO`.

- [ ] **Step 6: Compile the overlay and run sequence tests**

Run the generic simulator build and the Task 1 targeted test command. Expected: both succeed.

- [ ] **Step 7: Commit the overlay**

```bash
git add ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.h \
  ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.m CaptureDemo.xcodeproj/project.pbxproj
git commit -m "feat: render sequential SceneKit aim points"
```

### Task 4: Integrate the overlay and motion service into 3DGS capture

**Files:**
- Modify: `ViewControllers/ThreeDGSCapture/CD3DGSCaptureViewController.m`
- Modify: `CaptureDemo/Info.plist`
- Modify: `project.yml`

- [ ] **Step 1: Add controller properties and the overlay layer**

Import both new headers and add:

```objc
@property (nonatomic, strong) CDMotionTrackingService *motionTrackingService;
@property (nonatomic, strong) CDSpatialAimOverlayView *spatialAimOverlayView;
```

After `setupUI`, insert the transparent overlay above preview tag 100 and below `imuReservedContainerView`. Set its frame in `viewDidLayoutSubviews`.

- [ ] **Step 2: Replace the controller-owned CMMotionManager lifecycle**

Remove `motionManager` and `motionQueue` properties. In `viewWillAppear`, create/start the service, start overlay rendering and reset the point queue. In `viewWillDisappear`, clear the handler, stop the service and stop rendering.

The update block must always forward motion to the overlay and only run the existing pitch/roll/speed UI calculations when `shouldUpdateMotionGuidance` is true:

```objc
service.updateHandler = ^(CMDeviceMotion *motion) {
    [weakSelf.spatialAimOverlayView updateWithDeviceMotion:motion];
    if (![weakSelf shouldUpdateMotionGuidance]) return;
    // Existing pitch, roll, angular speed and movement calculations.
};
```

- [ ] **Step 3: Separate IMU UI visibility from sensor shutdown**

Change `startPitchMonitoringIfNeeded` to configure/show existing UI only; it must not start another manager. Change `stopPitchMonitoring` to reset/hide existing UI only; it must not stop `CDMotionTrackingService`.

Use the service interval for movement integration:

```objc
CGFloat dt = self.motionTrackingService.updateInterval > 0
    ? self.motionTrackingService.updateInterval
    : (1.0 / 60.0);
```

- [ ] **Step 4: Match the preview field of view**

After attaching `AVCaptureVideoPreviewLayer`, inspect its session inputs for `AVCaptureDeviceInput`, read `device.activeFormat.videoFieldOfView`, and assign a valid value to `spatialAimOverlayView.horizontalFieldOfView`.

- [ ] **Step 5: Pause advancement behind the guide video**

Set `advancementEnabled = NO` when guide video/countdown overlay becomes visible. Restore it when preparation finishes or is cancelled. This affects only sequence timing, not rendering or recording.

- [ ] **Step 6: Add motion privacy descriptions**

Add `NSMotionUsageDescription` with value `用于根据手机姿态显示空间拍摄引导点` to both `CaptureDemo/Info.plist` and the target `info.properties` section of `project.yml`.

- [ ] **Step 7: Regenerate and run integration verification**

```bash
xcodegen generate
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'generic/platform=iOS Simulator' build
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'platform=iOS Simulator,id=21C02B03-A906-44E6-A938-36A77EE29D88' \
  -only-testing:CaptureDemoTests/CDSpatialAimSequenceTests test
```

Expected: app build and all new sequence tests succeed.

- [ ] **Step 8: Commit integration**

```bash
git add ViewControllers/ThreeDGSCapture/CD3DGSCaptureViewController.m \
  CaptureDemo/Info.plist project.yml CaptureDemo.xcodeproj/project.pbxproj
git commit -m "feat: integrate spatial aim guidance into 3dgs capture"
```

### Task 5: Final regression and handoff

**Files:**
- Verify all files changed in Tasks 1-4.

- [ ] **Step 1: Run whitespace and status checks**

```bash
git diff --check
git status --short
```

Expected: no whitespace errors and only intentionally changed/untracked worktree files.

- [ ] **Step 2: Run the new targeted tests fresh**

Run the Task 4 targeted test command. Expected: all `CDSpatialAimSequenceTests` pass.

- [ ] **Step 3: Run a fresh full app build**

Run the Task 4 generic simulator build. Expected: exit code 0.

- [ ] **Step 4: Record existing full-suite failures without masking them**

Run the full `xcodebuild test` command. Compare failures to the baseline: the baseline has 18 passing and 4 failing tests in blur monitoring/variance and the untracked bitrate default test. No new failure may be introduced by this feature.

- [ ] **Step 5: Inspect the complete diff against the design**

Verify: one motion manager, no AR session usage, exactly eight points, sequential reveal, 800ms center hold, no photo call, no recording-state mutation, overlay below existing controls, motion stopped on page exit, and privacy text present.

- [ ] **Step 6: Prepare true-device verification notes**

Document that Simulator proves build/state behavior only. On device, verify first-point centering, yaw direction, FOV edge slip, 8-point closure, UI touch passthrough and unchanged recording behavior.
