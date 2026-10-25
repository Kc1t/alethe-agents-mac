import AletheDesign
import AletheFoundation
import AletheIntegrations
import AppKit
import SwiftUI

struct McpBackupsSheet: View {
    let model: McpManagerModel
    let record: McpServerRecord
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modalsM2Close) private var closeOverlay
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var backups: [ConfigBackup]?
    @State private var restoring: ConfigBackup?

    private func closeWeb() {
        if let closeOverlay { closeOverlay() } else { dismiss() }
    }

    var body: some View {
        if metrics.isWebInterface { webBody } else { nativeBody }
    }

    private var webBody: some View {
        GitWebModal(close: closeWeb) {
            Text("mcp.backups.title")
        } content: {
            VStack(alignment: .leading, spacing: metrics.size(12)) {
                Text(verbatim: record.sourceURL.path(percentEncoded: false))
                    .font(metrics.monoFont(size: 11)).foregroundStyle(theme[.fgMuted])
                    .lineLimit(2).textSelection(.enabled)
                if let backups {
                    if backups.isEmpty {
                        Text("mcp.backups.empty").foregroundStyle(theme[.fgMuted])
                            .frame(maxWidth: .infinity, minHeight: metrics.size(120))
                            .accessibilityIdentifier("mcp.backups.empty")
                    } else {
                        LazyVStack(spacing: metrics.size(8)) {
                            ForEach(Array(backups.enumerated()), id: \.element.id) { index, backup in
                                HStack {
                                    VStack(alignment: .leading, spacing: metrics.size(3)) {
                                        Text(verbatim: backup.createdAt.formatted(date: .abbreviated, time: .standard))
                                            .font(metrics.font(size: 12.5))
                                        Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(backup.size), countStyle: .file))
                                            .font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted])
                                    }
                                    Spacer()
                                    Button("mcp.backups.restore") { restoring = backup }
                                        .disabled(model.busy).accessibilityIdentifier("mcp.backups.restore.\(index)")
                                }.padding(metrics.size(10))
                                .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                                .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                                    .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                            }
                        }.accessibilityIdentifier("mcp.backups.list")
                    }
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: metrics.size(120)) }
                Text("mcp.backups.note").font(metrics.font(size: 11)).foregroundStyle(theme[.fgFaint])
            }
        } footer: {
            Spacer()
            Button("agentInstall.done", action: closeWeb).accessibilityIdentifier("mcp.backups.done")
        }
        .task { backups = await model.backups(for: record) }
        .gitWebSheet(isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), width: 440) {
            if let backup = restoring {
                WebConfirmationModal(title: Text("mcp.backups.confirmTitle"),
                    message: Text(verbatim: format("mcp.backups.confirmMessage", record.sourceURL.lastPathComponent,
                        backup.createdAt.formatted(date: .abbreviated, time: .standard))),
                        confirm: "mcp.backups.restore", confirmIdentifier: "mcp.backups.confirm") {
                    Task { await model.restore(backup, for: record); closeWeb() }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcp.backups")
    }

    private var nativeBody: some View {
        VStack(alignment: .leading, spacing: metrics.space(.l)) {
            Text("mcp.backups.title").font(metrics.font(.title3))
            Text(verbatim: record.sourceURL.path(percentEncoded: false))
                .font(metrics.font(.caption).monospaced())
                .foregroundStyle(theme[.textSecondary])
                .lineLimit(1)
                .truncationMode(.middle)
            if let backups {
                if backups.isEmpty {
                    Text("mcp.backups.empty")
                        .font(metrics.font(.footnote))
                        .foregroundStyle(theme[.textSecondary])
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .accessibilityIdentifier("mcp.backups.empty")
                } else {
                    List(Array(backups.enumerated()), id: \.element.id) { index, backup in
                        HStack {
                            Text(verbatim: backup.createdAt.formatted(date: .abbreviated, time: .standard))
                            Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(backup.size), countStyle: .file))
                                .foregroundStyle(theme[.textSecondary])
                            Spacer()
                            Button("mcp.backups.restore") { restoring = backup }
                                .disabled(model.busy)
                                .accessibilityIdentifier("mcp.backups.restore.\(index)")
                        }
                        .font(metrics.font(.body))
                    }
                    .accessibilityIdentifier("mcp.backups.list")
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Text("mcp.backups.note")
                    .font(metrics.font(.caption))
                    .foregroundStyle(theme[.textTertiary])
                Spacer()
                Button("agentInstall.done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("mcp.backups.done")
            }
        }
        .padding(metrics.space(.xl))
        .frame(width: metrics.size(520), height: metrics.size(380))
        .task { backups = await model.backups(for: record) }
        .confirmationDialog(Text("mcp.backups.confirmTitle"), isPresented: Binding {
            restoring != nil
        } set: { if !$0 { restoring = nil } }, presenting: restoring) { backup in
            Button("mcp.backups.restore", role: .destructive) {
                Task {
                    await model.restore(backup, for: record)
                    dismiss()
                }
            }
            .accessibilityIdentifier("mcp.backups.confirm")
            Button("editor.cancel", role: .cancel) {}
        } message: { backup in
            Text(verbatim: format("mcp.backups.confirmMessage", record.sourceURL.lastPathComponent,
                                  backup.createdAt.formatted(date: .abbreviated, time: .standard)))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcp.backups")
    }
}
