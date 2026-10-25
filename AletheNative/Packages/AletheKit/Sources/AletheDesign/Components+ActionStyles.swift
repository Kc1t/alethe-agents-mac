import AppKit
import SwiftUI

public struct AletheSidebarTabStyle: ButtonStyle {
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    let bordered: Bool

    public init(isSelected: Bool, width: CGFloat = 28, height: CGFloat = 26, bordered: Bool = true) {
        self.isSelected = isSelected
        self.width = width
        self.height = height
        self.bordered = bordered
    }

    public func makeBody(configuration: Configuration) -> some View {
        LeftSidebarTabBody(configuration: configuration, isSelected: isSelected, width: width, height: height,
                           bordered: bordered)
    }
}

private struct LeftSidebarTabBody: View {
    let configuration: ButtonStyleConfiguration
    let isSelected: Bool
    let width: CGFloat
    let height: CGFloat
    let bordered: Bool
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var hovering = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(metrics.font(size: 14))
            .foregroundStyle(theme[isSelected || hovering ? .fg : .fgMuted])
            .frame(width: metrics.size(width), height: metrics.size(height))
            .background(theme[.panelHover].opacity(isSelected || hovering ? 1 : 0),
                        in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm))
                .strokeBorder(theme[.border].opacity(isSelected && bordered ? 1 : 0),
                              lineWidth: metrics.size(1)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

public struct AletheTitleBarPillStyle: ButtonStyle {
    private let iconOnly: Bool

    public init(iconOnly: Bool = false) { self.iconOnly = iconOnly }

    public func makeBody(configuration: Configuration) -> some View {
        AletheTitleBarPillBody(configuration: configuration, iconOnly: iconOnly)
    }
}

private struct AletheTitleBarPillBody: View {
    let configuration: ButtonStyleConfiguration
    let iconOnly: Bool
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(metrics.monoFont(size: 11, weight: .semibold))
            .foregroundStyle(theme[hovering ? .fg : .fgMuted])
            .padding(.horizontal, metrics.size(iconOnly ? 0 : 8))
            .frame(minWidth: metrics.size(iconOnly ? 26 : 0), minHeight: metrics.size(22))
            .background(theme[hovering || configuration.isPressed ? .panelHover : .bgSunken],
                        in: RoundedRectangle(cornerRadius: metrics.size(8)))
            .overlay(RoundedRectangle(cornerRadius: metrics.size(8))
                .strokeBorder(theme[.borderStrong].opacity(hovering ? 1 : 0), lineWidth: metrics.size(1)))
            .onHover { hovering = $0 }
    }
}

public struct AletheRightSidebarTabStyle: ButtonStyle {
    public var selected: Bool
    public var width: CGFloat
    public var height: CGFloat
    public init(selected: Bool = false, width: CGFloat = 28, height: CGFloat = 26) {
        self.selected = selected
        self.width = width
        self.height = height
    }
    public func makeBody(configuration: Configuration) -> some View {
        RightSidebarTabBody(configuration: configuration, selected: selected, width: width, height: height)
    }
}

private struct RightSidebarTabBody: View {
    let configuration: ButtonStyleConfiguration
    let selected: Bool
    let width: CGFloat
    let height: CGFloat
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    var body: some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(metrics.font(size: 14))
            .foregroundStyle(theme[selected || hovering ? .fg : .fgMuted])
            .frame(width: metrics.size(width), height: metrics.size(height))
            .background(
                theme[selected ? .panel : .panelHover].opacity(selected || hovering ? 1 : 0),
                in: RoundedRectangle(cornerRadius: metrics.radius(.sm))
            )
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: metrics.radius(.sm))
                        .strokeBorder(theme[.borderStrong], lineWidth: metrics.size(1))
                }
            }
            .shadow(
                color: theme[.bgSunken].opacity(selected ? 0.25 : 0),
                radius: metrics.size(2), y: metrics.size(1)
            )
            .contentShape(Rectangle())
            .opacity(enabled ? 1 : 0.5)
            .onHover { hovering = $0 }
    }
}

public struct AlethePanelActionStyle: ButtonStyle {
    public var approval: Bool
    public var accented: Bool
    public init(approval: Bool = false, accented: Bool = false) {
        self.approval = approval
        self.accented = accented
    }
    public func makeBody(configuration: Configuration) -> some View {
        PanelActionBody(configuration: configuration, approval: approval, accented: accented)
    }
}

private struct PanelActionBody: View {
    let configuration: ButtonStyleConfiguration
    let approval: Bool
    let accented: Bool
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false
    var body: some View {
        configuration.label
            .font(metrics.font(size: approval ? 10 : 11, weight: approval ? .semibold : .regular))
            .foregroundStyle(theme[enabled ? .fg : .fgFaint])
            .padding(.horizontal, metrics.size(approval ? 8 : 10))
            .padding(.vertical, approval ? metrics.size(2) : 0)
            .frame(maxWidth: approval ? nil : .infinity)
            .frame(height: approval ? nil : metrics.size(26))
            .background(
                theme[hovering ? .panelHover : accented && enabled ? .accentSoft : .bgElevated]
                    .opacity(approval || hovering || accented && enabled ? 1 : 0),
                in: RoundedRectangle(cornerRadius: metrics.radius(.sm))
            )
            .overlay(
                RoundedRectangle(cornerRadius: metrics.radius(.sm))
                    .strokeBorder(theme[accented && enabled ? .accentBorder : .border], lineWidth: metrics.size(1))
            )
            .contentShape(Rectangle())
            .opacity(approval && !enabled ? 0.5 : 1)
            .onHover { hovering = $0 && enabled }
    }
}

public struct AletheQuickFieldStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        AletheQuickFieldBody(configuration: configuration)
    }
}

private struct AletheQuickFieldBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var hovering = false

    var body: some View {
        configuration.label
            .font(metrics.monoFont(size: 10))
            .foregroundStyle(theme[.fgMuted])
            .padding(.horizontal, metrics.size(8))
            .frame(height: metrics.size(30))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme[hovering ? .panelHover : .bgSunken].opacity(hovering ? 1 : 0.72),
                        in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                .strokeBorder(theme[hovering ? .accentBorder : .border], lineWidth: metrics.size(1)))
            .onHover { hovering = $0 }
    }
}

public struct AletheHomeActionStyle: ButtonStyle {
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(AletheHomeActionLabelStyle())
            .font(metrics.monoFont(size: 11))
            .foregroundStyle(theme[.fgMuted])
            .padding(.horizontal, metrics.size(10))
            .padding(.vertical, metrics.size(7))
            .background(theme[configuration.isPressed ? .bgElevated : .bg].opacity(0.48),
                        in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm))
                .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
    }
}

private struct AletheHomeActionLabelStyle: LabelStyle {
    @Environment(\.metrics) private var metrics

    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: metrics.size(7)) {
            configuration.icon.font(metrics.font(size: 13))
            configuration.title
        }
    }
}

public struct AletheWorkspaceActionStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        WorkspaceActionBody(configuration: configuration)
    }
}

private struct WorkspaceActionBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @State private var hovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(theme[hovering ? .fg : .fgMuted])
            .background(theme[.panelHover].opacity(hovering ? 1 : 0),
                        in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}
