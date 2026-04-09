//
//  PlaneCoveragePainter.swift
//  RoomShootDemo
//
//  Created by Codex on 2026/4/2.
//

import Foundation
import UIKit

final class PlaneCoveragePainter {
    struct Config {
        var textureSize: Int = 256
        var brushRadiusPixels: Int = 8
        var minUpdateIntervalSeconds: Double = 0.20
    }

    struct Mapping {
        var centerX: Float
        var centerZ: Float
        var extentX: Float
        var extentZ: Float

        init(centerX: Float, centerZ: Float, extentX: Float, extentZ: Float) {
            self.centerX = centerX
            self.centerZ = centerZ
            self.extentX = max(extentX, 1e-4)
            self.extentZ = max(extentZ, 1e-4)
        }
    }

    private(set) var config: Config

    private let width: Int
    private let height: Int
    private var alpha: [UInt8]
    private var coveredCount: Int = 0
    private var lastUpdateTimestamp: TimeInterval = 0
    private var dirty: Bool = true

    init(config: Config = .init()) {
        self.config = config
        self.width = max(32, config.textureSize)
        self.height = max(32, config.textureSize)
        self.alpha = Array(repeating: 0, count: width * height)
    }

    func reset() {
        alpha = Array(repeating: 0, count: width * height)
        coveredCount = 0
        dirty = true
        lastUpdateTimestamp = 0
    }

    func paint(u: Float, v: Float) {
        // u/v in [0,1]
        let x = Int((Double(u) * Double(width - 1)).rounded())
        let y = Int(((1.0 - Double(v)) * Double(height - 1)).rounded())
        paintPixel(x: x, y: y, radius: config.brushRadiusPixels)
    }

    func shouldUpdateTexture(at timestamp: TimeInterval) -> Bool {
        guard dirty else { return false }
        if lastUpdateTimestamp == 0 { return true }
        return (timestamp - lastUpdateTimestamp) >= config.minUpdateIntervalSeconds
    }

    func makeTextureAndMarkUpdated(at timestamp: TimeInterval) -> UIImage? {
        guard dirty else { return nil }
        lastUpdateTimestamp = timestamp
        dirty = false

        // Build RGBA where RGB is green and A is alpha coverage.
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for i in 0..<(width * height) {
            let a = alpha[i]
            let base = i * 4
            // Premultiply to match premultipliedLast.
            let alphaF = Float(a) / 255.0
            rgba[base + 0] = UInt8(Float(0x14) * alphaF) // R
            rgba[base + 1] = UInt8(Float(0xFF) * alphaF) // G
            rgba[base + 2] = UInt8(Float(0x14) * alphaF) // B
            rgba[base + 3] = a // A
        }

        let data = Data(rgba)
        let provider = CGDataProvider(data: data as CFData)!
        let cg = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
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

    func coverageRatio() -> Double {
        Double(coveredCount) / Double(max(1, alpha.count))
    }

    /// ARPlaneAnchor 的 center/extent 会在跟踪过程中不断更新（扩展/收缩/中心漂移）。
    /// 为避免用户“扫过的涂抹消失”，把旧 UV 贴图内容按新 plane 的映射关系近似重投影到新贴图上。
    func remap(from old: Mapping, to new: Mapping) {
        guard alpha.count == width * height else { return }
        let oldAlpha = alpha
        var newAlpha = [UInt8](repeating: 0, count: width * height)

        // For each texel in NEW UV, find its corresponding local (x,z),
        // then map that local point back into OLD UV and sample.
        for yy in 0..<height {
            let v = Float(height - 1 - yy) / Float(max(1, height - 1)) // match paint(u,v) convention
            for xx in 0..<width {
                let u = Float(xx) / Float(max(1, width - 1))

                let lx = (u - 0.5) * new.extentX + new.centerX
                let lz = (v - 0.5) * new.extentZ + new.centerZ

                let ou = (lx - old.centerX) / old.extentX + 0.5
                let ov = (lz - old.centerZ) / old.extentZ + 0.5
                if ou < 0 || ou > 1 || ov < 0 || ov > 1 { continue }

                let ox = Int((ou * Float(width - 1)).rounded())
                let oy = Int(((1.0 - ov) * Float(height - 1)).rounded())
                if ox < 0 || ox >= width || oy < 0 || oy >= height { continue }
                newAlpha[yy * width + xx] = oldAlpha[oy * width + ox]
            }
        }

        alpha = newAlpha
        coveredCount = alpha.reduce(into: 0) { partial, a in
            if a != 0 { partial += 1 }
        }
        dirty = true
        lastUpdateTimestamp = 0
    }

    // MARK: - Painting

    private func paintPixel(x: Int, y: Int, radius: Int) {
        guard radius > 0 else { return }
        let r2 = radius * radius
        let minX = max(0, x - radius)
        let maxX = min(width - 1, x + radius)
        let minY = max(0, y - radius)
        let maxY = min(height - 1, y + radius)

        for yy in minY...maxY {
            let dy = yy - y
            for xx in minX...maxX {
                let dx = xx - x
                if (dx * dx + dy * dy) > r2 { continue }
                let idx = yy * width + xx
                // Accumulate coverage up to 255.
                let current = alpha[idx]
                let next = min(255, Int(current) + 18)
                if next != Int(current) {
                    if current == 0 { coveredCount += 1 }
                    alpha[idx] = UInt8(next)
                    dirty = true
                }
            }
        }
    }
}
