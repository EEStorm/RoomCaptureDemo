import XCTest
import CoreMotion
import SceneKit
@testable import CaptureDemo

final class CDSpatialAimOverlayViewTests: XCTestCase {
    func testOverlayDefaultsDoNotInterceptCaptureControls() {
        let overlay = CDSpatialAimOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        XCTAssertFalse(overlay.isUserInteractionEnabled)
        XCTAssertTrue(overlay.isAdvancementEnabled)
        XCTAssertEqual(overlay.horizontalFieldOfView, 90, accuracy: 0.001)
    }

    func testCenterReticleStaysAtScreenCenter() {
        let overlay = CDSpatialAimOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        overlay.layoutIfNeeded()
        let reticle = overlay.value(forKey: "centerReticleView") as? UIView

        XCTAssertNotNil(reticle)
        XCTAssertEqual(reticle?.center.x ?? 0, 195, accuracy: 0.5)
        XCTAssertEqual(reticle?.center.y ?? 0, 422, accuracy: 0.5)
        XCTAssertFalse(reticle?.isUserInteractionEnabled ?? true)
    }

    func testTurningPhoneMovesInitialAimPointOutOfCameraCenter() {
        let overlay = CDSpatialAimOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        let cameraNode = overlay.value(forKey: "cameraNode") as! SCNNode
        let aimRootNode = overlay.value(forKey: "aimRootNode") as! SCNNode
        let aimNodes = overlay.value(forKey: "aimNodes") as! [SCNNode]
        let halfSqrt = sqrt(0.5)
        let initial = CMQuaternion(x: -halfSqrt, y: 0, z: 0, w: halfSqrt)
        let halfAngle = -Double.pi / 8
        let deviceYaw = CMQuaternion(x: 0, y: 0, z: sin(halfAngle), w: cos(halfAngle))
        let current = multiply(initial, deviceYaw)

        overlay.update(withCoreMotionQuaternion: initial)
        var cameraSpacePoint = cameraNode.convertPosition(aimNodes[0].position, from: aimRootNode)
        XCTAssertEqual(cameraSpacePoint.x, 0, accuracy: 0.001)

        overlay.update(withCoreMotionQuaternion: current)
        cameraSpacePoint = cameraNode.convertPosition(aimNodes[0].position, from: aimRootNode)

        XCTAssertGreaterThan(abs(cameraSpacePoint.x), 1.0)
        XCTAssertLessThan(cameraSpacePoint.z, -1.0)
    }

    func testAndroidMatrixPipelineAlignsInitialPointAndMovesItAfterDeviceYaw() {
        let halfSqrt = sqrt(0.5)
        let initialQuaternion = CMQuaternion(x: -halfSqrt, y: 0, z: 0, w: halfSqrt)
        let halfAngle = -Double.pi / 8
        let deviceYaw = CMQuaternion(x: 0, y: 0, z: sin(halfAngle), w: cos(halfAngle))
        let currentQuaternion = multiply(initialQuaternion, deviceYaw)
        let initial = rotationMatrix(initialQuaternion)
        let current = rotationMatrix(currentQuaternion)

        let initialTransform = CDSpatialAimOverlayView.cameraTransform(
            forInitialCoreMotionRotationMatrix: initial,
            currentCoreMotionRotationMatrix: initial
        )
        var cameraSpacePoint = cameraSpacePosition(
            of: SCNVector3(0, 0, -2.5),
            cameraTransform: initialTransform
        )
        XCTAssertEqual(cameraSpacePoint.x, 0, accuracy: 0.001)
        XCTAssertLessThan(cameraSpacePoint.z, -1.0)

        let turnedTransform = CDSpatialAimOverlayView.cameraTransform(
            forInitialCoreMotionRotationMatrix: initial,
            currentCoreMotionRotationMatrix: current
        )
        cameraSpacePoint = cameraSpacePosition(
            of: SCNVector3(0, 0, -2.5),
            cameraTransform: turnedTransform
        )
        XCTAssertGreaterThan(abs(cameraSpacePoint.x), 1.0)
        XCTAssertLessThan(cameraSpacePoint.z, -1.0)
    }

