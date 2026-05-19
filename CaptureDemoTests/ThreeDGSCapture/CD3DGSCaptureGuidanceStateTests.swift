import XCTest
@testable import CaptureDemo

final class CD3DGSCaptureGuidanceStateTests: XCTestCase {
    func test_stepNavigation_updatesInstructionAndButtonAvailability() {
        let state = makeState()

        XCTAssertEqual(state.value(forKey: "currentInstruction") as? String, "第一步：空间环绕扫描")
        XCTAssertEqual(state.value(forKey: "canMoveToPreviousStep") as? Bool, false)
        XCTAssertEqual(state.value(forKey: "canMoveToNextStep") as? Bool, true)

        _ = state.perform(NSSelectorFromString("moveToNextStep"))

        XCTAssertEqual(state.value(forKey: "currentInstruction") as? String, "第二步：全域推进拍摄")
        XCTAssertEqual(state.value(forKey: "canMoveToPreviousStep") as? Bool, true)
        XCTAssertEqual(state.value(forKey: "canMoveToNextStep") as? Bool, true)

        _ = state.perform(NSSelectorFromString("moveToPreviousStep"))

        XCTAssertEqual(state.value(forKey: "currentInstruction") as? String, "第一步：空间环绕扫描")
        XCTAssertEqual(state.value(forKey: "canMoveToPreviousStep") as? Bool, false)
    }

    func test_stepNavigation_staysWithinBounds() {
        let state = makeState()

        _ = state.perform(NSSelectorFromString("moveToPreviousStep"))
        XCTAssertEqual(state.value(forKey: "currentInstruction") as? String, "第一步：空间环绕扫描")

        _ = state.perform(NSSelectorFromString("moveToNextStep"))
        _ = state.perform(NSSelectorFromString("moveToNextStep"))
        _ = state.perform(NSSelectorFromString("moveToNextStep"))
        _ = state.perform(NSSelectorFromString("moveToNextStep"))

        XCTAssertEqual(state.value(forKey: "currentInstruction") as? String, "第四步：关键物品细节拍摄")
        XCTAssertEqual(state.value(forKey: "canMoveToNextStep") as? Bool, false)
    }

    func test_completingSteps_recordsVideoAndAutoAdvancesUntilComplete() {
        let state = makeState()
        let urls = [
            URL(fileURLWithPath: "/tmp/step1.mp4"),
            URL(fileURLWithPath: "/tmp/step2.mp4"),
            URL(fileURLWithPath: "/tmp/step3.mp4"),
            URL(fileURLWithPath: "/tmp/step4.mp4")
        ]

        for index in 0..<3 {
            _ = state.perform(NSSelectorFromString("completeCurrentStepWithVideoURL:"), with: urls[index])
            XCTAssertEqual(state.value(forKey: "currentStepIndex") as? Int, index + 1)
            XCTAssertEqual(state.value(forKey: "isComplete") as? Bool, false)
        }

        _ = state.perform(NSSelectorFromString("completeCurrentStepWithVideoURL:"), with: urls[3])

        XCTAssertEqual(state.value(forKey: "isComplete") as? Bool, true)
        XCTAssertEqual(state.value(forKey: "completedVideoURLs") as? [URL], urls)
        XCTAssertEqual(state.value(forKey: "currentInstruction") as? String, "第四步：关键物品细节拍摄")
    }

    func test_eachStepProvidesGuideVideoResourceName() {
        let state = makeState()
        let resourceNames = ["step01", "step02", "step03", "step04"]

        for index in 0..<4 {
            XCTAssertEqual(state.value(forKey: "guideVideoResourceName") as? String, resourceNames[index])
            if index < 3 {
                _ = state.perform(NSSelectorFromString("moveToNextStep"))
            }
        }
    }

    func test_eachStepProvidesToastGuidanceText() {
        let state = makeState()
        let guidanceTexts = [
            "第一步，空间环绕扫描：分客厅、卧室依次进行。全程手机保持水平不晃动，镜头始终对准房间中心；沿墙边匀速平移，卧室拐角处停留2-3秒，保持镜头对准房间中心，完整扫描布局即可。",
            "第二步，分区纵深推进：手机保持水平不晃动，缓慢匀速推进，从区域一端沿可通行路线推至另一端；如遇障碍物缓慢调整方向，绕开障碍时镜头始终朝前，不遗漏任何区域。",
            "第三步，盲区补录+家具拍摄：盲区对准死角，手机平稳上下平移，每处拍3-5秒；家具以其为中心，缓慢环绕一周，拍摄正面、侧面及边角细节",
            "第四步，MR效果生成：拍摄完成后，系统自动同步数据、生成点云，前置校验是否满足重建要求"
        ]

        for index in 0..<4 {
            XCTAssertEqual(state.value(forKey: "currentToastText") as? String, guidanceTexts[index])
            if index < 3 {
                _ = state.perform(NSSelectorFromString("moveToNextStep"))
            }
        }
    }

    private func makeState() -> NSObject {
        guard let stateClass = NSClassFromString("CD3DGSCaptureGuidanceState") as? NSObject.Type else {
            XCTFail("CD3DGSCaptureGuidanceState should be available to drive capture guidance UI")
            return NSObject()
        }
        return stateClass.init()
    }
}
