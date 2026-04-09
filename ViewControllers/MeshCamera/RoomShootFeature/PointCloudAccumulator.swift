//
//  PointCloudAccumulator.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/3/30.
//

import ARKit
import Foundation
import SceneKit
import simd

final class PointCloudAccumulator {
    struct Config {
        // Depth sampling (smaller => denser, but heavier).
        var sampleStride: Int = 3
        var maxDepthMeters: Float = 6.0
        // Coverage-style point cloud: keep at most 1 point per voxel.
        var voxelSizeMeters: Float = 0.015
        // NOTE: Truly "unlimited" points is not feasible for real-time rendering/memory.
        // Set a very high cap to behave unbounded for normal scanning sessions.
        var maxVoxels: Int = 1_000_000
        var minDepthMeters: Float = 0.15
        var updateIntervalSeconds: Double = 0.12
        // Only render points near the camera to avoid "full-screen green".
        var renderRadiusMeters: Float = 2.5
        // Newer points are brighter; older points fade.
        var fadeSeconds: Double = 5.0
        // Render each point as a camera-facing quad (billboard) in world units.
        var billboardSizeMeters: Float = 0.004
        // Cap rendered quads to keep performance stable.
        var maxRenderPoints: Int = 200_000
    }

    private(set) var config: Config

    private struct VoxelKey: Hashable {
        let x: Int32
        let y: Int32
        let z: Int32
    }

    private struct Sample {
        var position: SIMD3<Float>
        var lastSeen: TimeInterval
    }

    private var voxels: [VoxelKey: Sample] = [:]

    private var lastGeometryUpdateTimestamp: TimeInterval = 0

    init(config: Config = .init()) {
        self.config = config
        self.voxels.reserveCapacity(config.maxVoxels)
    }

    func reset() {
        voxels.removeAll(keepingCapacity: true)
        lastGeometryUpdateTimestamp = 0
    }

    var currentVoxelCount: Int { voxels.count }
    var maxVoxels: Int { config.maxVoxels }
    private(set) var lastRenderedPointCount: Int = 0

    func updateConfig(_ newConfig: Config) {
        config = newConfig
        voxels.reserveCapacity(newConfig.maxVoxels)
        reset()
    }

    func ingest(frame: ARFrame) {
        if let sceneDepth = frame.sceneDepth {
            ingestDepth(sceneDepth: sceneDepth, camera: frame.camera, timestamp: frame.timestamp)
        } else if let features = frame.rawFeaturePoints {
            // Fallback: sparse feature points (still useful for UI visibility / non-LiDAR devices).
            ingestFeaturePoints(features, timestamp: frame.timestamp)
        }
    }

    private func ingestFeaturePoints(_ cloud: ARPointCloud, timestamp: TimeInterval) {
        let points = cloud.points
        for i in 0..<points.count {
            append(points[i], timestamp: timestamp)
        }
    }

    private func ingestDepth(sceneDepth: ARDepthData, camera: ARCamera, timestamp: TimeInterval) {
        let depthMap = sceneDepth.depthMap

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return }

        let format = CVPixelBufferGetPixelFormatType(depthMap)

        // Scale intrinsics to depth resolution (depth map is typically lower-res than capturedImage).
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

                // ARKit camera coordinates are right-handed with the camera looking down -Z.
                // Depth maps provide a positive distance along the view direction, so Z should be negative.
                // Image Y increases downward, while camera Y is up => negate Y.
                let X = (Float(x) - cx) / fx * z
                let Y = -((Float(y) - cy) / fy * z)
                let cameraPoint = SIMD4<Float>(X, Y, -z, 1)
                let worldPoint4 = cameraToWorld * cameraPoint
                let worldPoint = SIMD3<Float>(worldPoint4.x, worldPoint4.y, worldPoint4.z)

                append(worldPoint, timestamp: timestamp)
            }
        }
    }

    func shouldUpdateGeometry(at timestamp: TimeInterval) -> Bool {
        if lastGeometryUpdateTimestamp == 0 { return true }
        return (timestamp - lastGeometryUpdateTimestamp) >= config.updateIntervalSeconds
    }

    func makePointGeometryAndMarkUpdated(at timestamp: TimeInterval, cameraTransform: simd_float4x4) -> SCNGeometry? {
        guard !voxels.isEmpty else { return nil }
        lastGeometryUpdateTimestamp = timestamp

        let cameraPos = SIMD3<Float>(cameraTransform.columns.3.x, cameraTransform.columns.3.y, cameraTransform.columns.3.z)
        let r2 = config.renderRadiusMeters * config.renderRadiusMeters

        // Filter: only keep points close to the camera for readability.
        var visible: [(Sample, Float)] = []
        visible.reserveCapacity(min(voxels.count, config.maxVoxels))
        for (_, sample) in voxels {
            let d = sample.position - cameraPos
            let dsq = simd_length_squared(d)
            if dsq <= r2 {
                visible.append((sample, dsq))
            }
        }
        if visible.isEmpty { return nil }

        // If too many points are visible, downsample instead of sorting (sorting large arrays is expensive).
        let maxRender = max(1, config.maxRenderPoints)
        let chosen: [(Sample, Float)]
        if visible.count <= maxRender {
            chosen = visible
        } else {
            let step = max(1, visible.count / maxRender)
            var tmp: [(Sample, Float)] = []
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

        let half = max(0.002, config.billboardSizeMeters) * 0.5
        let right = simd_normalize(SIMD3<Float>(cameraTransform.columns.0.x, cameraTransform.columns.0.y, cameraTransform.columns.0.z)) * half
        let up = simd_normalize(SIMD3<Float>(cameraTransform.columns.1.x, cameraTransform.columns.1.y, cameraTransform.columns.1.z)) * half

        // 4 vertices per point, 2 triangles (6 indices) per point.
        var vertexData = Data(count: n * 4 * MemoryLayout<Float>.size * 3)
        var colorData = Data(count: n * 4 * MemoryLayout<Float>.size * 4)
        var indexData = Data(count: n * 6 * MemoryLayout<UInt32>.size)

        let fade = max(config.fadeSeconds, 0.25)
        vertexData.withUnsafeMutableBytes { raw in
            guard let out = raw.baseAddress?.assumingMemoryBound(to: Float.self) else { return }
            for i in 0..<n {
                let p = chosen[i].0.position
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
                let age = max(0, timestamp - chosen[i].0.lastSeen)
                let t = min(1.0, age / fade)
                // New points are bright, old points fade.
                let alpha = Float(max(0.05, 0.75 * (1.0 - t)))
                let base = i * 16
                for v in 0..<4 {
                    out[base + v * 4 + 0] = 0.1 // R
                    out[base + v * 4 + 1] = 1.0 // G
                    out[base + v * 4 + 2] = 0.1 // B
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
        material.emission.contents = UIColor.green.withAlphaComponent(0.35)
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.blendMode = .alpha
        material.writesToDepthBuffer = false
        // Read depth so points behave like "paint on surfaces" rather than full-screen overlay.
        material.readsFromDepthBuffer = true
        geometry.materials = [material]

        return geometry
    }

    // MARK: - Voxel coverage

    private func append(_ point: SIMD3<Float>, timestamp: TimeInterval) {
        let key = voxelKey(for: point)
        if var existing = voxels[key] {
            // Exponential moving average to reduce jitter.
            existing.position = 0.8 * existing.position + 0.2 * point
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
