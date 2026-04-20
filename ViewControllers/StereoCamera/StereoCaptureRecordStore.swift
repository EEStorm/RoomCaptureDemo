import Foundation

enum StereoCaptureLensKind: String, CaseIterable {
    case ultraWide
    case wide

    var preferredFilename: String {
        switch self {
        case .ultraWide:
            return "ultra_wide.mp4"
        case .wide:
            return "wide.mp4"
        }
    }

    var displayTitle: String {
        switch self {
        case .ultraWide:
            return "0.5x 超广角"
        case .wide:
            return "1.0x 广角"
        }
    }
}

struct StereoCaptureRecordFile: Equatable {
    let kind: StereoCaptureLensKind
    let url: URL
    let sizeInBytes: Int64

    var fileName: String {
        url.lastPathComponent
    }
}

struct StereoCaptureRecord: Equatable {
    let folderURL: URL
    let createdAt: Date
    let files: [StereoCaptureRecordFile]

    var title: String {
        folderURL.lastPathComponent
    }

    var isComplete: Bool {
        files.count == StereoCaptureLensKind.allCases.count
    }
}

struct StereoCaptureRecordStore {
    private let fileManager: FileManager
    private let rootURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL = Self.defaultRootURL
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    static var defaultRootURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StereoCaptures", isDirectory: true)
    }

    func loadRecords() throws -> [StereoCaptureRecord] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }

        let folderURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent.hasPrefix("StereoCapture_") else {
                return false
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }

        let records = try folderURLs.compactMap { folderURL -> StereoCaptureRecord? in
            let files = try loadFiles(in: folderURL)
            guard !files.isEmpty else {
                return nil
            }

            let values = try folderURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let createdAt = values.creationDate ?? values.contentModificationDate ?? .distantPast
            return StereoCaptureRecord(folderURL: folderURL, createdAt: createdAt, files: files)
        }

        return records.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.folderURL.lastPathComponent > rhs.folderURL.lastPathComponent
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func deleteRecord(_ record: StereoCaptureRecord) throws {
        guard fileManager.fileExists(atPath: record.folderURL.path) else {
            return
        }
        try fileManager.removeItem(at: record.folderURL)
    }

    private func loadFiles(in folderURL: URL) throws -> [StereoCaptureRecordFile] {
        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let byName = Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, $0) })
        return StereoCaptureLensKind.allCases.compactMap { kind in
            guard let url = byName[kind.preferredFilename] else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else {
                return nil
            }
            return StereoCaptureRecordFile(kind: kind, url: url, sizeInBytes: Int64(values?.fileSize ?? 0))
        }
    }
}
