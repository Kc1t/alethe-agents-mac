import SwiftUI

public enum AletheSettingsRowSurface: Equatable, Sendable {
    case standalone, option, remote, plugin, version, metric, task, agent, empty, toolbar

    var horizontal: CGFloat {
        if case .empty = self {
            return 18
        } else if case .toolbar = self {
            return 10
        } else if case .version = self {
            return 14
        } else if case .metric = self {
            return 10
        } else if case .task = self {
            return 10
        } else {
            return 12
        }
    }
    var vertical: CGFloat {
        if case .empty = self {
            return 18
        } else if case .toolbar = self {
            return 8
        } else if case .remote = self {
            return 12
        } else if case .plugin = self {
            return 12
        } else if case .version = self {
            return 12
        } else if case .metric = self {
            return 8
        } else if case .task = self {
            return 8
        } else {
            return 10
        }
    }
}

extension ContainerValues {
    @Entry public var settingsRowSurface: AletheSettingsRowSurface = .standalone
}

extension View {
    public func settingsRowSurface(_ surface: AletheSettingsRowSurface) -> some View {
        containerValue(\.settingsRowSurface, surface)
    }
}

public struct AletheSettingsRowSurfaceModifier: ViewModifier {
    let surface: AletheSettingsRowSurface
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme

    public init(_ surface: AletheSettingsRowSurface) { self.surface = surface }

    public func body(content: Content) -> some View {
        if metrics.isWebInterface, surface != .standalone {
            content
                .padding(.horizontal, metrics.size(surface.horizontal))
                .padding(.vertical, metrics.size(surface.vertical))
                .background(theme[surface == .toolbar ? .panel : .bgSunken],
                    in: RoundedRectangle(cornerRadius: metrics.radius(surface == .metric || surface == .task ? .sm : .md)))
                .overlay(RoundedRectangle(cornerRadius: metrics.radius(surface == .metric || surface == .task ? .sm : .md))
                    .strokeBorder(theme[.border], style: StrokeStyle(lineWidth: metrics.size(1), dash: surface ==
                        .empty ? [metrics.size(3)] : [])))
        } else { content }
    }
}
