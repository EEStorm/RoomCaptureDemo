import Foundation
import CoreGraphics
import CoreVideo
import UIKit

@objcMembers
final class CD3DGSPitchCalibration: NSObject {
    static func pitchDegrees(gravityX: Double,
                             gravityY: Double,
                             gravityZ: Double,
                             interfaceOrientation: UIInterfaceOrientation) -> CGFloat {
        switch interfaceOrientation {
        case .landscapeLeft:
            return atan2(gravityZ, gravityX) * 180.0 / .pi
        case .landscapeRight:
            return atan2(gravityZ, -gravityX) * 180.0 / .pi
        case .portraitUpsideDown:
            return atan2(-gravityZ, gravityY) * 180.0 / .pi
        case .portrait, .unknown:
            fallthrough
        default:
            return atan2(gravityZ, -gravityY) * 180.0 / .pi
        }
    }

    static func rollDegrees(gravityX: Double,
                            gravityY: Double,
                            gravityZ: Double,
                            interfaceOrientation: UIInterfaceOrientation) -> CGFloat {
        switch interfaceOrientation {
        case .landscapeLeft:
            return atan2(gravityY, -gravityZ) * 180.0 / .pi
        case .landscapeRight:
            return atan2(-gravityY, -gravityZ) * 180.0 / .pi
        case .portraitUpsideDown:
            return atan2(gravityX, -gravityY) * 180.0 / .pi
        case .portrait, .unknown:
            fallthrough
        default:
            return atan2(gravityX, -gravityY) * 180.0 / .pi
        }
    }

    static func offsetY(forRelativePitchDegrees relativePitchDegrees: CGFloat,
                        threshold: CGFloat,
                        maxOffset: CGFloat) -> CGFloat {
        guard threshold > 0 else { return 0 }
        let clampedPitch = max(-threshold, min(threshold, relativePitchDegrees))
        return (clampedPitch / threshold) * maxOffset
    }

    static func offsetX(forRelativeRollDegrees relativeRollDegrees: CGFloat,
                        threshold: CGFloat,
                        maxOffset: CGFloat) -> CGFloat {
        guard threshold > 0 else { return 0 }
        let clampedRoll = max(-threshold, min(threshold, relativeRollDegrees))
        return (clampedRoll / threshold) * maxOffset
    }

    static func isWarningActive(forRelativePitchDegrees relativePitchDegrees: CGFloat,
                                threshold: CGFloat) -> Bool {
        abs(relativePitchDegrees) >= threshold
    }

    static func isWarningActive(forRelativeRollDegrees relativeRollDegrees: CGFloat,
                                threshold: CGFloat) -> Bool {
        abs(relativeRollDegrees) >= threshold
    }

    static func warningToastText(pitchWarningActive: Bool,
                                 rollWarningActive: Bool,
                                 angularSpeedWarningActive: Bool) -> String? {
        if pitchWarningActive {
            return "请保持手机水平"
        }
        if rollWarningActive {
            return "请保持手机垂直"
        }
        if angularSpeedWarningActive {
            return "请放慢转动速度"
        }
        return nil
    }
}

@objc enum CD3DGSBlurState: Int {
    case clear = 0
    case soft = 1
    case blurry = 2
}

@objcMembers
final class CD3DGSBlurMonitor: NSObject {
    private let windowSize = 5
    private let clearThreshold: CGFloat = 45.0
    private let softThreshold: CGFloat = 20.0
    private var recentVariances: [CGFloat] = []
    private(set) var currentState: CD3DGSBlurState = .clear
    private(set) var currentAverageVariance: CGFloat = 0

    func reset() {
        recentVariances.removeAll(keepingCapacity: true)
        currentState = .clear
        currentAverageVariance = 0
    }

    func update(withLaplacianVariance variance: CGFloat) -> CD3DGSBlurState {
        recentVariances.append(max(0, variance))
        if recentVariances.count > windowSize {
            recentVariances.removeFirst(recentVariances.count - windowSize)
        }

        let average = recentVariances.reduce(0, +) / CGFloat(recentVariances.count)
        currentAverageVariance = average

        if recentVariances.count == 1 {
            currentState = .clear
            return currentState
        }

        if average >= clearThreshold {
            currentState = .clear
        } else if average >= softThreshold {
            currentState = .soft
        } else if recentVariances.count >= 3 {
            currentState = .blurry
        } else {
            currentState = .soft
        }
        return currentState
    }

    @objc(statusTextForState:)
    static func statusText(for state: CD3DGSBlurState) -> String {
        switch state {
        case .clear:
            return "画面清晰"
        case .soft:
            return "画面偏糊"
        case .blurry:
            return "画面模糊"
        @unknown default:
            return "画面清晰"
        }
    }

    @objc(laplacianVarianceForLumaBytes:width:height:bytesPerRow:)
    static func laplacianVariance(forLumaBytes lumaBytes: [UInt8],
                                  width: Int,
                                  height: Int,
                                  bytesPerRow: Int) -> CGFloat {
        guard width > 2, height > 2, bytesPerRow > 0, lumaBytes.count >= bytesPerRow * height else {
            return 0
        }

        return lumaBytes.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return CGFloat(0)
            }
            return laplacianVariance(baseAddress: baseAddress,
                                     width: width,
                                     height: height,
                                     bytesPerRow: bytesPerRow)
        }
    }

    @objc(laplacianVarianceForPixelBuffer:)
    static func laplacianVariance(for pixelBuffer: CVPixelBuffer) -> CGFloat {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0)
        let bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0)
        guard let baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0) else {
            return 0
        }
        return laplacianVariance(baseAddress: baseAddress.assumingMemoryBound(to: UInt8.self),
                                 width: width,
                                 height: height,
                                 bytesPerRow: bytesPerRow)
    }

    private static func laplacianVariance(baseAddress: UnsafePointer<UInt8>,
                                          width: Int,
                                          height: Int,
                                          bytesPerRow: Int) -> CGFloat {
        guard width > 2, height > 2 else { return 0 }

        var count = 0
        var sum = 0.0
        var sumSquares = 0.0

        for y in stride(from: 1, to: height - 1, by: 4) {
            let previousRow = baseAddress.advanced(by: (y - 1) * bytesPerRow)
            let currentRow = baseAddress.advanced(by: y * bytesPerRow)
            let nextRow = baseAddress.advanced(by: (y + 1) * bytesPerRow)

            for x in stride(from: 1, to: width - 1, by: 4) {
                let center = Double(currentRow[x])
                let response = Double(previousRow[x])
                    + Double(nextRow[x])
                    + Double(currentRow[x - 1])
                    + Double(currentRow[x + 1])
                    - 4.0 * center

                sum += response
                sumSquares += response * response
                count += 1
            }
        }

        guard count > 0 else { return 0 }

        let mean = sum / Double(count)
        let variance = max(0, sumSquares / Double(count) - mean * mean)
        return CGFloat(variance)
    }
}
