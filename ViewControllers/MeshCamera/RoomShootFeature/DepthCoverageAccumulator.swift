//
//  DepthCoverageAccumulator.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/2.
//
//  Scheme B: Depth-map driven "coverage" preview.
//  - Ingests ARFrame.sceneDepth (if available)
//  - Builds a sparse voxel occupancy map (coverage)
//  - Renders only recent/nearby points as small billboards (like spray paint)
//

import ARKit
import Foundation
import SceneKit
import simd

final class DepthCoverageAccumulator {
    struct Config {
        var sampleStride: Int = 6
        var minDepthMeters: Float = 0.20
        var maxDepthMeters: Float = 6.0

        var voxelSizeMeters: Float = 0.04
        // Keep a large persistent coverage map (actual rendered points are still capped).
        var maxVoxels: Int = 800_000

        // Render neighborhood around the camera; stored voxels persist until reset.
        var renderRadiusMeters: Float = 6.0
        // <= 0 means "do not fade out by time".
        var fadeSeconds: Double = 0

        var billboardSizeMeters: Float = 0.006
        var maxRenderPoints: Int = 25_000

        var updateIntervalSeconds: Double = 0.20
    }

    private struct VoxelKey: Hashable {
        let x: Int32
        let y: Int32
        let z: Int32
    }

    private struct Sample {
        var position: SIMD3<Float>
        var lastSeen: TimeInterval
    }

    private(set) var config: Config

    private var voxels: [VoxelKey: Sample] = [:]
    private var lastGeometryUpdateTimestamp: TimeInterval = 0
    private(set) var lastRenderedPointCount: Int = 0

    init(config: Config = .init()) {
        self.config = config
        voxels.reserveCapacity(config.maxVoxels)
    }

    func reset() {
        voxels.removeAll(keepingCapacity: true)
        lastGeometryUpdateTimestamp = 0
        lastRenderedPointCount = 0
    }

    var currentVoxelCount: Int { voxels.count }
    var maxVoxels: Int { config.maxVoxels }

    func ingest(frame: ARFrame) {
        guard let sceneDepth = frame.sceneDepth else { return }
        ingestDepth(sceneDepth: sceneDepth, camera: frame.camera, timestamp: frame.timestamp)
    }

    func shouldUpdateGeometry(at timestamp: TimeInterval) -> Bool {
        if lastGeometryUpdateTimestamp == 0 { return true }
        return (timestamp - lastGeometryUpdateTimestamp) >= config.updateIntervalSeconds
    }

