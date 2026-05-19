import XCTest
@testable import CaptureDemo

final class CD3DGSPitchCalibrationTests: XCTestCase {
    func test_pitchDegrees_fromGravity_usesSensorOnlyAndIgnoresCalibration() {
        let levelPitch = CD3DGSPitchCalibration.pitchDegrees(
            gravityX: 0,
            gravityY: -1,
            gravityZ: 0,
            interfaceOrientation: .portrait
        )

        let tiltedPitch = CD3DGSPitchCalibration.pitchDegrees(
            gravityX: 0,
            gravityY: -0.8660254,
            gravityZ: -0.5,
            interfaceOrientation: .portrait
        )

        XCTAssertEqual(levelPitch, 0.0, accuracy: 0.0001)
        XCTAssertLessThan(tiltedPitch, -20.0)
    }

    func test_pitchDegrees_usesPortraitAxis_evenIfDeviceOrientationChanges() {
        let portraitPitch = CD3DGSPitchCalibration.pitchDegrees(
            gravityX: 0,
            gravityY: -1,
            gravityZ: 0,
            interfaceOrientation: .portrait
        )

        let landscapePitch = CD3DGSPitchCalibration.pitchDegrees(
            gravityX: 0,
            gravityY: -1,
            gravityZ: 0,
            interfaceOrientation: .landscapeLeft
        )

        XCTAssertEqual(portraitPitch, landscapePitch, accuracy: 0.0001)
    }

    func test_rollDegrees_changesWithSideTilt() {
        let levelRoll = CD3DGSPitchCalibration.rollDegrees(
            gravityX: 0,
            gravityY: -1,
            gravityZ: 0,
            interfaceOrientation: .portrait
        )

        let rightTiltRoll = CD3DGSPitchCalibration.rollDegrees(
            gravityX: 0.5,
            gravityY: -0.8660254,
            gravityZ: 0,
            interfaceOrientation: .portrait
        )

        XCTAssertEqual(levelRoll, 0.0, accuracy: 0.0001)
        XCTAssertGreaterThan(rightTiltRoll, 20.0)
    }

    func test_rollDegrees_reachesNinetyWhenPhoneIsHorizontal() {
        let horizontalRoll = CD3DGSPitchCalibration.rollDegrees(
            gravityX: 1,
            gravityY: 0,
            gravityZ: 0,
            interfaceOrientation: .portrait
        )

        XCTAssertEqual(horizontalRoll, 90.0, accuracy: 0.0001)
    }

    func test_warningToastText_usesPitchPriorityOverRoll() {
        let text = CD3DGSPitchCalibration.warningToastText(
            pitchWarningActive: true,
            rollWarningActive: true,
            angularSpeedWarningActive: false
        )

        XCTAssertEqual(text, "请保持手机水平")
    }

    func test_laplacianVariance_isHigherForHighFrequencyPattern() {
        let width = 8
        let height = 8
        let bytesPerRow = 8
        let flat = Array(repeating: UInt8(128), count: width * height)
        var hardEdge: [UInt8] = []
        for y in 0..<height {
            for _ in 0..<width {
                hardEdge.append(y < height / 2 ? 0 : 255)
            }
        }

        let flatVariance = CD3DGSBlurMonitor.laplacianVariance(
            forLumaBytes: flat,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        )
        let hardEdgeVariance = CD3DGSBlurMonitor.laplacianVariance(
            forLumaBytes: hardEdge,
            width: width,
            height: height,
            bytesPerRow: bytesPerRow
        )

        XCTAssertEqual(flatVariance, 0.0, accuracy: 0.0001)
        XCTAssertGreaterThan(hardEdgeVariance, flatVariance)
    }

    func test_blurMonitor_requires_sustainedLowVarianceBeforeDeclaringBlur() {
        let monitor = CD3DGSBlurMonitor()

        XCTAssertEqual(monitor.update(withLaplacianVariance: 44.0), .clear)
        XCTAssertEqual(monitor.update(withLaplacianVariance: 19.0), .soft)
        XCTAssertEqual(monitor.update(withLaplacianVariance: 18.0), .blurry)
        XCTAssertEqual(monitor.update(withLaplacianVariance: 17.0), .blurry)
    }

    func test_blurMonitor_keepsModerateVarianceOutOfBlurryState() {
        let monitor = CD3DGSBlurMonitor()

        XCTAssertEqual(monitor.update(withLaplacianVariance: 80.0), .clear)
        XCTAssertEqual(monitor.update(withLaplacianVariance: 55.0), .clear)
        XCTAssertEqual(monitor.update(withLaplacianVariance: 40.0), .clear)
        XCTAssertEqual(monitor.update(withLaplacianVariance: 25.0), .soft)
    }
}
