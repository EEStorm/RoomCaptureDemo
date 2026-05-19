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
            rollWarningActive: true
        )

        XCTAssertEqual(text, "请保持手机水平")
    }
}
