import UIKit

@objc(CDStereoCaptureListViewController)
final class CDStereoCaptureListViewController: UITableViewController {
    private let store = StereoCaptureRecordStore()
    private var records: [StereoCaptureRecord] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "下载列表"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "StereoRecordCell")
        tableView.tableFooterView = UIView()
        reloadRecords()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        reloadRecords()
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        records.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "StereoRecordCell", for: indexPath)
        let record = records[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = record.title
        content.secondaryText = secondaryText(for: record)
        content.secondaryTextProperties.color = .secondaryLabel
        content.secondaryTextProperties.numberOfLines = 2
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        cell.imageView?.image = UIImage(systemName: record.isComplete ? "tray.full.fill" : "tray.fill")
        cell.imageView?.tintColor = record.isComplete ? .systemBlue : .systemOrange
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let detailViewController = CDStereoCaptureDetailViewController(record: records[indexPath.row])
        navigationController?.pushViewController(detailViewController, animated: true)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        guard editingStyle == .delete else { return }
        let record = records[indexPath.row]
        do {
            try store.deleteRecord(record)
            records.remove(at: indexPath.row)
            tableView.deleteRows(at: [indexPath], with: .automatic)
        } catch {
            presentMessage(title: "删除失败", message: error.localizedDescription)
        }
    }

    private func reloadRecords() {
        do {
            records = try store.loadRecords()
        } catch {
            records = []
            presentMessage(title: "加载失败", message: error.localizedDescription)
        }
        tableView.reloadData()
    }

    private func secondaryText(for record: StereoCaptureRecord) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let files = record.files.map(\.fileName).joined(separator: " / ")
        return "\(formatter.string(from: record.createdAt))\n\(files)"
    }

    private func presentMessage(title: String, message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "确定", style: .default))
        present(alert, animated: true)
    }
}
