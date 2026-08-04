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
        XCTAssertEqual(sequence.positions[1].scnVector3Value.x,
                       2.5 * sin(.pi / 4),
                       accuracy: 0.0001)
    }

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
        XCTAssertTrue(sequence.updateCentered(true, timestamp: 2.8))
        XCTAssertEqual(sequence.currentIndex, 1)
    }

    func testCompletesAfterEighthPointWithoutOverflow() {
        let sequence = CDSpatialAimSequence(pointCount: 8, radius: 2.5, holdDuration: 0.8)

        for index in 0..<8 {
            let start = Double(index) * 2.0
            XCTAssertFalse(sequence.updateCentered(true, timestamp: start))
            XCTAssertTrue(sequence.updateCentered(true, timestamp: start + 0.8))
        }

        XCTAssertTrue(sequence.isComplete)
        XCTAssertEqual(sequence.currentIndex, 8)
        XCTAssertFalse(sequence.updateCentered(true, timestamp: 20.0))
    }
}
