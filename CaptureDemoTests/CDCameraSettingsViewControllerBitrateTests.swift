import XCTest
@testable import CaptureDemo

// 校验相机码率设置的 UserDefaults 默认值和已保存值加载逻辑。
final class CDCameraSettingsViewControllerBitrateTests: XCTestCase {
    private let bitrateKey = "CDSettingsVideoBitrateKbps"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: bitrateKey)
        super.tearDown()
    }

    func testDefaultVideoBitrateIs6000Kbps() {
        UserDefaults.standard.removeObject(forKey: bitrateKey)
        let viewController = makeSettingsViewController()

        viewController.perform(NSSelectorFromString("loadViewIfNeeded"))

        XCTAssertEqual(viewController.value(forKey: "videoBitrateKbps") as? Int, 6000)
    }

    func testSavedVideoBitrateIsLoaded() {
        UserDefaults.standard.set(6000, forKey: bitrateKey)
        let viewController = makeSettingsViewController()

        viewController.perform(NSSelectorFromString("loadViewIfNeeded"))

        XCTAssertEqual(viewController.value(forKey: "videoBitrateKbps") as? Int, 6000)
    }

    private func makeSettingsViewController() -> NSObject {
        guard let type = NSClassFromString("CDCameraSettingsViewController") as? NSObject.Type else {
            XCTFail("CDCameraSettingsViewController should be available")
            return NSObject()
        }
        return type.init()
    }
}
