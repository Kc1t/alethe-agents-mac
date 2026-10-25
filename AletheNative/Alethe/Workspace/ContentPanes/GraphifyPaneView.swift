import AletheDesign
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct GraphifyPaneView: View {
    let model: GraphifyPaneModel
    let project: ProjectID
    let isFocused: Bool
    let onClose: () -> Void
    let onDrag: (CGSize?) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var pendingRollback: GraphSnapshot?
    @State private var confirmingPrune = false

    static let keepLast = 10

    var body: some View {
        VStack(spacing: 0) {
            if metrics.isWebInterface {
                webToolbar
            } else {
            ContentPaneHeader(symbol: "point.3.connected.trianglepath.dotted", url: model.root, isFocused: isFocused,
                              onClose: onClose, onDrag: onDrag) {
                stats
                Spacer(minLength: 0)
                ContentPaneButton(symbol: "arrow.clockwise", label: "graphify.reload", id: "graphify.reload") { model.reload() }
                if model.state == .loaded {
                    ContentPaneButton(symbol: "arrow.triangle.2.circlepath", label: "graphify.regenerate",
                                      id: "graphify.regenerate") { model.generate() }
                        .disabled(model.isGenerating)
                }
                ContentPaneButton(symbol: "camera", label: "graphify.snapshot", id: "graphify.takeSnapshot") {
                    model.takeSnapshot()
                }
                .disabled(model.state != .loaded)
                ContentPaneButton(symbol: "scissors", label: "graphify.prune", id: "graphify.prune") { confirmingPrune = true }
                    .disabled(model.snapshots.count <= Self.keepLast)
            }
            }
            HStack(spacing: 0) {
                graphArea
                Rectangle().fill(theme[.borderSubtle]).frame(width: metrics.size(1))
                timeline
            }
        }
        .background(theme[.bg])
        .onChange(of: environment.graphify.revisions[model.root, default: 0]) { model.reloadIfChanged() }
        .alert(Text("graphify.rollback.confirm"), isPresented: Binding(
            get: { pendingRollback != nil }, set: { if !$0 { pendingRollback = nil } }
        ), presenting: pendingRollback) { snapshot in
            Button("graphify.rollback.action", role: .destructive) { model.rollback(to: snapshot.id) }
            Button("editor.cancel", role: .cancel) {}
        } message: { _ in
            Text("graphify.rollback.detail")
        }
        .alert(Text(verbatim: format("graphify.prune.confirm", Self.keepLast)), isPresented: $confirmingPrune) {
            Button("graphify.prune.action", role: .destructive) { model.prune(keepLast: Self.keepLast) }
            Button("editor.cancel", role: .cancel) {}
        } message: {
            Text("graphify.prune.detail")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("graphify.pane")
    }

    private var webToolbar: some View {
        HStack(spacing: metrics.size(8)) {
            Text("graphify.title").font(metrics.font(size: 13, weight: .semibold))
                .padding(.trailing, metrics.size(4))
            stats
            Spacer(minLength: 0)
            webAction("graphify.reload", symbol: "arrow.clockwise", id: "graphify.reload") { model.reload() }
                .disabled(model.state == .loading)
            webAction("graphify.snapshot", symbol: "camera", id: "graphify.takeSnapshot") { model.takeSnapshot() }
                .disabled(model.state != .loaded)
            webAction("graphify.prune", symbol: "scissors", id: "graphify.prune") { confirmingPrune = true }
                .disabled(model.snapshots.isEmpty)
            ContentPaneButton(symbol: "xmark", label: "markdown.close", id: "pane.close", webSize: 22, webIconSize: 15, action: onClose)
        }
        .foregroundStyle(theme[.fg])
        .padding(.horizontal, metrics.size(12))
        .padding(.vertical, metrics.size(8))
        .overlay(alignment: .bottom) { Rectangle().fill(theme[.border]).frame(height: metrics.size(1)) }
        .accessibilityIdentifier("pane.header.\(model.root.lastPathComponent)")
    }

    private func webAction(_ title: LocalizedStringKey, symbol: String, id: String,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: metrics.size(6)) {
                Image(systemName: symbol).font(metrics.font(size: 13))
                Text(title).font(metrics.font(size: 12))
            }
            .padding(.horizontal, metrics.size(10))
            .padding(.vertical, metrics.size(4))
            .background(theme[.bgElevated], in: RoundedRectangle(cornerRadius: metrics.size(6)))
            .overlay(RoundedRectangle(cornerRadius: metrics.size(6)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    @ViewBuilder
    private var stats: some View {
        if let graph = model.graph, model.state == .loaded {
            let text = format("graphify.stats", graph.nodeCount, graph.edgeCount)
                + (graph.truncated ? " · " + format("graphify.truncated", graph.nodes.count) : "")
            Text(verbatim: text)
                .font(metrics.isWebInterface ? metrics.font(size: 12) : metrics.font(.caption))
                .foregroundStyle(theme[metrics.isWebInterface ? .fgMuted : .textTertiary])
                .lineLimit(1)
                .accessibilityIdentifier("graphify.stats")
        }
    }

    @ViewBuilder
    private var graphArea: some View {
        if case .loading = model.state {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if case .empty = model.state {
            emptyState
        } else if case .failed = model.state {
            emptyState
        } else if case .loaded = model.state {
            if let graph = model.graph, let layout = model.layout {
                GraphCanvas(model: model, graph: graph, layout: layout, onOpenFile: openFile)
            } else {
                VStack(spacing: metrics.space(.m)) {
                    ProgressView()
                    Text(verbatim: format("graphify.layingOut", model.graph?.nodes.count ?? 0))
                        .font(metrics.font(.footnote))
                        .foregroundStyle(theme[.textSecondary])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("graphify.layingOut")
            }
        }
    }

    private var emptyState: some View {
        let unavailable = !model.isAvailable
        return VStack(spacing: metrics.space(.m)) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(metrics.font(.largeTitle))
                .foregroundStyle(theme[.textTertiary])
            Text(unavailable ? LocalizedStringKey("graphify.unavailableTitle") : "graphify.emptyTitle")
                .font(metrics.font(.headline))
                .foregroundStyle(theme[.textPrimary])
            Group {
                if case .failed(let message) = model.state {
                    Text(verbatim: message)
                } else if let failure = model.generationFailure {
                    Text(verbatim: failure)
                } else {
                    Text(unavailable ? LocalizedStringKey("graphify.unavailable") : "graphify.emptyDescription")
                }
            }
            .font(metrics.font(.footnote))
            .foregroundStyle(theme[.textSecondary])
            .multilineTextAlignment(.center)
            .frame(maxWidth: metrics.size(360))
            if model.isGenerating {
                HStack(spacing: metrics.space(.s)) {
                    ProgressView().controlSize(.small)
                    Text("graphify.generating").font(metrics.font(.footnote)).foregroundStyle(theme[.textSecondary])
                    Button("editor.cancel") { model.cancelGeneration() }
                        .accessibilityIdentifier("graphify.cancelGeneration")
                }
            } else {
                Button("graphify.generate") { model.generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(unavailable)
                    .accessibilityIdentifier("graphify.generate")
            }
        }
        .padding(metrics.space(.xl))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("graphify.empty")
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: metrics.space(.s)) {
            Text("graphify.snapshots")
                .font(metrics.font(.caption).weight(.semibold))
                .foregroundStyle(theme[.textSecondary])
            if let error = model.actionError {
                Text(verbatim: error)
                    .font(metrics.font(.caption))
                    .foregroundStyle(theme[.statusStopped])
                    .accessibilityIdentifier("graphify.actionError")
            }
            if model.snapshots.isEmpty {
                Text("graphify.noSnapshots")
                    .font(metrics.font(.caption))
                    .foregroundStyle(theme[.textTertiary])
                Spacer(minLength: 0)
            } else {
                if let diff = model.diff, model.comparedSnapshot != nil {
                    diffSummary(diff)
                } else {
                    Text("graphify.compareHint")
                        .font(metrics.font(.caption))
                        .foregroundStyle(theme[.textTertiary])
                        .fixedSize(horizontal: false, vertical: true)
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                        ForEach(model.snapshots) { snapshot in
                            snapshotRow(snapshot)
                        }
                    }
                }
            }
        }
        .padding(metrics.space(.m))
        .frame(width: metrics.size(210))
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme[.bgSunken])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("graphify.timeline")
    }

    private func diffSummary(_ diff: GraphDiff) -> some View {
        VStack(alignment: .leading, spacing: metrics.space(.xs)) {
            Text(verbatim: diff.isEmpty ? String(localized: "graphify.diff.none")
                 : format("graphify.diff", diff.nodesAdded, diff.nodesRemoved, diff.edgesAdded, diff.edgesRemoved))
                .font(metrics.font(.caption))
                .foregroundStyle(theme[.textPrimary])
                .fixedSize(horizontal: false, vertical: true)
                .id(model.comparedSnapshot)
                .accessibilityIdentifier("graphify.diff")
            Button("graphify.clearComparison") { model.compare(with: nil) }
                .buttonStyle(.link)
                .font(metrics.font(.caption))
                .accessibilityIdentifier("graphify.clearComparison")
        }
        .padding(metrics.space(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: metrics.radius(.sm)).fill(theme[.statusActive].opacity(0.12)))
    }

    private func snapshotRow(_ snapshot: GraphSnapshot) -> some View {
        let compared = model.comparedSnapshot == snapshot.id
        return HStack(spacing: metrics.space(.xs)) {
            Button {
                model.compare(with: compared ? nil : snapshot.id)
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    Text(snapshot.createdAt, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(metrics.font(.caption).weight(compared ? .semibold : .regular))
                        .foregroundStyle(theme[compared ? .accent : .textPrimary])
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(snapshot.sizeBytes), countStyle: .file))
                        .font(metrics.font(.caption))
                        .foregroundStyle(theme[.textTertiary])
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("graphify.snapshot.\(snapshot.id)")
            ContentPaneButton(symbol: "arrow.uturn.backward", label: "graphify.rollback",
                              id: "graphify.rollback.\(snapshot.id)") { pendingRollback = snapshot }
        }
        .padding(.horizontal, metrics.space(.s))
        .padding(.vertical, metrics.space(.xs))
        .background(RoundedRectangle(cornerRadius: metrics.radius(.sm)).fill(compared ? theme[.accentFaint] : .clear))
    }

    private func openFile(_ relative: String) {
        let url = relative.hasPrefix("/") ? URL(filePath: relative) : model.root.appending(path: relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            NSSound.beep()
            return
        }
        if let content = PaneContent.forFile(url.path) {
            environment.open(content, in: project)
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
