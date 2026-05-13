import XCTest
@testable import CaptureDemo

final class CD3DGSMetricsTests: XCTestCase {
    func test_translationTrafficLight_thresholds() {
        XCTAssertEqual(CD3DGSMetrics.translationTrafficLight(forRatio: 0.0), .green)
        XCTAssertEqual(CD3DGSMetrics.translationTrafficLight(forRatio: 0.299), .green)
        XCTAssertEqual(CD3DGSMetrics.translationTrafficLight(forRatio: 0.30), .yellow)
        XCTAssertEqual(CD3DGSMetrics.translationTrafficLight(forRatio: 0.60), .yellow)
        XCTAssertEqual(CD3DGSMetrics.translationTrafficLight(forRatio: 0.601), .red)
    }

    func test_rotationTrafficLight_thresholds() {
        XCTAssertEqual(CD3DGSMetrics.rotationTrafficLight(forDegreesPerSecond: 0.0), .green)
        XCTAssertEqual(CD3DGSMetrics.rotationTrafficLight(forDegreesPerSecond: 11.99), .green)
        XCTAssertEqual(CD3DGSMetrics.rotationTrafficLight(forDegreesPerSecond: 12.0), .yellow)
        XCTAssertEqual(CD3DGSMetrics.rotationTrafficLight(forDegreesPerSecond: 18.0), .yellow)
        XCTAssertEqual(CD3DGSMetrics.rotationTrafficLight(forDegreesPerSecond: 18.01), .red)
    }

    func test_translationAllowed_rotationGate() {
        XCTAssertTrue(CD3DGSMetrics.isTranslationEstimationAllowed(forRotationDegreesPerSecond: 0.0))
        XCTAssertTrue(CD3DGSMetrics.isTranslationEstimationAllowed(forRotationDegreesPerSecond: 29.99))
        XCTAssertFalse(CD3DGSMetrics.isTranslationEstimationAllowed(forRotationDegreesPerSecond: 30.0))
        XCTAssertFalse(CD3DGSMetrics.isTranslationEstimationAllowed(forRotationDegreesPerSecond: 60.0))
    }
}
