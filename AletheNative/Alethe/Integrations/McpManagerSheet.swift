import AletheDesign
import AletheFoundation
import AletheIntegrations
import AppKit
import SwiftUI

struct McpManagerSheet: View {
    let route: McpManagerRoute
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modalsM2Close) private var closeOverlay
    @Environment(\.metrics) private var metrics

    var body: some View {
        Group {
            if let model = environment.mcp {
                McpManagerContent(model: model, route: route, skillStore: environment.skillStore,
                                  folder: selectedFolder, dismiss: { if let closeOverlay { closeOverlay() } else { dismiss() } })
            } else {
                ProgressView()
            }
        }
        .frame(width: metrics.isWebInterface ? nil : metrics.size(920), height: metrics.isWebInterface ? nil : metrics.size(620))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcp.manager")
    }

    private var selectedFolder: String? {
        environment.workspace.flatMap { model in
            model.document.workspace.selectedProjectID.flatMap(model.document.project)?.folder
        }
    }
}

struct McpRecordTarget: Identifiable {
    let record: McpServerRecord
    var id: String { "\(record.agent.rawValue):\(record.sourceKind.rawValue):\(record.sourceURL.path):\(record.server.name)" }
}

private struct McpManagerContent: View {
    let model: McpManagerModel
    let route: McpManagerRoute
    let skillStore: SkillStore
    let folder: String?
    let dismiss: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var tab = McpManagerRoute.Tab.servers
    @State private var query = ""
    @State private var selection: String?
    @State private var adding = false
    @State private var editing: McpRecordTarget?
    @State private var backupsFor: McpRecordTarget?
    @State private var removal: [McpServerRecord]?
    @State private var routed = false

    private var visible: [McpServerGroup] { model.groups.filter { $0.matches(query) } }

    private var active: McpServerGroup? {
        visible.first { $0.name == selection } ?? model.groups.first { $0.name == selection } ?? visible.first
    }

    var body: some View {
        Group {
            if metrics.isWebInterface { webBody } else { nativeBody }
        }
        .task {
            guard !routed else { return }
            routed = true
            tab = route.tab
            selection = route.server
            model.setRepository(folder)
            if route.add { adding = true }
            await model.refresh()
        }
        .onDisappear { model.close() }
        .gitWebSheet(isPresented: $adding, width: 620) {
            McpServerEditor(model: model, editing: nil)
        }
        .gitWebSheet(item: $editing, width: 620) { target in
            McpServerEditor(model: model, editing: target.record)
        }
        .gitWebSheet(item: $backupsFor, width: 520) { target in
            McpBackupsSheet(model: model, record: target.record)
        }
        .gitWebSheet(isPresented: Binding(get: { metrics.isWebInterface && removal != nil },
            set: { if !$0 { removal = nil } }), width: 420) {
            if let records = removal {
                WebConfirmationModal(title: Text("mcp.remove.title"), message: Text(verbatim: removalMessage(records)),
                    confirm: "mcp.remove.action", confirmIdentifier: "mcp.remove.confirm") { Task { await model.remove(records) } }
            }
        }
        .confirmationDialog(Text("mcp.remove.title"), isPresented: Binding {
            !metrics.isWebInterface && removal != nil
        } set: { if !$0 { removal = nil } }, presenting: removal) { records in
            Button("mcp.remove.action", role: .destructive) { Task { await model.remove(records) } }
                .accessibilityIdentifier("mcp.remove.confirm")
            Button("editor.cancel", role: .cancel) {}
        } message: { records in Text(verbatim: removalMessage(records)) }
    }

