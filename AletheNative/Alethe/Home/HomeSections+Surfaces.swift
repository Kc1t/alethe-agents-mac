import AletheAgents
import AletheDesign
import AletheModel
import SwiftUI

struct HomeWebBadge: View {
    let symbol: String
    let token: ThemeToken
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        Image(systemName: symbol).webProfileSized(15).font(metrics.font(size: 15))
            .foregroundStyle(theme[token])
            .frame(width: metrics.size(26), height: metrics.size(26))
            .background(theme[token].opacity(0.14), in: RoundedRectangle(cornerRadius: metrics.size(7)))
            .overlay(RoundedRectangle(cornerRadius: metrics.size(7))
                .strokeBorder(theme[token].opacity(0.26), lineWidth: metrics.size(1)))
    }
}

struct HomeTimeSurface: ViewModifier {
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    @ViewBuilder func body(content: Content) -> some View {
        if metrics.isWebInterface {
            content.padding(.horizontal, metrics.size(14)).padding(.vertical, metrics.size(13))
                .background(theme[.bgSunken].opacity(0.82), in: RoundedRectangle(cornerRadius: metrics.radius(.lg)))
                .overlay(RoundedRectangle(cornerRadius: metrics.radius(.lg))
                    .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        } else { content.aletheCard() }
    }
}

struct HomeActivityCell: View {
    let level: Int
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var hovered = false

    var body: some View {
        RoundedRectangle(cornerRadius: metrics.size(2))
            .fill(theme[level == 0 ? .bgElevated : .statusWorking].opacity(level == 0 ? 1 : Double(level) * 0.25))
            .frame(height: metrics.size(11))
            .overlay(RoundedRectangle(cornerRadius: metrics.size(2))
                .strokeBorder(theme[.borderStrong].opacity(hovered ? 1 : 0), lineWidth: metrics.size(1)))
            .onHover { hovered = $0 }
    }
}