    func makeGeometryAndMarkUpdated(at timestamp: TimeInterval, cameraTransform: simd_float4x4) -> SCNGeometry? {
        guard !voxels.isEmpty else { return nil }
        lastGeometryUpdateTimestamp = timestamp

        let cameraPos = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        let r2 = config.renderRadiusMeters * config.renderRadiusMeters
        let fadeSeconds = config.fadeSeconds

        // Collect points close to camera and recently seen.
        var visible: [Sample] = []
        visible.reserveCapacity(min(voxels.count, config.maxRenderPoints))
        for (_, s) in voxels {
            if fadeSeconds > 0 {
                let fade = max(fadeSeconds, 0.25)
                let age = timestamp - s.lastSeen
                if age < 0 || age > fade { continue }
            }
            let d = s.position - cameraPos
            if simd_length_squared(d) <= r2 {
                visible.append(s)
            }
        }
        if visible.isEmpty { return nil }

        // Downsample if still too many.
        let maxRender = max(1, config.maxRenderPoints)
        let chosen: [Sample]
        if visible.count <= maxRender {
            chosen = visible
        } else {
            let step = max(1, visible.count / maxRender)
            var tmp: [Sample] = []
            tmp.reserveCapacity(maxRender)
            var i = 0
            while i < visible.count && tmp.count < maxRender {
                tmp.append(visible[i])
                i += step
            }
            chosen = tmp
        }

        let n = chosen.count
        lastRenderedPointCount = n

        let half = max(0.0015, config.billboardSizeMeters) * 0.5
        let right = simd_normalize(SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)) * half
        let up = simd_normalize(SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)) * half

        var vertexData = Data(count: n * 4 * MemoryLayout<Float>.size * 3)
        var colorData = Data(count: n * 4 * MemoryLayout<Float>.size * 4)
        var indexData = Data(count: n * 6 * MemoryLayout<UInt32>.size)

        vertexData.withUnsafeMutableBytes { raw in
            guard let out = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            for i in 0..<n {
                let p = chosen[i].position
                let v0 = p - right - up
                let v1 = p + right - up
                let v2 = p + right + up
                let v3 = p - right + up

                let base = i * 12
                out[base + 0] = v0.x
                out[base + 1] = v0.y
                out[base + 2] = v0.z
                out[base + 3] = v1.x
                out[base + 4] = v1.y
                out[base + 5] = v1.z
                out[base + 6] = v2.x
                out[base + 7] = v2.y
                out[base + 8] = v2.z
                out[base + 9] = v3.x
                out[base + 10] = v3.y
                out[base + 11] = v3.z
            }
        }

        colorData.withUnsafeMutableBytes { raw in
            guard let out = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            for i in 0..<n {
                let alpha: Float
                if fadeSeconds > 0 {
                    let fade = max(fadeSeconds, 0.25)
                    let age = max(0, timestamp - chosen[i].lastSeen)
                    let t = min(1.0, age / fade)
                    alpha = Float(max(0.06, 0.85 * (1.0 - t)))
                } else {
                    // Persistent coverage preview.
                    alpha = 0.28
                }
                let base = i * 16
                for v in 0..<4 {
                    out[base + v * 4 + 0] = 0.12
                    out[base + v * 4 + 1] = 1.0
                    out[base + v * 4 + 2] = 0.12
                    out[base + v * 4 + 3] = alpha
                }
            }
        }

        indexData.withUnsafeMutableBytes { raw in
            guard let out = raw.baseAddress?.assumingMemoryBound(to: UInt32.self) else { return }
            for i in 0..<n {
                let vbase = UInt32(i * 4)
                let ibase = i * 6
                out[ibase + 0] = vbase + 0
                out[ibase + 1] = vbase + 1
                out[ibase + 2] = vbase + 2
                out[ibase + 3] = vbase + 0
                out[ibase + 4] = vbase + 2
                out[ibase + 5] = vbase + 3
            }
        }

        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: n * 4,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 3
        )

        let colorSource = SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: n * 4,
            usesFloatComponents: true,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: MemoryLayout<Float>.size * 4
        )

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: n * 2,
            bytesPerIndex: MemoryLayout<UInt32>.size
        )

        let geometry = SCNGeometry(sources: [vertexSource, colorSource], elements: [element])
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.emission.contents = UIColor.green.withAlphaComponent(0.22)
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        material.readsFromDepthBuffer = true
        geometry.materials = [material]

        return geometry
    }

    // MARK: - Private

    private func ingestDepth(sceneDepth: ARDepthData, camera: ARCamera, timestamp: TimeInterval) {
        let depthMap = sceneDepth.depthMap
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }
        let format = CVPixelBufferGetPixelFormatType(depthMap)

        let imageRes = camera.imageResolution
        let sx = Float(depthWidth) / Float(max(1, Int(imageRes.width)))
        let sy = Float(depthHeight) / Float(max(1, Int(imageRes.height)))

        let intr = camera.intrinsics
        let fx = intr.columns.0.x * sx
        let fy = intr.columns.1.y * sy
        let cx = intr.columns.2.x * sx
        let cy = intr.columns.2.y * sy

        let cameraToWorld = camera.transform
        let step = max(1, config.sampleStride)

        for y in Swift.stride(from: 0, to: depthHeight, by: step) {
            let rowPtr = baseAddress.advanced(by: y * bytesPerRow)
            for x in Swift.stride(from: 0, to: depthWidth, by: step) {
                let z: Float
                switch format {
                case kCVPixelFormatType_DepthFloat32:
                    z = rowPtr.advanced(by: x * MemoryLayout<Float>.size).assumingMemoryBound(to: Float.self).pointee
                case kCVPixelFormatType_DepthFloat16:
                    let raw = rowPtr.advanced(by: x * MemoryLayout<UInt16>.size).assumingMemoryBound(to: UInt16.self).pointee
                    z = Self.float16ToFloat32(raw)
                default:
                    continue
                }

                if !z.isFinite { continue }
                if z < config.minDepthMeters || z > config.maxDepthMeters { continue }

                let X = (Float(x) - cx) / fx * z
                let Y = -((Float(y) - cy) / fy * z)
                let cameraPoint = SIMD4<Float>(X, Y, -z, 1)
                let worldPoint4 = cameraToWorld * cameraPoint
                let worldPoint = SIMD3<Float>(worldPoint4.x, worldPoint4.y, worldPoint4.z)

                append(worldPoint, timestamp: timestamp)
            }
        }
    }

    private func append(_ point: SIMD3<Float>, timestamp: TimeInterval) {
        let key = voxelKey(for: point)
        if var existing = voxels[key] {
            existing.position = 0.85 * existing.position + 0.15 * point
            existing.lastSeen = timestamp
            voxels[key] = existing
            return
        }
        guard voxels.count < config.maxVoxels else { return }
        voxels[key] = Sample(position: point, lastSeen: timestamp)
    }

    private func voxelKey(for p: SIMD3<Float>) -> VoxelKey {
        let s = max(config.voxelSizeMeters, 0.005)
        let inv = 1.0 / s
        return VoxelKey(
            x: Int32(floor(p.x * inv)),
            y: Int32(floor(p.y * inv)),
            z: Int32(floor(p.z * inv))
        )
    }

    private static func float16ToFloat32(_ raw: UInt16) -> Float {
        let sign = (raw & 0x8000) >> 15
        let exp = (raw & 0x7C00) >> 10
        let frac = raw & 0x03FF

        var f: UInt32
        if exp == 0 {
            if frac == 0 {
                f = UInt32(sign) << 31
            } else {
                var e: Int32 = -1
                var m = UInt32(frac)
                while (m & 0x0400) == 0 {
                    m <<= 1
                    e -= 1
                }
                m &= 0x03FF
                let exp32 = UInt32(Int32(127 - 15) + e)
                f = (UInt32(sign) << 31) | (exp32 << 23) | (m << 13)
            }
        } else if exp == 0x1F {
            f = (UInt32(sign) << 31) | 0x7F80_0000 | (UInt32(frac) << 13)
        } else {
            let exp32 = UInt32(exp) + (127 - 15)
            f = (UInt32(sign) << 31) | (exp32 << 23) | (UInt32(frac) << 13)
        }

        return Float(bitPattern: f)
    }
}
