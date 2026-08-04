# Android Matrix Spatial Aim Design

## Goal

Make the iOS 3DGS capture page use the same camera-transform model as Android `PhonePanoActivity`: eight aim nodes remain fixed in SceneKit world space while CoreMotion changes only the camera transform. The first point aligns with the camera's initial horizontal heading, and the remaining points stay at 45-degree intervals around the horizontal circle.

## Architecture

Discard the session-relative quaternion path. Each valid CoreMotion attitude is converted to a 4×4 sensor matrix. The overlay applies the Android matrix chain:

`view(t) = sensor(t) × Rx(90°) × C`

`cameraTransform(t) = inverse(view(t))`

`C = Ry(phi)` is computed once from the first valid frame. For the first frame, calculate `baseView = sensor(0) × Rx(90°)`, transform camera forward `(0, 0, -1, 0)` by `inverse(baseView)`, and calculate `phi = atan2(-forward.x, -forward.z)`. This removes only the initial horizontal heading; gravity-referenced pitch and roll remain intact, matching Android.

## Components

- `CDSpatialAimOverlayView` stores the first-frame yaw correction matrix and assigns the resulting matrix only to `cameraNode.transform`.
- `CDMotionTrackingService` continues delivering `CMDeviceMotion` at 60 Hz using `CMAttitudeReferenceFrameXArbitraryZVertical`.
- `aimRootNode` and all eight aim nodes remain children of the scene root and are never transformed in response to motion.
- The quaternion-only public test API and calibration state are replaced by a rotation-matrix camera-transform API.

## Interaction

- Only the current point is attached to `aimRootNode`.
- Centering it for 0.8 seconds advances to the next fixed point.
- No photo or video capture is triggered by an aim point.
- Reset clears both point progress and first-frame matrix calibration. Background/foreground recalibration keeps the existing point index.

## Validation

Tests verify that the first frame horizontally aligns point zero, a 45-degree sensor turn moves point zero out of camera center, a full turn returns it, invalid matrices do not calibrate, and motion updates never mutate aim-node transforms. The spatial test groups and simulator build must pass. Final behavior still requires a physical-device check because the simulator does not produce real CoreMotion attitude samples.

## Constraints

- No ARKit, camera-feature tracking, position tracking, magnetic north, or true north.
- No commits or staging; all changes remain local for the user.
