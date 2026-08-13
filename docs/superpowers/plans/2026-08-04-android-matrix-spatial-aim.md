# Android Matrix Spatial Aim Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the failed relative-quaternion camera logic with the matrix pipeline used by Android `PhonePanoActivity`.

**Architecture:** Convert each CoreMotion attitude to a sensor matrix, post-multiply the portrait `Rx(90°)` correction and one-time horizontal `Ry(phi)` correction, invert the view matrix, and assign it to the SceneKit camera. World-space aim nodes never receive motion transforms.

**Tech Stack:** Objective-C, Swift XCTest, CoreMotion, SceneKit, GLKit math, Xcode

---

### Task 1: Specify the Android matrix behavior

**Files:**
- Modify: `CaptureDemoTests/ThreeDGSCapture/CDSpatialAimOverlayViewTests.swift`
- Modify: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.h`

- [ ] Replace quaternion component tests with a test API accepting initial/current `CMQuaternion` values and returning `SCNMatrix4` through the Android matrix chain.
- [ ] Add a behavioral test that converts point zero into camera coordinates and expects its initial X coordinate to be zero.
- [ ] Add a behavioral test using `current = initial × Rz(-45°)` and expect point zero's camera-space absolute X coordinate to exceed 1 meter.
- [ ] Run the two new tests and verify RED because the matrix API is not implemented.

Run:

```bash
xcodebuild -project CaptureDemo.xcodeproj -scheme CaptureDemo \
  -destination 'platform=iOS Simulator,id=21C02B03-A906-44E6-A938-36A77EE29D88' \
  -only-testing:CaptureDemoTests/CDSpatialAimOverlayViewTests test -quiet
```

### Task 2: Implement the Android matrix chain

**Files:**
- Modify: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.h`
- Modify: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.m`
- Test: `CaptureDemoTests/ThreeDGSCapture/CDSpatialAimOverlayViewTests.swift`

- [ ] Add pure helpers for quaternion normalization, quaternion-to-matrix conversion, matrix inversion validation, and the Android first-frame yaw correction.
- [ ] Implement `sensor × Rx90 × C`, then return its inverse as the SceneKit camera transform.
- [ ] Replace `initialCoreMotionQuaternion` with the one-time yaw-correction matrix and validity flag.
- [ ] Make `updateWithDeviceMotion:` use `motion.attitude.quaternion` to build the same sensor matrix used by the pure test helper, then assign only `cameraNode.transform`.
- [ ] Keep `updateWithCoreMotionQuaternion:` as the testable input boundary, but route it through the same matrix implementation.
- [ ] Reset calibration to identity and keep the existing generation guard for queued background updates.
- [ ] Run overlay tests and verify GREEN.

### Task 3: Verify integration

**Files:**
- Verify: `ViewControllers/ThreeDGSCapture/CDSpatialAimOverlayView.m`
- Verify: `ViewControllers/ThreeDGSCapture/CD3DGSCaptureViewController.m`

- [ ] Run all spatial tests and confirm zero failures.
- [ ] Build the simulator target and confirm exit code 0.
- [ ] Run `git diff --check`, confirm HEAD remains `c0d704c`, and confirm `git diff --cached --name-only` is empty.
- [ ] Do not stage or commit any file.
