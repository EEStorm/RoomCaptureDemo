# Session-Relative Spatial Aim Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the eight SceneKit aim points remain fixed in the camera-start session coordinate system while a stationary user rotates the phone through 360 degrees.

**Architecture:** Replace the absolute CoreMotion-to-SceneKit orientation plus yaw correction with a pure session-relative quaternion calculation. The overlay stores the first valid CoreMotion quaternion and applies `qInitial * inverse(qCurrent)` only to the SceneKit camera node; aim-node world coordinates remain unchanged.

**Tech Stack:** Objective-C, Swift XCTest, CoreMotion, SceneKit, Xcode/iOS Simulator

---

### Task 1: Specify session-relative quaternion behavior

**Files:**
- Modify: `CaptureDemoTests/ThreeDGSCapture/CDSpatialAimOverlayViewTests.swift`
- Modify: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.h`

- [ ] **Step 1: Replace absolute-orientation tests with failing relative-orientation tests**

Expose this pure calculation in the Objective-C header:

```objc
+ (SCNQuaternion)sceneOrientationForInitialCoreMotionQuaternion:(CMQuaternion)initialQuaternion
                                    currentCoreMotionQuaternion:(CMQuaternion)currentQuaternion;
```

Add a Swift quaternion multiplication helper and two tests. The first asserts identical initial/current attitudes produce identity. The second constructs a portrait initial attitude and a 45-degree device yaw, then asserts the returned SceneKit rotation is a 45-degree rotation around SceneKit Y:

```swift
private func multiply(_ lhs: CMQuaternion, _ rhs: CMQuaternion) -> CMQuaternion {
    CMQuaternion(
        x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
        y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
        z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
        w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
    )
}

func testInitialAttitudeProducesIdentityCameraOrientation() {
    let s = sqrt(0.5)
    let initial = CMQuaternion(x: -s, y: 0, z: 0, w: s)
    let result = CDSpatialAimOverlayView.sceneOrientation(
        forInitialCoreMotionQuaternion: initial,
        currentCoreMotionQuaternion: initial
    )
    XCTAssertEqual(result.x, 0, accuracy: 0.001)
    XCTAssertEqual(result.y, 0, accuracy: 0.001)
    XCTAssertEqual(result.z, 0, accuracy: 0.001)
    XCTAssertEqual(abs(result.w), 1, accuracy: 0.001)
}

func testPhoneYawProducesSessionCameraYaw() {
    let s = sqrt(0.5)
    let initial = CMQuaternion(x: -s, y: 0, z: 0, w: s)
    let halfYaw = Double.pi / 8
    let deviceYaw = CMQuaternion(x: 0, y: 0, z: -sin(halfYaw), w: cos(halfYaw))
    let current = multiply(initial, deviceYaw)
    let result = CDSpatialAimOverlayView.sceneOrientation(
        forInitialCoreMotionQuaternion: initial,
        currentCoreMotionQuaternion: current
    )
    XCTAssertEqual(result.x, 0, accuracy: 0.001)
    XCTAssertEqual(abs(result.y), Float(sin(halfYaw)), accuracy: 0.001)
    XCTAssertEqual(result.z, 0, accuracy: 0.001)
    XCTAssertEqual(abs(result.w), Float(cos(halfYaw)), accuracy: 0.001)
}
```

- [ ] **Step 2: Run the overlay tests and verify RED**

Run:

```bash
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'platform=iOS Simulator,id=21C02B03-A906-44E6-A938-36A77EE29D88' \
  -only-testing:CaptureDemoTests/CDSpatialAimOverlayViewTests test -quiet
```

Expected: build or tests fail because the new relative-orientation selector is not implemented.

### Task 2: Implement the session-relative camera transform

**Files:**
- Modify: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.h`
- Modify: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.m`
- Test: `CaptureDemoTests/ThreeDGSCapture/CDSpatialAimOverlayViewTests.swift`

- [ ] **Step 1: Add normalized quaternion inversion**

Add helpers beside `CDQuaternionMultiply`:

```objc
static SCNQuaternion CDQuaternionNormalize(SCNQuaternion quaternion) {
    float length = sqrtf(quaternion.x * quaternion.x + quaternion.y * quaternion.y +
                         quaternion.z * quaternion.z + quaternion.w * quaternion.w);
    if (length <= FLT_EPSILON) {
        return SCNVector4Make(0, 0, 0, 1);
    }
    return SCNVector4Make(quaternion.x / length, quaternion.y / length,
                          quaternion.z / length, quaternion.w / length);
}

