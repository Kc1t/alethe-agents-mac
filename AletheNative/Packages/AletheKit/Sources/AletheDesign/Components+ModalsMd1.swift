import SwiftUI

public struct AletheInstallActionStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, link, danger, quiet }
    let kind: Kind

    public init(_ kind: Kind = .link) { self.kind = kind }

    public func makeBody(configuration: Configuration) -> some View {
        InstallActionBody(configuration: configuration, kind: kind)
    }

    private struct InstallActionBody: View {
        let configuration: ButtonStyleConfiguration
        let kind: Kind
        @Environment(\.theme) private var theme
        @Environment(\.metrics) private var metrics
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            let hot = hovering && isEnabled
            let radius = metrics.radius(.sm)
            configuration.label
                .font(metrics.font(size: 12))
                .lineLimit(1)
                .foregroundStyle(foreground(hot))
                .padding(.horizontal, metrics.size(10))
                .frame(minWidth: metrics.size(96), minHeight: metrics.size(28))
                .background(background(hot), in: RoundedRectangle(cornerRadius: radius))
                .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border(hot), lineWidth: metrics.size(1)))
                .contentShape(RoundedRectangle(cornerRadius: radius))
                .opacity(isEnabled ? 1 : 0.6)
                .onHover { hovering = $0 }
        }

        private func foreground(_ hot: Bool) -> Color {
            if case .primary = kind { return theme[.accentOn] }
            else if case .link = kind { return theme[hot ? .fg : .fgMuted] }
            else if case .danger = kind { return theme[hot ? .statusOffline : .fgMuted] }
            else { return theme[hot ? .fg : .fgMuted] }
        }

        private func background(_ hot: Bool) -> Color {
            if case .primary = kind { return theme[.accent] }
            else if case .quiet = kind { return hot ? theme[.bgElevated] : .clear }
            else { return theme[.bg] }
        }

        private func border(_ hot: Bool) -> Color {
            if case .primary = kind { return theme[.accent] }
            else if case .link = kind { return theme[hot ? .accent : .border] }
            else if case .danger = kind { return theme[hot ? .statusOffline : .border] }
            else { return hot ? theme[.border] : .clear }
        }
    }
}
