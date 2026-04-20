import XCTest
@testable import CaptureDemo

final class MeshCaptureRecordStoreTests: XCTestCase {
    private var rootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL, FileManager.default.fileExists(atPath: rootURL.path) {
            try FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        try super.tearDownWithError()
    }

    func test_loadRecords_discoversVideoJsonAndOBJInCaptureFolder() throws {
        let folder = rootURL.appendingPathComponent("RoomShoot_2026-04-17T10-00-00Z", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: folder.appendingPathComponent("frames.mp4"))
        try Data("json".utf8).write(to: folder.appendingPathComponent("poses.json"))
        try Data("obj".utf8).write(to: folder.appendingPathComponent("mesh.obj"))

        let store = MeshCaptureRecordStore(rootURL: rootURL)

        let records = try store.loadRecords()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].files.map(\.kind), [.video, .json, .obj])
        XCTAssertTrue(records[0].isComplete)
    }

    func test_loadRecords_sortsNewestCaptureFirst() throws {
        let older = try makeRecordFolder(named: "RoomShoot_older", createdAt: Date(timeIntervalSince1970: 100))
        let newer = try makeRecordFolder(named: "RoomShoot_newer", createdAt: Date(timeIntervalSince1970: 200))
        XCTAssertNotEqual(older, newer)

        let store = MeshCaptureRecordStore(rootURL: rootURL)

        let records = try store.loadRecords()

        XCTAssertEqual(records.map(\.folderURL.lastPathComponent), ["RoomShoot_newer", "RoomShoot_older"])
    }

    func test_deleteRecord_removesCaptureFolder() throws {
        let folder = try makeRecordFolder(named: "RoomShoot_delete", createdAt: Date())
        let store = MeshCaptureRecordStore(rootURL: rootURL)
        let record = try XCTUnwrap(store.loadRecords().first(where: { $0.folderURL == folder }))

        try store.deleteRecord(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    func test_recordFiles_marksVideoAsAlbumSavableAndOtherFilesAsShareOnly() throws {
        let folder = try makeRecordFolder(named: "RoomShoot_actions", createdAt: Date())
        let store = MeshCaptureRecordStore(rootURL: rootURL)
        let record = try XCTUnwrap(store.loadRecords().first(where: { $0.folderURL == folder }))

        let actionMap = Dictionary(uniqueKeysWithValues: record.files.map { ($0.kind, $0.kind.supportsSaveToAlbum) })

        XCTAssertEqual(actionMap[.video], true)
        XCTAssertEqual(actionMap[.json], false)
        XCTAssertEqual(actionMap[.obj], false)
        XCTAssertTrue(record.files.allSatisfy(\.isShareable))
    }

    @discardableResult
    private func makeRecordFolder(named name: String, createdAt: Date) throws -> URL {
        let folder = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("video".utf8).write(to: folder.appendingPathComponent("frames.mp4"))
        try Data("json".utf8).write(to: folder.appendingPathComponent("poses.json"))
        try Data("obj".utf8).write(to: folder.appendingPathComponent("mesh.obj"))
        try FileManager.default.setAttributes([.creationDate: createdAt, .modificationDate: createdAt], ofItemAtPath: folder.path)
        return folder
    }
}
