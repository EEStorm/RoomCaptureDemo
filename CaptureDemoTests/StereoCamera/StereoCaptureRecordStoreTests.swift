import XCTest
@testable import CaptureDemo

final class StereoCaptureRecordStoreTests: XCTestCase {
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

    func test_loadRecords_discoversUltraWideAndWideVideoFiles() throws {
        let folder = try makeRecordFolder(named: "StereoCapture_batch_1", createdAt: Date())

        let store = StereoCaptureRecordStore(rootURL: rootURL)

        let records = try store.loadRecords()

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].folderURL, folder)
        XCTAssertEqual(records[0].files.map(\.kind), [.ultraWide, .wide])
        XCTAssertTrue(records[0].isComplete)
    }

    func test_loadRecords_sortsNewestCaptureFirst() throws {
        let older = try makeRecordFolder(named: "StereoCapture_older", createdAt: Date(timeIntervalSince1970: 100))
        let newer = try makeRecordFolder(named: "StereoCapture_newer", createdAt: Date(timeIntervalSince1970: 200))
        XCTAssertNotEqual(older, newer)

        let store = StereoCaptureRecordStore(rootURL: rootURL)

        let records = try store.loadRecords()

        XCTAssertEqual(records.map(\.folderURL.lastPathComponent), ["StereoCapture_newer", "StereoCapture_older"])
    }

    func test_deleteRecord_removesCaptureFolder() throws {
        let folder = try makeRecordFolder(named: "StereoCapture_delete", createdAt: Date())
        let store = StereoCaptureRecordStore(rootURL: rootURL)
        let record = try XCTUnwrap(store.loadRecords().first(where: { $0.folderURL == folder }))

        try store.deleteRecord(record)

        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
    }

    @discardableResult
    private func makeRecordFolder(named name: String, createdAt: Date) throws -> URL {
        let folder = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("ultra".utf8).write(to: folder.appendingPathComponent("ultra_wide.mp4"))
        try Data("wide".utf8).write(to: folder.appendingPathComponent("wide.mp4"))
        try FileManager.default.setAttributes([.creationDate: createdAt, .modificationDate: createdAt], ofItemAtPath: folder.path)
        return folder
    }
}
