import CoreGraphics
import SwiftUI

public struct Metrics: Hashable, Sendable {
    public static let minimumScale: CGFloat = 0.8
    public static let maximumScale: CGFloat = 1.5

    public let scale: CGFloat
    public let style: VisualStyle
    public let interface: InterfaceStyle
    public let reducesMotion: Bool

    public init(scale: CGFloat = 1, style: VisualStyle = .normal, interface: InterfaceStyle = .web,
                reducesMotion: Bool = false) {
        self.scale = min(max(scale, Self.minimumScale), Self.maximumScale)
        self.style = style
        self.interface = interface
        self.reducesMotion = reducesMotion
    }

    public enum Space: CGFloat, CaseIterable, Sendable {
        case xxs = 2, xs = 4, s = 6, m = 8, l = 12, xl = 16, xxl = 20, xxxl = 24, huge = 32
    }

    public enum Radius: CGFloat, CaseIterable, Sendable {
        case sm = 4, md = 8, lg = 14
    }

    public var isWebInterface: Bool { interface == .web }

    public func space(_ space: Space) -> CGFloat { space.rawValue * scale }
    public func radius(_ radius: Radius) -> CGFloat {
        guard style == .clean else { return radius.rawValue * scale }
        let clean: CGFloat = switch radius {
        case .sm: 3
        case .md: 4
        case .lg: 6
        }
        return clean * scale
    }
    public func size(_ points: CGFloat) -> CGFloat { points * scale }
}

extension EnvironmentValues {
    @Entry public var metrics = Metrics()
    @Entry public var theme: Theme = ThemeCatalog.builtin.defaultTheme
}
