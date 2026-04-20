import AVKit
import Photos
import UIKit

final class CDStereoCaptureDetailViewController: UITableViewController {
    private let record: StereoCaptureRecord

    init(record: StereoCaptureRecord) {
        self.record = record
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "记录详情"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StereoFileCell")
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        2
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        section == 0 ? 1 : record.files.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        section == 0 ? "拍摄批次" : "镜头视频"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StereoFileCell", for: indexPath)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
            content.text = record.title
            content.secondaryText = "\(formatter.string(from: record.createdAt))\n\(record.folderURL.path)"
            content.secondaryTextProperties.numberOfLines = 0
            cell.accessoryType = .none
            cell.selectionStyle = .none
        } else {
            let file = record.files[indexPath.row]
            content.text = "\(file.kind.displayTitle) · \(file.fileName)"
            content.secondaryText = ByteCountFormatter.string(fromByteCount: file.sizeInBytes, countStyle: .file)
            cell.accessoryType = .disclosureIndicator
            cell.selectionStyle = .default
            cell.imageView?.image = UIImage(systemName: "video.fill")
            cell.imageView?.tintColor = .systemRed
        }
        content.secondaryTextProperties.color = .secondaryLabel
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard indexPath.section == 1 else { return }
        presentVideoActions(for: record.files[indexPath.row])
    }

    private func presentVideoActions(for file: StereoCaptureRecordFile) {
        let alert = UIAlertController(title: file.fileName, message: nil, preferredStyle: .actionSheet)
        alert.addAction(UIAlertAction(title: "播放", style: .default) { [weak self] _ in
            self?.playVideo(url: file.url)
        })
        alert.addAction(UIAlertAction(title: "保存到相册", style: .default) { [weak self] _ in
            self?.saveVideoToAlbum(url: file.url)
        })
        alert.addAction(UIAlertAction(title: "分享", style: .default) { [weak self] _ in
            self?.share(url: file.url)
        })
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        if let popover = alert.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(alert, animated: true)
    }

    private func playVideo(url: URL) {
        let player = AVPlayer(url: url)
        let controller = AVPlayerViewController()
        controller.player = player
        present(controller, animated: true) {
            player.play()
        }
    }

    private func saveVideoToAlbum(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { [weak self] status in
            guard let self else { return }
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    self.presentMessage(title: "无法保存", message: "请在设置中允许访问相册。")
                }
                return
            }

            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                DispatchQueue.main.async {
                    if success {
                        self.presentMessage(title: "保存成功", message: "视频已保存到系统相册。")
                    } else {
                        self.presentMessage(title: "保存失败", message: error?.localizedDescription ?? "未知错误")
                    }
                }
            }
        }
    }

    private func share(url: URL) {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
            popover.permittedArrowDirections = []
        }
        present(controller, animated: true)
    }

    private func presentMessage(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
