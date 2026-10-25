import CoreGraphics
import SwiftUI

public enum Motion {
    public struct SpringSpec: Hashable, Sendable {
        public let response: Double
        public let dampingFraction: Double

        public var animation: Animation {
            .spring(response: response, dampingFraction: dampingFraction)
        }

        public var stiffness: Double { pow(2 * .pi / response, 2) }
        public var damping: Double { 4 * .pi * dampingFraction / response }
    }

    public static let standard = SpringSpec(response: 0.35, dampingFraction: 1.0)
    public static let quick = SpringSpec(response: 0.25, dampingFraction: 1.0)
    public static let momentum = SpringSpec(response: 0.35, dampingFraction: 0.8)

    public static func animation(_ spec: SpringSpec, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : spec.animation
    }

    public static func projectedOffset(velocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
        (velocity / 1000) * decelerationRate / (1 - decelerationRate)
    }

    public static func rubberBand(overshoot: CGFloat, dimension: CGFloat, constant: CGFloat = 0.55) -> CGFloat {
        guard dimension > 0 else { return 0 }
        return (overshoot * dimension * constant) / (dimension + constant * abs(overshoot))
    }

    public static func snapTarget(current: CGFloat, velocity: CGFloat, candidates: [CGFloat]) -> CGFloat? {
        let projected = current + projectedOffset(velocity: velocity)
        return candidates.min { abs($0 - projected) < abs($1 - projected) }
    }
}
