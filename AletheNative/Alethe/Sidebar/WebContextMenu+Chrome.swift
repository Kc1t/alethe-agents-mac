import AletheDesign
import AppKit
import SwiftUI

struct WebMenuChrome<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme

    var body: some View {
        let clean = metrics.style == .clean
        let radius = clean ? metrics.size(4) : metrics.radius(.md)
        let shadow = theme.shadow(.md)
        VStack(alignment: .leading, spacing: 0) { content() }
            .buttonStyle(WebMenuButtonStyle())
            .labelStyle(WebMenuLabelStyle())
            .padding(metrics.size(4))
            .frame(minWidth: metrics.size(180), alignment: .leading)
            .fixedSize()
            .background(theme[.bgElevated], in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
            .shadow(color: clean ? .clear : shadow.color.color, radius: metrics.size(shadow.blur / 2),
                    x: metrics.size(shadow.x), y: metrics.size(shadow.y))
    }
}

struct WebMenuCheckRow: View {
    let title: Text
    let symbol: String
    let selected: Bool
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(spacing: metrics.size(12)) {
            Label { title } icon: { Image(systemName: symbol).webProfileSized(14) }
            Spacer(minLength: 0)
            if selected { Image(systemName: "checkmark").webProfileSized(11) }
        }
    }
}
