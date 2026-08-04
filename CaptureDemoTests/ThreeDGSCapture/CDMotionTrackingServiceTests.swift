import XCTest
@testable import CaptureDemo

final class CDMotionTrackingServiceTests: XCTestCase {
    func testDefaultsToSixtyHertzAndStopIsIdempotent() {
        let service = CDMotionTrackingService()

        XCTAssertEqual(service.updateInterval, 1.0 / 60.0, accuracy: 0.000_001)
        service.stop()
        service.stop()
        XCTAssertFalse(service.isActive)
    }

    func testStopInvalidatesMotionGenerationForStaleHandlers() {
        let service = CDMotionTrackingService()
        let generationBeforeStop = motionGeneration(of: service)

        service.stop()

        XCTAssertEqual(motionGeneration(of: service), generationBeforeStop + 1)
    }

    private func motionGeneration(of service: CDMotionTrackingService) -> UInt {
        (service.value(forKey: "motionGeneration") as! NSNumber).uintValue
    }
}
