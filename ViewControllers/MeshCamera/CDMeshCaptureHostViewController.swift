import SwiftUI
import UIKit
import Combine

@objc(CDMeshCaptureHostViewController)
@objcMembers
final class CDMeshCaptureHostViewController: UIViewController {
    private var hostingController: UIHostingController<ContentView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let hostingController = UIHostingController(
            rootView: ContentView(
                onShowCaptureList: { [weak self] in
                    self?.showCaptureList()
                }
            )
        )
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    private func showCaptureList() {
        guard let listClass = NSClassFromString("CDMeshCaptureListViewController") as? UIViewController.Type else {
            return
        }
        let listViewController = listClass.init()
        navigationController?.pushViewController(listViewController, animated: true)
    }
}

@objc(CD3DGSMeshStepInlineCaptureViewController)
@objcMembers
final class CD3DGSMeshStepInlineCaptureViewController: UIViewController {
    static let didFinishNotificationName = "CD3DGSMeshStepCaptureDidFinishNotification"
    static let didBecomeReadyNotificationName = "CD3DGSMeshStepCaptureDidBecomeReadyNotification"
    static let videoURLUserInfoKey = "videoURL"

    private let model = CaptureSessionModel(generatesReviewOnStop: false)
    private let liveMeshPreviewStore = LiveMeshPreviewSceneStore()
    private var hostingController: UIHostingController<CD3DGSMeshStepInlineView>?
    private var cancellables = Set<AnyCancellable>()
    private var didNotifyReady = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        model.$lastCompletedVideoURL
            .compactMap { $0 }
            .sink { [weak self] videoURL in
                self?.finish(with: videoURL)
            }
            .store(in: &cancellables)

        let hostingController = UIHostingController(
            rootView: CD3DGSMeshStepInlineView(
                model: model,
                liveMeshPreviewStore: liveMeshPreviewStore,
                onFirstFrame: { [weak self] in
                    self?.notifyReadyIfNeeded()
                }
            )
        )
        hostingController.view.backgroundColor = .clear
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }

    func startRecording() {
        model.startRecording()
    }

    func stopRecording() {
        model.stopRecording()
    }

    func cancelRecording() {
        model.cancelRecording()
    }

    func isRecording() -> Bool {
        model.isRecording
    }

    private func finish(with videoURL: URL) {
        NotificationCenter.default.post(
            name: Notification.Name(Self.didFinishNotificationName),
            object: self,
            userInfo: [Self.videoURLUserInfoKey: videoURL]
        )
    }

    private func notifyReadyIfNeeded() {
        guard !didNotifyReady else { return }
        didNotifyReady = true
        NotificationCenter.default.post(
            name: Notification.Name(Self.didBecomeReadyNotificationName),
            object: self
        )
    }
}

private struct CD3DGSMeshStepInlineView: View {
    @ObservedObject var model: CaptureSessionModel
    @ObservedObject var liveMeshPreviewStore: LiveMeshPreviewSceneStore
    let onFirstFrame: () -> Void
    @State private var resetCounter = 0
    @State private var snapshotRequestCounter = 0
    @State private var meshExportRequestCounter = 0
    @State private var meshExportFolderPath: String?

    var body: some View {
        ZStack(alignment: .top) {
            ARSCNViewContainer(
                isMovingTooFast: $model.isMovingTooFast,
                isRecording: $model.isRecording,
                renderMode: $model.renderMode,
                renderResetCounter: $resetCounter,
                reviewSnapshotRequestCounter: $snapshotRequestCounter,
                reviewMeshExportRequestCounter: $meshExportRequestCounter,
                reviewMeshExportFolderPath: $meshExportFolderPath,
                liveMeshPreviewStore: liveMeshPreviewStore,
                showsMainMeshOverlay: true,
                onMotionUpdate: { linear, angular, tooFast in
                    model.handleMotion(linearSpeed: linear, angularSpeed: angular, isTooFast: tooFast)
                },
                onPointCloudStatsUpdate: { depthAvailable, count, max, rendered in
                    model.pointCloudDepthAvailable = depthAvailable
                    model.pointCloudPointCount = count
                    model.pointCloudMaxPoints = max
                    model.pointCloudRenderedCount = rendered
                },
                onPlaneCoverageStatsUpdate: { planeCount, ratio in
                    model.planeCoveragePlaneCount = planeCount
                    model.planeCoverageRatio = ratio
                },
                onSkyboxCoverageStatsUpdate: { ratio in
                    model.skyboxCoverageRatio = ratio
                },
                onFrameForRecording: { frame in
                    onFirstFrame()
                    model.handleFrameForRecording(frame)
                },
                onReviewSnapshotReady: { _ in },
                onReviewMeshExportReady: { _, _, _, _ in }
            )
            .ignoresSafeArea()

            VStack(spacing: 6) {
                Text(model.renderMode == .mesh ? "Mesh 扫描中" : model.renderMode.rawValue)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.92))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.black.opacity(0.42))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.top, 110)
        }
        .onAppear {
            if !model.availableRenderModes.contains(.mesh) {
                model.renderMode = model.availableRenderModes.first ?? .planeCoverage
            } else {
                model.renderMode = .mesh
            }
        }
        .onChange(of: model.isRecording) { isRecording in
            if isRecording {
                liveMeshPreviewStore.reset()
            }
        }
    }

    private var statusText: String {
        if model.renderMode == .mesh {
            return "移动手机扫描墙面、角落和家具遮挡区"
        }
        if model.renderMode == .planeCoverage {
            return String(format: "平面覆盖 %.0f%%，非 LiDAR 设备将降级显示", model.planeCoverageRatio * 100)
        }
        if model.renderMode == .skyboxCoverage {
            return String(format: "方向覆盖 %.0f%%，非 LiDAR 设备将降级显示", model.skyboxCoverageRatio * 100)
        }
        return "当前设备不支持真实 Mesh，已降级为可用覆盖模式"
    }
}