    func testAndroidMatrixPipelineReturnsToInitialViewAfterFullTurn() {
        let halfSqrt = sqrt(0.5)
        let initialQuaternion = CMQuaternion(x: -halfSqrt, y: 0, z: 0, w: halfSqrt)
        let fullTurn = CMQuaternion(x: 0, y: 0, z: -sin(Double.pi), w: cos(Double.pi))
        let currentQuaternion = multiply(initialQuaternion, fullTurn)

        let transform = CDSpatialAimOverlayView.cameraTransform(
            forInitialCoreMotionRotationMatrix: rotationMatrix(initialQuaternion),
            currentCoreMotionRotationMatrix: rotationMatrix(currentQuaternion)
        )
        let cameraSpacePoint = cameraSpacePosition(of: SCNVector3(0, 0, -2.5), cameraTransform: transform)

        XCTAssertEqual(cameraSpacePoint.x, 0, accuracy: 0.001)
        XCTAssertEqual(cameraSpacePoint.y, 0, accuracy: 0.001)
        XCTAssertEqual(cameraSpacePoint.z, -2.5, accuracy: 0.001)
    }

    func testOverlayWaitsForFirstAttitudeAndStopsDisplayLink() {
        let overlay = CDSpatialAimOverlayView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))

        overlay.startRendering()
        XCTAssertTrue(overlay.isRendering)
        XCTAssertFalse(overlay.hasValidAttitude)
        XCTAssertTrue(overlay.isHidden)

        overlay.update(withCoreMotionQuaternion: CMQuaternion(x: 0, y: 0, z: 0, w: 1))
        XCTAssertTrue(overlay.hasValidAttitude)
        XCTAssertFalse(overlay.isHidden)

        overlay.resetAttitudeCalibration()
        XCTAssertFalse(overlay.hasValidAttitude)
        XCTAssertTrue(overlay.isHidden)

        overlay.stopRendering()
        XCTAssertFalse(overlay.isRendering)
        XCTAssertTrue(overlay.isHidden)
    }

    func testInvalidInitialAttitudesDoNotCalibrateOrContaminateCamera() {
        let invalidQuaternions = [
            CMQuaternion(x: 0, y: 0, z: 0, w: 0),
            CMQuaternion(x: .nan, y: 0, z: 0, w: 1),
            CMQuaternion(x: .infinity, y: 0, z: 0, w: 1)
        ]

        for quaternion in invalidQuaternions {
            let overlay = CDSpatialAimOverlayView(frame: .zero)
            let cameraNode = overlay.value(forKey: "cameraNode") as! SCNNode
            overlay.startRendering()
            defer { overlay.stopRendering() }

            overlay.update(withCoreMotionQuaternion: quaternion)

            XCTAssertFalse(overlay.hasValidAttitude)
            XCTAssertTrue(overlay.isHidden)
            XCTAssertTrue(cameraNode.orientation.x.isFinite)
            XCTAssertTrue(cameraNode.orientation.y.isFinite)
            XCTAssertTrue(cameraNode.orientation.z.isFinite)
            XCTAssertTrue(cameraNode.orientation.w.isFinite)
        }
    }

    func testResetDiscardsBackgroundAttitudeUpdateQueuedBeforeReset() {
        XCTAssertTrue(Thread.isMainThread)
        let overlay = CDSpatialAimOverlayView(frame: .zero)
        let queued = DispatchSemaphore(value: 0)
        overlay.startRendering()
        defer { overlay.stopRendering() }

        DispatchQueue.global().async {
            overlay.update(withCoreMotionQuaternion: CMQuaternion(x: 0, y: 0, z: 0, w: 1))
            queued.signal()
        }
        XCTAssertEqual(queued.wait(timeout: .now() + 1), .success)

        overlay.resetAttitudeCalibration()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        XCTAssertFalse(overlay.hasValidAttitude)
        XCTAssertTrue(overlay.isHidden)
    }

    func testOverlayCapturesInitialAttitudeOnlyOnce() {
        let overlay = CDSpatialAimOverlayView(frame: .zero)
        let cameraNode = overlay.value(forKey: "cameraNode") as! SCNNode
        let aimRootNode = overlay.value(forKey: "aimRootNode") as! SCNNode
        let aimNodes = overlay.value(forKey: "aimNodes") as! [SCNNode]
        let halfSqrt = sqrt(0.5)
        let initial = CMQuaternion(x: -halfSqrt, y: 0, z: 0, w: halfSqrt)
        let halfAngle = -Double.pi / 8
        let deviceYaw = CMQuaternion(x: 0, y: 0, z: sin(halfAngle), w: cos(halfAngle))
        let current = multiply(initial, deviceYaw)

        overlay.update(withCoreMotionQuaternion: initial)
        var cameraSpacePoint = cameraNode.convertPosition(aimNodes[0].position, from: aimRootNode)
        XCTAssertEqual(cameraSpacePoint.x, 0, accuracy: 0.001)

        overlay.update(withCoreMotionQuaternion: current)
        cameraSpacePoint = cameraNode.convertPosition(aimNodes[0].position, from: aimRootNode)
        XCTAssertGreaterThan(abs(cameraSpacePoint.x), 1.0)

        overlay.update(withCoreMotionQuaternion: initial)
        cameraSpacePoint = cameraNode.convertPosition(aimNodes[0].position, from: aimRootNode)
        XCTAssertEqual(cameraSpacePoint.x, 0, accuracy: 0.001)
    }

    func testAttitudeCalibrationResetKeepsSequenceProgressButClearsInitialAttitude() {
        let overlay = CDSpatialAimOverlayView(frame: .zero)
        let sequence = overlay.value(forKey: "sequence") as! CDSpatialAimSequence
        let cameraNode = overlay.value(forKey: "cameraNode") as! SCNNode
        let aimRootNode = overlay.value(forKey: "aimRootNode") as! SCNNode
        let aimNodes = overlay.value(forKey: "aimNodes") as! [SCNNode]

        XCTAssertFalse(sequence.updateCentered(true, timestamp: 0.0))
        XCTAssertTrue(sequence.updateCentered(true, timestamp: 0.8))
        XCTAssertGreaterThan(sequence.currentIndex, 0)
        let progressedIndex = sequence.currentIndex

        overlay.resetAttitudeCalibration()
        XCTAssertEqual(sequence.currentIndex, progressedIndex)

        let halfSqrt = sqrt(0.5)
        let portraitNeutral = CMQuaternion(x: -halfSqrt, y: 0, z: 0, w: halfSqrt)
        let halfAngle = -Double.pi / 8
        let deviceYaw = CMQuaternion(x: 0, y: 0, z: sin(halfAngle), w: cos(halfAngle))
        let newInitial = multiply(portraitNeutral, deviceYaw)
        overlay.update(withCoreMotionQuaternion: newInitial)
        let cameraSpacePoint = cameraNode.convertPosition(aimNodes[0].position, from: aimRootNode)
        XCTAssertEqual(cameraSpacePoint.x, 0, accuracy: 0.001)

        overlay.reset()
        XCTAssertEqual(sequence.currentIndex, 0)
    }

    func testMotionUpdatesLeaveAimNodesAndRootTransformUnchanged() {
        let overlay = CDSpatialAimOverlayView(frame: .zero)
        let aimRootNode = overlay.value(forKey: "aimRootNode") as! SCNNode
        let aimNodesBefore = overlay.value(forKey: "aimNodes") as! [SCNNode]
        let aimNodeStatesBefore = aimNodesBefore.map { (position: $0.position, orientation: $0.orientation, transform: $0.transform) }
        let rootOrientationBefore = aimRootNode.orientation
        let rootTransformBefore = aimRootNode.transform
        let initial = CMQuaternion(x: 0, y: 0, z: 0, w: 1)
        let halfAngle = -Double.pi / 8
        let current = CMQuaternion(x: 0, y: 0, z: sin(halfAngle), w: cos(halfAngle))

        overlay.update(withCoreMotionQuaternion: initial)
        overlay.update(withCoreMotionQuaternion: current)

        let aimNodesAfter = overlay.value(forKey: "aimNodes") as! [SCNNode]
        XCTAssertEqual(aimNodesAfter.count, aimNodesBefore.count)
        for (index, node) in aimNodesAfter.enumerated() {
            XCTAssertTrue(node === aimNodesBefore[index])
            assertEqual(node.position, aimNodeStatesBefore[index].position)
            assertEqual(node.orientation, aimNodeStatesBefore[index].orientation)
            assertEqual(node.transform, aimNodeStatesBefore[index].transform)
        }
        assertEqual(aimRootNode.orientation, rootOrientationBefore)
        assertEqual(aimRootNode.transform, rootTransformBefore)
    }

    private func multiply(_ lhs: CMQuaternion, _ rhs: CMQuaternion) -> CMQuaternion {
        CMQuaternion(
            x: lhs.w * rhs.x + lhs.x * rhs.w + lhs.y * rhs.z - lhs.z * rhs.y,
            y: lhs.w * rhs.y - lhs.x * rhs.z + lhs.y * rhs.w + lhs.z * rhs.x,
            z: lhs.w * rhs.z + lhs.x * rhs.y - lhs.y * rhs.x + lhs.z * rhs.w,
            w: lhs.w * rhs.w - lhs.x * rhs.x - lhs.y * rhs.y - lhs.z * rhs.z
        )
    }

    private func rotationMatrix(_ quaternion: CMQuaternion) -> CMRotationMatrix {
        let x = quaternion.x
        let y = quaternion.y
        let z = quaternion.z
        let w = quaternion.w
        return CMRotationMatrix(
            m11: 1 - 2 * (y * y + z * z),
            m12: 2 * (x * y - z * w),
            m13: 2 * (x * z + y * w),
            m21: 2 * (x * y + z * w),
            m22: 1 - 2 * (x * x + z * z),
            m23: 2 * (y * z - x * w),
            m31: 2 * (x * z - y * w),
            m32: 2 * (y * z + x * w),
            m33: 1 - 2 * (x * x + y * y)
        )
    }

    private func cameraSpacePosition(of worldPosition: SCNVector3, cameraTransform: SCNMatrix4) -> SCNVector3 {
        let scene = SCNScene()
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.transform = cameraTransform
        scene.rootNode.addChildNode(camera)
        return camera.convertPosition(worldPosition, from: scene.rootNode)
    }

    private func assertEqual(_ actual: SCNVector3, _ expected: SCNVector3, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.001, file: file, line: line)
    }

    private func assertEqual(_ actual: SCNQuaternion, _ expected: SCNQuaternion, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.z, expected.z, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.w, expected.w, accuracy: 0.001, file: file, line: line)
    }

    private func assertEqual(_ actual: SCNMatrix4, _ expected: SCNMatrix4, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.m11, expected.m11, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m12, expected.m12, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m13, expected.m13, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m14, expected.m14, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m21, expected.m21, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m22, expected.m22, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m23, expected.m23, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m24, expected.m24, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m31, expected.m31, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m32, expected.m32, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m33, expected.m33, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m34, expected.m34, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m41, expected.m41, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m42, expected.m42, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m43, expected.m43, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(actual.m44, expected.m44, accuracy: 0.001, file: file, line: line)
    }
}
