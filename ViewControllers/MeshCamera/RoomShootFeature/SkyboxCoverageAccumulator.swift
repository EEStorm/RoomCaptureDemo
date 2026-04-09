//
//  SkyboxCoverageAccumulator.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/2.
//
//  Non‑LiDAR friendly coverage preview:
//  - Does NOT try to reconstruct real surfaces.
//  - Marks which viewing directions (camera frustum) have been observed.
//  - Implementation: project view rays onto a unit sphere and paint an equirectangular texture.
//

import ARKit
import Foundation
import UIKit

final class SkyboxCoverageAccumulator {
    struct Config {
        // 2:1 equirectangular texture.
        var width: Int = 512
        var height: Int = 256

        // Brush
        var brushRadiusPixels: Int = 5
        var alphaStep: UInt8 = 26

        // Sampling in screen space (per paint tick).
        var sampleCols: Int = 9
        var sampleRows: Int = 13
        var margin: CGFloat = 0.12

        // Throttle texture regeneration (heavy if too frequent).
        var minUpdateIntervalSeconds: Double = 0.12
    }

    private(set) var config: Config

    private var alpha: [UInt8]
    private var coveredCount: Int = 0
    private var dirty: Bool = true
    private var lastUpdateTimestamp: TimeInterval = 0

    init(config: Config = .init()) {
        self.config = config
        let w = max(64, config.width)
        let h = max(32, config.height)
        self.alpha = Array(repeating: 0, count: w * h)
    }

    var width: Int { max(64, config.width) }
    var height: Int { max(32, config.height) }

    func reset() {
        alpha = Array(repeating: 0, count: width * height)
        coveredCount = 0
        dirty = true
        lastUpdateTimestamp = 0
    }

    func shouldUpdateTexture(at timestamp: TimeInterval) -> Bool {
        guard dirty else { return false }
        if lastUpdateTimestamp == 0 { return true }
        return (timestamp - lastUpdateTimestamp) >= config.minUpdateIntervalSeconds
    }

    func coverageRatio() -> Double {
        Double(coveredCount) / Double(max(1, alpha.count))
    }

    func paintDirections(from frame: ARFrame, in viewBounds: CGRect, interfaceOrientation: UIInterfaceOrientation) {
        guard viewBounds.width > 0, viewBounds.height > 0 else { return }

        let cols = max(1, config.sampleCols)
        let rows = max(1, config.sampleRows)
        let margin = max(0, min(0.45, config.margin))

        let minX = viewBounds.minX + viewBounds.width * margin
        let maxX = viewBounds.maxX - viewBounds.width * margin
        let minY = viewBounds.minY + viewBounds.height * margin
        let maxY = viewBounds.maxY - viewBounds.height * margin

        let viewport = CGSize(width: viewBounds.width, height: viewBounds.height)
        // ARFrame.displayTransform maps normalized image -> normalized view.
        // We invert it to map normalized view -> normalized image (handles aspect/orientation).
        let viewToImage = frame.displayTransform(for: interfaceOrientation, viewportSize: viewport).inverted()

        let intr = frame.camera.intrinsics
        let fx = intr.columns.0.x
        let fy = intr.columns.1.y
        let cx = intr.columns.2.x
        let cy = intr.columns.2.y
        let imageRes = frame.camera.imageResolution

        let cameraToWorld = frame.camera.transform

        for r in 0..<rows {
            let ty = CGFloat(r) / CGFloat(max(1, rows - 1))
            let y = minY + (maxY - minY) * ty
            for c in 0..<cols {
                let tx = CGFloat(c) / CGFloat(max(1, cols - 1))
                let x = minX + (maxX - minX) * tx

                // Normalized view -> normalized image.
                let vn = CGPoint(x: x / viewBounds.width, y: y / viewBounds.height)
                let inN = vn.applying(viewToImage)

                let ix = Float(inN.x) * Float(imageRes.width)
                let iy = Float(inN.y) * Float(imageRes.height)

                // Build ray direction in camera coordinates.
                // Camera looks down -Z. Image Y increases downward => negate.
                let X = (ix - cx) / fx
                let Y = -((iy - cy) / fy)
                let dirCam = simd_normalize(SIMD3<Float>(X, Y, -1))

                // Rotate to world (w=0).
                let dirWorld4 = simd_mul(cameraToWorld, SIMD4<Float>(dirCam.x, dirCam.y, dirCam.z, 0))
                let dirWorld = simd_normalize(SIMD3<Float>(dirWorld4.x, dirWorld4.y, dirWorld4.z))

                paint(worldDirection: dirWorld)
            }
        }
    }

    func makeTextureAndMarkUpdated(at timestamp: TimeInterval) -> UIImage? {
        guard dirty else { return nil }
        lastUpdateTimestamp = timestamp
        dirty = false

        let w = width
        let h = height

        var rgba = [UInt8](repeating: 0, count: w * h * 4)
        for i in 0..<(w * h) {
            let a = alpha[i]
            let base = i * 4
            let alphaF = Float(a) / 255.0
            rgba[base + 0] = UInt8(Float(0x14) * alphaF)
            rgba[base + 1] = UInt8(Float(0xFF) * alphaF)
            rgba[base + 2] = UInt8(Float(0x14) * alphaF)
            rgba[base + 3] = a
        }

        let data = Data(rgba)
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: w,
            height: h,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
        guard let cg else { return nil }
        return UIImage(cgImage: cg)
    }

    // MARK: - Painting (equirectangular)

    private func paint(worldDirection d: SIMD3<Float>) {
        guard d.x.isFinite, d.y.isFinite, d.z.isFinite else { return }
        let lon = atan2(d.x, -d.z) // forward (-Z) => 0
        let lat = asin(max(-1, min(1, d.y)))

        let u = Float(lon / (2.0 * .pi) + 0.5) // [0,1]
        let v = Float(0.5 - (lat / .pi))        // [0,1] (up => 0)

        let x = Int((u * Float(width - 1)).rounded())
        let y = Int((v * Float(height - 1)).rounded())
        paintPixel(x: x, y: y, radius: config.brushRadiusPixels)
    }

    private func paintPixel(x: Int, y: Int, radius: Int) {
        guard radius > 0 else { return }
        let w = width
        let h = height
        let r2 = radius * radius

        // Wrap horizontally (u seam), clamp vertically.
        let minY = max(0, y - radius)
        let maxY = min(h - 1, y + radius)

        for yy in minY...maxY {
            let dy = yy - y
            for dx in -radius...radius {
                if (dx * dx + dy * dy) > r2 { continue }
                var xx = x + dx
                if xx < 0 { xx += w }
                if xx >= w { xx -= w }
                let idx = yy * w + xx
                let current = alpha[idx]
                let next = min(255, Int(current) + Int(config.alphaStep))
                if next != Int(current) {
                    if current == 0 { coveredCount += 1 }
                    alpha[idx] = UInt8(next)
                    dirty = true
                }
            }
        }
    }
}
