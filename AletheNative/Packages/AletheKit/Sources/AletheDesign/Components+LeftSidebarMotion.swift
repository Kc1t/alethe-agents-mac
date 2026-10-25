import SwiftUI

extension Motion {
    public enum SidebarEffect: Sendable {
        case tabColor, tabFill, tabLift, layout, quickNavigation, rowSlot, status
        case chevron, collapse, collapseOpacity, panel, profile, profilePopover, cleanPopover

        public func animation(reduceMotion: Bool, clean: Bool = false) -> Animation? {
            guard !reduceMotion else { return nil }
            let baseDurations: [Self: Double] = [
                .tabColor: 0.14, .tabFill: 0.16, .tabLift: 0.18, .layout: 0.10, .profile: 0.10,
                .status: 0.10, .quickNavigation: 0.15, .rowSlot: 0.12, .chevron: 0.16,
                .collapse: 0.17, .collapseOpacity: 0.13, .panel: 0.26, .profilePopover: 0.12, .cleanPopover: 0.18,
            ]
            let cleanEffects: [Self] = [.tabColor, .tabFill, .tabLift, .layout, .profile, .quickNavigation]
            let duration = clean && cleanEffects.contains(self) ? 0.12 : baseDurations[self] ?? 0.18
            if [.tabLift, .chevron, .collapse, .panel, .cleanPopover].contains(self) {
                return .timingCurve(0.16, 1, 0.3, 1, duration: duration)
            }
            if self == .profilePopover { return .timingCurve(0, 0, 0.58, 1, duration: duration) }
            return .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
        }
    }
}

public struct AletheSidebarMotionTabStyle: ButtonStyle {
    private let selected: Bool
    private let layout: Bool

    public init(isSelected: Bool, layout: Bool = false) {
        selected = isSelected
        self.layout = layout
    }

    public func makeBody(configuration: Configuration) -> some View {
        SidebarMotionTabBody(configuration: configuration, selected: selected, layout: layout)
    }
}

private struct SidebarMotionTabBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let layout: Bool
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    private func animation(_ effect: Motion.SidebarEffect) -> Animation? {
        effect.animation(reduceMotion: metrics.reducesMotion, clean: metrics.style == .clean)
    }

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(metrics.font(size: 14))
            .foregroundStyle(theme[selected || hovering ? .fg : .fgMuted])
            .animation(animation(layout ? .layout : .tabColor), value: hovering)
            .animation(animation(layout ? .layout : .tabColor), value: selected)
            .frame(width: metrics.size(layout ? 24 : 28), height: metrics.size(layout ? 22 : 26))
            .background {
                RoundedRectangle(cornerRadius: metrics.radius(.sm))
                    .fill(theme[.panelHover].opacity(selected || (hovering && !layout) ? 1 : 0))
                    .animation(animation(layout ? .layout : .tabFill), value: hovering)
                    .animation(animation(layout ? .layout : .tabFill), value: selected)
            }
            .overlay {
                RoundedRectangle(cornerRadius: metrics.radius(.sm))
                    .strokeBorder(theme[.border].opacity(selected && !layout ? 1 : 0), lineWidth: metrics.size(1))
                    .animation(animation(.tabFill), value: selected)
            }
            .contentShape(Rectangle())
            .offset(y: metrics.size(hovering && !layout ? -1 : 0))
            .animation(animation(.tabLift), value: hovering)
            .onHover { hovering = $0 && enabled }
    }
}
