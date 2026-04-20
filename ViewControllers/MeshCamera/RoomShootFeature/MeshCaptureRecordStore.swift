//
//  MeshCaptureRecordStore.swift
//  CaptureDemo
//
//  Created by Codex on 2026/4/17.
//

import Foundation

enum MeshCaptureFileKind: String, CaseIterable {
    case video
    case json
    case obj

    var preferredFilename: String {
        switch self {
        case .video:
            return "frames.mp4"
        case .json:
            return "poses.json"
        case .obj:
            return "mesh.obj"
        }
    }

    var displayTitle: String {
        switch self {
        case .video:
            return "完整视频"
        case .json:
            return "位姿 JSON"
        case .obj:
            return "Mesh OBJ"
        }
    }

    var supportsSaveToAlbum: Bool {
        self == .video
    }
}

struct MeshCaptureRecordFile: Equatable {
    let kind: MeshCaptureFileKind
    let url: URL
    let sizeInBytes: Int64

    var fileName: String {
        url.lastPathComponent
    }

    var isShareable: Bool {
        true
    }
}

struct MeshCaptureRecord: Equatable {
    let folderURL: URL
    let createdAt: Date
    let files: [MeshCaptureRecordFile]

    var title: String {
        folderURL.lastPathComponent
    }

    var videoFile: MeshCaptureRecordFile? {
        files.first(where: { $0.kind == .video })
    }

    var jsonFile: MeshCaptureRecordFile? {
        files.first(where: { $0.kind == .json })
    }

    var objFile: MeshCaptureRecordFile? {
        files.first(where: { $0.kind == .obj })
    }

    var isComplete: Bool {
        videoFile != nil && jsonFile != nil && objFile != nil
    }
}

struct MeshCaptureRecordStore {
    private let fileManager: FileManager
    private let rootURL: URL

    init(
        fileManager: FileManager = .default,
        rootURL: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    ) {
        self.fileManager = fileManager
        self.rootURL = rootURL
    }

    func loadRecords() throws -> [MeshCaptureRecord] {
        guard fileManager.fileExists(atPath: rootURL.path) else {
            return []
        }

        let folderURLs = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent.hasPrefix("RoomShoot_") else {
                return false
            }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }

        let records = try folderURLs.compactMap { folderURL -> MeshCaptureRecord? in
            let files = try loadFiles(in: folderURL)
            guard !files.isEmpty else {
                return nil
            }

            let values = try folderURL.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let createdAt = values.creationDate ?? values.contentModificationDate ?? .distantPast
            return MeshCaptureRecord(folderURL: folderURL, createdAt: createdAt, files: files)
        }

        return records.sorted { lhs, rhs in
            if lhs.createdAt == rhs.createdAt {
                return lhs.folderURL.lastPathComponent > rhs.folderURL.lastPathComponent
            }
            return lhs.createdAt > rhs.createdAt
        }
    }

    func deleteRecord(_ record: MeshCaptureRecord) throws {
        guard fileManager.fileExists(atPath: record.folderURL.path) else {
            return
        }
        try fileManager.removeItem(at: record.folderURL)
    }

    private func loadFiles(in folderURL: URL) throws -> [MeshCaptureRecordFile] {
        let urls = try fileManager.contentsOfDirectory(
            at: folderURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        )

        let byName = Dictionary(uniqueKeysWithValues: urls.map { ($0.lastPathComponent, $0) })
        return MeshCaptureFileKind.allCases.compactMap { kind in
            guard let url = byName[kind.preferredFilename] else {
                return nil
            }
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values?.isRegularFile == true else {
                return nil
            }
            let size = Int64(values?.fileSize ?? 0)
            return MeshCaptureRecordFile(kind: kind, url: url, sizeInBytes: size)
        }
    }
}
