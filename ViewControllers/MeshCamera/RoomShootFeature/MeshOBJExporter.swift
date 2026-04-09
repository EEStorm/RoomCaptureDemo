//
//  MeshOBJExporter.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/3.
//
//  Simple OBJ export for LiDAR mesh review (no materials).
//

import ARKit
import Foundation
import simd

enum MeshOBJExporter {
    struct Stats: Equatable {
        var anchorCount: Int
        var vertexCount: Int
        var faceCount: Int
    }

    static func exportOBJ(from anchors: [ARMeshAnchor], to url: URL) throws -> Stats {
        // Stream to file to avoid OOM on long scans (OBJ can be huge).
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        FileManager.default.createFile(atPath: url.path, contents: nil, attributes: nil)
        let out = try FileHandle(forWritingTo: url)
        defer { try? out.close() }

        var buffer = Data()
        buffer.reserveCapacity(1024 * 1024)
        func flushIfNeeded(force: Bool = false) throws {
            if force || buffer.count >= 1024 * 1024 {
                try out.write(contentsOf: buffer)
                buffer.removeAll(keepingCapacity: true)
            }
        }
        func writeLine(_ s: String) throws {
            if let d = (s + "\n").data(using: .utf8) {
                buffer.append(d)
                try flushIfNeeded()
            }
        }

        var globalVertexOffset: Int = 0 // OBJ is 1-based.
        var totalVertices = 0
        var totalFaces = 0

        for (idx, anchor) in anchors.enumerated() {
            let mesh = anchor.geometry

            try writeLine("o mesh_\(idx)")

            // Vertices (stream).
            let vertexBuffer = mesh.vertices.buffer
            let vertexStride = mesh.vertices.stride
            let vertexOffset = mesh.vertices.offset
            let vertexCount = mesh.vertices.count
            let baseAddress = vertexBuffer.contents().advanced(by: vertexOffset)
            let anchorTransform = anchor.transform

            for i in 0..<vertexCount {
                let local = baseAddress.advanced(by: i * vertexStride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let world4 = simd_mul(anchorTransform, SIMD4<Float>(local.x, local.y, local.z, 1))
                try writeLine(String(format: "v %.6f %.6f %.6f", world4.x, world4.y, world4.z))
            }

            // Faces (triangles) (stream).
            let faces = mesh.faces
            let faceBuffer = faces.buffer
            let bytesPerIndex = faces.bytesPerIndex
            let indexCountPerPrimitive = faces.indexCountPerPrimitive
            let primitiveCount = faces.count
            precondition(indexCountPerPrimitive == 3, "Expected triangles")

            let faceBase = faceBuffer.contents()
            for primitiveIndex in 0..<primitiveCount {
                let primitiveBase = faceBase.advanced(by: primitiveIndex * indexCountPerPrimitive * bytesPerIndex)

                func readIndex(_ i: Int) -> UInt32 {
                    let idxPtr = primitiveBase.advanced(by: i * bytesPerIndex)
                    switch bytesPerIndex {
                    case 2:
                        return UInt32(idxPtr.assumingMemoryBound(to: UInt16.self).pointee)
                    case 4:
                        return idxPtr.assumingMemoryBound(to: UInt32.self).pointee
                    default:
                        return 0
                    }
                }

                let a = globalVertexOffset + Int(readIndex(0)) + 1
                let b = globalVertexOffset + Int(readIndex(1)) + 1
                let c = globalVertexOffset + Int(readIndex(2)) + 1
                try writeLine("f \(a) \(b) \(c)")
            }

            globalVertexOffset += vertexCount
            totalVertices += vertexCount
            totalFaces += primitiveCount
        }

        try flushIfNeeded(force: true)
        return Stats(anchorCount: anchors.count, vertexCount: totalVertices, faceCount: totalFaces)
    }
}
