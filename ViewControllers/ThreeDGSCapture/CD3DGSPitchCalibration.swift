import Foundation
import CoreGraphics
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
