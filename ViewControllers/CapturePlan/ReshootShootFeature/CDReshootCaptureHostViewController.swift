import SwiftUI
import UIKit

@objc(CDReshootCaptureHostViewController)
@objcMembers
final class CDReshootCaptureHostViewController: UIViewController {
    private var hostingController: UIHostingController<ContentView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let hostingController = UIHostingController(
            rootView: ContentView(
                onShowCaptureList: { [weak self] in
                    self?.showCaptureList()
                },
                showsRenderModePicker: false,
                showsDownloadListButton: false,
                showsMainMeshOverlay: true
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
