import SwiftUI
import UIKit

@objc(CDMeshCaptureHostViewController)
@objcMembers
final class CDMeshCaptureHostViewController: UIViewController {
    private var hostingController: UIHostingController<ContentView>?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let hostingController = UIHostingController(rootView: ContentView())
        addChild(hostingController)
        hostingController.view.frame = view.bounds
        hostingController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hostingController.view)
        hostingController.didMove(toParent: self)
        self.hostingController = hostingController
    }
}
