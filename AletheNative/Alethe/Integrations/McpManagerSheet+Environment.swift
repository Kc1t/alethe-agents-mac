import AletheDesign
import AletheFoundation
import AletheIntegrations
import AppKit
import SwiftUI

struct McpEnvTable: View {
    let model: McpManagerModel
    let record: McpServerRecord
    let entries: McpEnvMap
    let header: Bool
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        if entries.isEmpty {
            Text("mcp.detail.noEnv")
                .font(metrics.font(.footnote))
                .foregroundStyle(theme[.textTertiary])
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: metrics.space(.l), verticalSpacing: metrics.space(.xs)) {
                ForEach(entries.keys.sorted(), id: \.self) { key in
                    row(key, entries[key]?.view)
                }
            }
        }
    }

    private func row(_ key: String, _ view: McpEnvEntryView?) -> some View {
        let revealKey = model.key(record, key, header: header)
        let shown = model.revealed[revealKey]
        return GridRow {
            Text(verbatim: key)
                .font(metrics.isWebInterface ? metrics.monoFont(size: 11) : metrics.font(.footnote).monospaced())
                .foregroundStyle(theme[.textTertiary])
            HStack(spacing: metrics.space(.xs)) {
                Text(verbatim: shown ?? view?.literal?.preview ?? "")
                    .font(metrics.isWebInterface ? metrics.monoFont(size: 11) : metrics.font(.footnote).monospaced())
                    .textSelection(.enabled)
                    .accessibilityIdentifier("mcp.env.value.\(key)")
                if let from = view?.passthroughFrom {
                    Text(verbatim: format("mcp.passthroughFrom", from))
                        .font(metrics.font(.caption))
                        .foregroundStyle(theme[.textSecondary])
                }
            }
            if let literal = view?.literal, !literal.isEmpty {
                if shown == nil {
                    Button {
                        Task { await model.reveal(record, key: key, header: header) }
                    } label: {
                        Label("mcp.reveal", systemImage: "eye")
                    }
                    .accessibilityIdentifier("mcp.env.reveal.\(key)")
                } else {
                    Button {
                        model.hide(revealKey)
                    } label: {
                        Label("mcp.hide", systemImage: "eye.slash")
                    }
                    .accessibilityIdentifier("mcp.env.hide.\(key)")
                }
            } else {
                Color.clear.frame(width: 0, height: 0)
            }
        }
    }
}