    private var webBody: some View {
        ModalsM2WebModal(title: Text("modalsM2.mcp.title"), close: dismiss, width: 880) {
            VStack(spacing: 0) {
                HStack(spacing: metrics.size(6)) {
                    webTab(.servers, title: "mcp.tab.servers")
                    webTab(.skills, title: "mcp.tab.skills")
                    Spacer()
                }
                .accessibilityIdentifier("mcp.manager.tab")
                .padding(.bottom, metrics.size(8))
                .overlay(alignment: .bottom) { Rectangle().fill(theme[.border]).frame(height: metrics.size(1)) }
                .padding(.bottom, metrics.size(16))
                if tab == .skills {
                    SkillsBrowser(model: SkillsBrowserModel(store: skillStore)).frame(height: metrics.size(380))
                } else {
                    HStack(spacing: metrics.size(14)) {
                        webSidebar.frame(width: metrics.size(232))
                        detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }.frame(height: metrics.size(380))
                }
            }
        } footer: {
            VStack(alignment: .leading, spacing: metrics.size(2)) {
                Text(verbatim: scopeNote).accessibilityIdentifier("mcp.manager.scope")
                if let error = model.error {
                    Text(verbatim: error).foregroundStyle(theme[.statusStopped]).accessibilityIdentifier("mcp.manager.error")
                }
                if let note = model.note { Text(verbatim: note).accessibilityIdentifier("mcp.manager.note") }
            }
            .font(metrics.font(size: 11.5)).foregroundStyle(theme[.fgFaint]).lineLimit(1)
            Spacer(minLength: 0)
            if model.undoLabel != nil {
                Button("mcp.undo") { Task { await model.performUndo() } }
                    .disabled(model.busy).accessibilityIdentifier("mcp.manager.undo")
            }
            Button("agentInstall.done", action: dismiss).accessibilityIdentifier("mcp.manager.done")
        }
    }

    private func webTab(_ value: McpManagerRoute.Tab, title: LocalizedStringKey) -> some View {
        Button { tab = value } label: {
            Text(title).font(metrics.font(size: 12, weight: tab == value ? .semibold : .medium))
                .padding(.horizontal, metrics.size(12)).padding(.vertical, metrics.size(6))
                .background(theme[.accentFaint].opacity(tab == value ? 1 : 0), in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                    .strokeBorder(theme[.accentBorder].opacity(tab == value ? 1 : 0), lineWidth: metrics.size(1)))
        }.buttonStyle(.plain).foregroundStyle(theme[tab == value ? .fg : .fgMuted])
            .accessibilityAddTraits(tab == value ? [.isSelected] : [])
    }

