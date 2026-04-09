//
//  SimpleZipWriter.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//
//  A tiny ZIP (store/no-compression) writer that supports streaming large files.
//  It writes local headers with a data descriptor so CRC/size can be computed on the fly.
//

import Foundation

enum SimpleZipWriter {
    struct Entry {
        let fileURL: URL
        /// Path inside the zip (UTF-8). Use "/" separators.
        let pathInZip: String
    }

    enum ZipError: Error {
        case cannotOpenInput(URL)
        case unsupportedFileSize(URL)
        case invalidUTF8Path(String)
    }

    static func createZip(at zipURL: URL, entries: [Entry]) throws {
        // Write atomically: create a temp zip and then move into place.
        // This prevents producing a corrupt/partial zip if the app crashes mid-write.
        let dir = zipURL.deletingLastPathComponent()
        let tmpURL = dir.appendingPathComponent(".tmp.\(UUID().uuidString).zip")
        if FileManager.default.fileExists(atPath: tmpURL.path) {
            try? FileManager.default.removeItem(at: tmpURL)
        }
        FileManager.default.createFile(atPath: tmpURL.path, contents: nil, attributes: nil)

        let out = try FileHandle(forWritingTo: tmpURL)
        defer {
            try? out.close()
            // If an error was thrown before move, try to clean up.
            if FileManager.default.fileExists(atPath: tmpURL.path), !FileManager.default.fileExists(atPath: zipURL.path) {
                try? FileManager.default.removeItem(at: tmpURL)
            }
        }

        var centralDirectory = Data()
        var bytesWritten: UInt64 = 0

        struct CentralRecord {
            let pathData: Data
            let crc32: UInt32
            let compressedSize: UInt32
            let uncompressedSize: UInt32
            let dosTime: UInt16
            let dosDate: UInt16
            let localHeaderOffset: UInt32
        }
        var records: [CentralRecord] = []
        records.reserveCapacity(entries.count)

        for entry in entries {
            guard let pathData = entry.pathInZip.data(using: .utf8) else {
                throw ZipError.invalidUTF8Path(entry.pathInZip)
            }

            let attrs = try FileManager.default.attributesOfItem(atPath: entry.fileURL.path)
            let fileSize64 = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
            guard fileSize64 <= UInt64(UInt32.max) else {
                throw ZipError.unsupportedFileSize(entry.fileURL)
            }

            let (dosTime, dosDate) = dosDateTime(from: (attrs[.modificationDate] as? Date) ?? Date())

            // Local file header (with data descriptor flag set)
            let localHeaderOffset = UInt32(truncatingIfNeeded: bytesWritten)
            var localHeader = Data()
            localHeader.appendUInt32LE(0x04034b50) // Local file header signature
            localHeader.appendUInt16LE(20) // version needed to extract
            localHeader.appendUInt16LE(0x0008) // general purpose bit flag: data descriptor
            localHeader.appendUInt16LE(0) // compression method: store
            localHeader.appendUInt16LE(dosTime)
            localHeader.appendUInt16LE(dosDate)
            localHeader.appendUInt32LE(0) // crc32 (unknown yet)
            localHeader.appendUInt32LE(0) // compressed size (unknown)
            localHeader.appendUInt32LE(0) // uncompressed size (unknown)
            localHeader.appendUInt16LE(UInt16(min(pathData.count, Int(UInt16.max)))) // file name length
            localHeader.appendUInt16LE(0) // extra field length
            localHeader.append(pathData)

            try out.write(contentsOf: localHeader)
            bytesWritten += UInt64(localHeader.count)

            // Stream file data and compute CRC32.
            let input = InputStream(url: entry.fileURL)
            guard let input else { throw ZipError.cannotOpenInput(entry.fileURL) }
            input.open()
            defer { input.close() }

            var crc = CRC32()
            var total: UInt32 = 0
            var buffer = [UInt8](repeating: 0, count: 256 * 1024)
            while input.hasBytesAvailable {
                let readCount = input.read(&buffer, maxLength: buffer.count)
                if readCount < 0 { break }
                if readCount == 0 { break }

                crc.update(bytes: buffer, count: readCount)
                total &+= UInt32(readCount)
                try out.write(contentsOf: Data(buffer[0..<readCount]))
                bytesWritten += UInt64(readCount)
            }

            // Data descriptor (with signature)
            let crcValue = crc.finalize()
            var descriptor = Data()
            descriptor.appendUInt32LE(0x08074b50)
            descriptor.appendUInt32LE(crcValue)
            descriptor.appendUInt32LE(total) // compressed size (store)
            descriptor.appendUInt32LE(total) // uncompressed size
            try out.write(contentsOf: descriptor)
            bytesWritten += UInt64(descriptor.count)

            records.append(
                CentralRecord(
                    pathData: pathData,
                    crc32: crcValue,
                    compressedSize: total,
                    uncompressedSize: total,
                    dosTime: dosTime,
                    dosDate: dosDate,
                    localHeaderOffset: localHeaderOffset
                )
            )
        }

        // Central directory
        let centralDirectoryOffset = bytesWritten
        for record in records {
            var cdh = Data()
            cdh.appendUInt32LE(0x02014b50) // Central directory file header signature
            cdh.appendUInt16LE(20) // version made by
            cdh.appendUInt16LE(20) // version needed to extract
            cdh.appendUInt16LE(0x0008) // general purpose bit flag: data descriptor
            cdh.appendUInt16LE(0) // compression method: store
            cdh.appendUInt16LE(record.dosTime)
            cdh.appendUInt16LE(record.dosDate)
            cdh.appendUInt32LE(record.crc32)
            cdh.appendUInt32LE(record.compressedSize)
            cdh.appendUInt32LE(record.uncompressedSize)
            cdh.appendUInt16LE(UInt16(min(record.pathData.count, Int(UInt16.max)))) // file name length
            cdh.appendUInt16LE(0) // extra field length
            cdh.appendUInt16LE(0) // file comment length
            cdh.appendUInt16LE(0) // disk number start
            cdh.appendUInt16LE(0) // internal file attributes
            cdh.appendUInt32LE(0) // external file attributes
            cdh.appendUInt32LE(record.localHeaderOffset)
            cdh.append(record.pathData)

            centralDirectory.append(cdh)
        }

        try out.write(contentsOf: centralDirectory)
        bytesWritten += UInt64(centralDirectory.count)

        let centralDirectorySize = UInt32(truncatingIfNeeded: centralDirectory.count)
        let centralDirectoryOffset32 = UInt32(truncatingIfNeeded: centralDirectoryOffset)

        // End of central directory record
        var eocd = Data()
        eocd.appendUInt32LE(0x06054b50)
        eocd.appendUInt16LE(0) // number of this disk
        eocd.appendUInt16LE(0) // number of the disk with the start of the central directory
        eocd.appendUInt16LE(UInt16(min(records.count, Int(UInt16.max)))) // total entries on this disk
        eocd.appendUInt16LE(UInt16(min(records.count, Int(UInt16.max)))) // total entries
        eocd.appendUInt32LE(centralDirectorySize)
        eocd.appendUInt32LE(centralDirectoryOffset32)
        eocd.appendUInt16LE(0) // zip file comment length
        try out.write(contentsOf: eocd)

        // Close before moving into place.
        try? out.close()

        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }
        try FileManager.default.moveItem(at: tmpURL, to: zipURL)
    }

    private static func dosDateTime(from date: Date) -> (UInt16, UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let c = calendar.dateComponents(in: TimeZone.current, from: date)
        let year = max(1980, c.year ?? 1980) - 1980
        let month = max(1, c.month ?? 1)
        let day = max(1, c.day ?? 1)
        let hour = c.hour ?? 0
        let minute = c.minute ?? 0
        let second = (c.second ?? 0) / 2

        let dosTime = UInt16((hour << 11) | (minute << 5) | second)
        let dosDate = UInt16((year << 9) | (month << 5) | day)
        return (dosTime, dosDate)
    }
}

private struct CRC32 {
    private var value: UInt32 = 0xFFFF_FFFF

    mutating func update(bytes: [UInt8], count: Int) {
        for i in 0..<count {
            let idx = Int((value ^ UInt32(bytes[i])) & 0xFF)
            value = (value >> 8) ^ CRC32.table[idx]
        }
    }

    mutating func finalize() -> UInt32 {
        value ^ 0xFFFF_FFFF
    }

    private static let table: [UInt32] = {
        (0..<256).map { i in
            var c = UInt32(i)
            for _ in 0..<8 {
                if (c & 1) != 0 {
                    c = 0xEDB8_8320 ^ (c >> 1)
                } else {
                    c = c >> 1
                }
            }
            return c
        }
    }()
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }
}
