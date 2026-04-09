//
//  ReviewZipPackager.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/3.
//

import Foundation

enum ReviewZipPackager {
    nonisolated static func repackageZip(
        export: VideoPoseRecorder.ExportResult,
        extraFiles: [URL]
    ) throws {
        let parent = export.folderURL.lastPathComponent

        var entries: [SimpleZipWriter.Entry] = [
            .init(fileURL: export.videoURL, pathInZip: "\(parent)/\(export.videoURL.lastPathComponent)"),
            .init(fileURL: export.jsonURL, pathInZip: "\(parent)/\(export.jsonURL.lastPathComponent)"),
        ]

        for url in extraFiles {
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            entries.append(.init(fileURL: url, pathInZip: "\(parent)/\(url.lastPathComponent)"))
        }

        // Overwrite zip.
        let zipURL = export.zipURL
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try? FileManager.default.removeItem(at: zipURL)
        }
        try SimpleZipWriter.createZip(at: zipURL, entries: entries)
    }
}