    private var webSidebar: some View {
        VStack(spacing: metrics.size(8)) {
            HStack(spacing: metrics.size(7)) {
                Image(systemName: "magnifyingglass").font(metrics.font(size: 13)).foregroundStyle(theme[.fgFaint])
                TextField(text: $query, prompt: Text("mcp.search")) { Text("mcp.search") }
                    .accessibilityIdentifier("mcp.manager.search")
            }.modifier(ModalsM2Input())
            Button { adding = true } label: {
                Label("mcp.addServer", systemImage: "plus").font(metrics.font(size: 12))
                    .frame(maxWidth: .infinity).padding(.horizontal, metrics.size(10)).padding(.vertical, metrics.size(6))
                    .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                        .strokeBorder(theme[.borderStrong], style: StrokeStyle(lineWidth: metrics.size(1), dash: [metrics.size(3)])))
            }.buttonStyle(.plain).foregroundStyle(theme[.fgMuted])
                .disabled(model.writableAgents.isEmpty || model.busy).accessibilityIdentifier("mcp.manager.add")
            if model.snapshots == nil { ProgressView() }
            ScrollView {
                VStack(spacing: metrics.size(2)) {
                    ForEach(visible, id: \.name) { group in
                        Button { selection = group.name } label: {
                            HStack(spacing: metrics.size(8)) {
                                Text(verbatim: group.name).lineLimit(1)
                                Spacer(minLength: 0)
                                Text(verbatim: "\(group.agents.count)").font(metrics.font(size: 11)).foregroundStyle(theme[.fgFaint])
                            }
                        }.buttonStyle(ModalsM2RowStyle(selected: active?.name == group.name))
                            .accessibilityIdentifier("mcp.manager.row.\(group.name)")
                    }
                }
            }.accessibilityIdentifier("mcp.manager.list")
        }
        .padding(.trailing, metrics.size(14))
        .overlay(alignment: .trailing) { Rectangle().fill(theme[.borderSubtle]).frame(width: metrics.size(1)) }
    }

    private var nativeBody: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("mcp.view", selection: $tab) {
                    Text("mcp.tab.servers").tag(McpManagerRoute.Tab.servers)
                    Text("mcp.tab.skills").tag(McpManagerRoute.Tab.skills)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("mcp.manager.tab")
                Spacer()
                if tab == .servers {
                    Text(verbatim: scopeNote)
                        .font(metrics.font(.caption))
                        .foregroundStyle(theme[.textSecondary])
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .accessibilityIdentifier("mcp.manager.scope")
                }
            }
            .padding(metrics.space(.l))
            Divider()
            if tab == .skills {
                SkillsBrowser(model: SkillsBrowserModel(store: skillStore))
            } else {
                HStack(spacing: 0) {
                    sidebar.frame(width: metrics.size(240))
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            footer
        }
    }

    private var scopeNote: String {
        if model.effectiveScope == .project, let repository = model.repository {
            return format("mcp.scope.projectNote", repository.path(percentEncoded: false))
        }
        return String(localized: "mcp.scope.globalNote")
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: metrics.space(.s)) {
            TextField(text: $query, prompt: Text("mcp.search")) { Text("mcp.search") }
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("mcp.manager.search")
            Button {
                adding = true
            } label: {
                Label("mcp.addServer", systemImage: "plus").frame(maxWidth: .infinity)
            }
            .disabled(model.writableAgents.isEmpty || model.busy)
            .accessibilityIdentifier("mcp.manager.add")
            if model.snapshots == nil {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if visible.isEmpty {
                Text((model.groups.isEmpty ? "mcp.empty.title" : "mcp.noMatch") as LocalizedStringKey)
                    .font(metrics.font(.footnote))
                    .foregroundStyle(theme[.textSecondary])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(visible, id: \.name, selection: $selection) { group in
                    HStack(spacing: metrics.space(.xs)) {
                        Text(verbatim: group.name).lineLimit(1).truncationMode(.middle)
                        if group.hasDisabled {
                            Image(systemName: "pause.circle").foregroundStyle(theme[.textTertiary])
                                .accessibilityLabel(Text("mcp.badge.disabled"))
                        }
                        Spacer(minLength: 0)
                        Text(verbatim: "\(group.agents.count)")
                            .font(metrics.font(.caption).monospacedDigit())
                            .foregroundStyle(theme[.textTertiary])
                    }
                    .font(metrics.font(.body))
                    .tag(group.name)
                    .accessibilityIdentifier("mcp.manager.row.\(group.name)")
                }
                .listStyle(.sidebar)
                .accessibilityIdentifier("mcp.manager.list")
            }
        }
        .padding(metrics.space(.m))
    }

    @ViewBuilder private var detail: some View {
        if let group = active {
            McpServerDetail(model: model, group: group,
                            onEdit: { editing = McpRecordTarget(record: $0) },
                            onBackups: { backupsFor = McpRecordTarget(record: $0) },
                            onRemove: { removal = $0 })
                .id(group.name)
        } else if model.snapshots != nil {
            ContentUnavailableView {
                Label((model.groups.isEmpty ? "mcp.empty.title" : "mcp.noMatch") as LocalizedStringKey, systemImage: "powerplug")
            } description: {
                if model.groups.isEmpty { Text("mcp.empty.detail") }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: metrics.space(.m)) {
            VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                if let error = model.error {
                    Label { Text(verbatim: error).textSelection(.enabled) } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(theme[.statusStopped])
                    .accessibilityIdentifier("mcp.manager.error")
                }
                if let note = model.note {
                    Text(verbatim: note)
                        .foregroundStyle(theme[.textSecondary])
                        .accessibilityIdentifier("mcp.manager.note")
                }
            }
            .font(metrics.font(.footnote))
            .lineLimit(3)
            Spacer()
            if model.undoLabel != nil {
                Button("mcp.undo") { Task { await model.performUndo() } }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(model.busy)
                    .help(Text(verbatim: model.undoLabel ?? ""))
                    .accessibilityIdentifier("mcp.manager.undo")
            }
            if model.busy { ProgressView().controlSize(.small) }
            Button("agentInstall.done") { dismiss() }
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("mcp.manager.done")
        }
        .padding(metrics.space(.l))
    }

    private func removalMessage(_ records: [McpServerRecord]) -> String {
        guard let first = records.first else { return "" }
        var message = format("mcp.remove.message", first.server.name,
                             McpManagerModel.labels(Array(Set(records.map(\.agent))).sorted { $0.rawValue < $1.rawValue }))
        message += "\n\n" + records.map { $0.sourceURL.path(percentEncoded: false) }.joined(separator: "\n")
        if let owner = records.compactMap(\.managedByImport).first {
            message += "\n\n" + format("mcp.importedHint", owner)
        }
        return message
    }
}