static SCNQuaternion CDQuaternionInverse(SCNQuaternion quaternion) {
    SCNQuaternion normalized = CDQuaternionNormalize(quaternion);
    return SCNVector4Make(-normalized.x, -normalized.y, -normalized.z, normalized.w);
}
```

- [ ] **Step 2: Implement the pure relative-orientation method**

Replace the old single-quaternion conversion method with:

```objc
+ (SCNQuaternion)sceneOrientationForInitialCoreMotionQuaternion:(CMQuaternion)initialQuaternion
                                    currentCoreMotionQuaternion:(CMQuaternion)currentQuaternion {
    SCNQuaternion initial = CDQuaternionNormalize(SCNVector4Make((float)initialQuaternion.x,
                                                                  (float)initialQuaternion.y,
                                                                  (float)initialQuaternion.z,
                                                                  (float)initialQuaternion.w));
    SCNQuaternion current = CDQuaternionNormalize(SCNVector4Make((float)currentQuaternion.x,
                                                                  (float)currentQuaternion.y,
                                                                  (float)currentQuaternion.z,
                                                                  (float)currentQuaternion.w));
    return CDQuaternionNormalize(CDQuaternionMultiply(initial, CDQuaternionInverse(current)));
}
```

- [ ] **Step 3: Store the first valid quaternion and remove yaw correction**

Replace `yawCorrectionRadians` with:

```objc
@property (nonatomic, assign) CMQuaternion initialCoreMotionQuaternion;
```

Update the motion handler so the first sample establishes the session reference and every sample updates only the camera:

```objc
if (!self.hasValidAttitude) {
    self.initialCoreMotionQuaternion = quaternion;
    self.hasValidAttitude = YES;
    self.hidden = !self.isRendering;
}
self.cameraNode.orientation = [CDSpatialAimOverlayView
    sceneOrientationForInitialCoreMotionQuaternion:self.initialCoreMotionQuaternion
    currentCoreMotionQuaternion:quaternion];
```

`resetAttitudeCalibration` must reset `initialCoreMotionQuaternion` to `{0, 0, 0, 1}` while retaining its existing behavior: clear `hasValidAttitude`, hide the overlay, reset the camera to identity, and preserve the current sequence index.

- [ ] **Step 4: Run overlay tests and verify GREEN**

Run the Task 1 test command.

Expected: all `CDSpatialAimOverlayViewTests` pass.

- [ ] **Step 5: Run all spatial-aim tests**

Run:

```bash
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'platform=iOS Simulator,id=21C02B03-A906-44E6-A938-36A77EE29D88' \
  -only-testing:CaptureDemoTests/CDSpatialAimSequenceTests \
  -only-testing:CaptureDemoTests/CDMotionTrackingServiceTests \
  -only-testing:CaptureDemoTests/CDSpatialAimOverlayViewTests test -quiet
```

Expected: all spatial-aim tests pass with zero failures.

- [ ] **Step 6: Commit the fix**

```bash
git add CaptureDemoTests/ThreeDGSCapture/CDSpatialAimOverlayViewTests.swift \
  ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.h \
  ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.m
git commit -m "fix: anchor spatial aims to initial attitude"
```

### Task 3: Verify integration and regressions

**Files:**
- Verify: `ViewControllers/ThreeDGSCapture/CD3DGSCaptureViewController.m`
- Verify: `ViewControllers/ThreeDGSCapture/CDSpatialAimSequence.m`

- [ ] **Step 1: Confirm only the camera orientation changes during motion updates**

Run:

```bash
rg -n "cameraNode.orientation|aimRootNode.(orientation|transform)|node.position" \
  ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.m
```

Expected: motion updates assign `cameraNode.orientation`; `aimRootNode` has no orientation/transform assignment; aim positions are assigned only during node construction.

- [ ] **Step 2: Build the app**

Run:

```bash
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'generic/platform=iOS Simulator' build -quiet
```

Expected: exit code 0. Existing unrelated warnings are acceptable.

- [ ] **Step 3: Run the full suite and compare with the known baseline**

Run:

```bash
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'platform=iOS Simulator,id=21C02B03-A906-44E6-A938-36A77EE29D88' test -quiet
```

Expected: no new failures. The known baseline may still contain the three blur-monitor failures and `CDCameraSettingsViewControllerBitrateTests/testDefaultVideoBitrateIs6000Kbps`.

- [ ] **Step 4: Inspect the final worktree**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors. Preserve the pre-existing uncommitted `CaptureDemo.xcodeproj/project.pbxproj` and untracked `CaptureDemoTests/CDCameraSettingsViewControllerBitrateTests.swift`; do not stage either file.
