import AletheDesign
import AletheModel
import AlethePluginKit
import AppKit
import SwiftUI

struct FindJumpSheet: View {
    let workspace: WorkspaceModel
    let undoManager: UndoManager?
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var query = ""
    @State private var cursor = 0
    @FocusState private var fieldFocused: Bool

    static let limit = 50

    enum Item: Hashable {
        case terminal(TabID)
        case project(ProjectID)
        case command(JumpCommand)
        case plugin(String)
    }

    private var document: WorkspaceDocument { workspace.document }

    private var pluginCommands: [CommandContribution] {
        (environment.plugins?.contributions.commands ?? []).filter { $0.placement.contains(.findJump) }
    }

    private var items: [Item] {
        let terminals = document.projects.flatMap { project in project.panes.flatMap { $0.tabs.map { Item.terminal($0.id) } } }
        let projects = document.projects.map { Item.project($0.id) }
        let commands = JumpCommand.allCases.filter { $0.isAvailable(document) }.map(Item.command)
        let plugin = pluginCommands.map { Item.plugin($0.id) }
        let all = terminals + projects + commands + plugin
        return Array(FuzzyMatch.rank(all, query: query, fields: fields).map(\.item).prefix(Self.limit))
    }

    var body: some View {
        let results = items
        VStack(spacing: 0) {
            HStack(spacing: metrics.space(.m)) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(theme[.textTertiary])
                TextField(text: $query) { Text("findJump.placeholder") }
                    .textFieldStyle(.plain)
                    .font(metrics.font(.title3))
                    .focused($fieldFocused)
                    .onChange(of: query) { _, _ in cursor = 0 }
                    .onKeyPress(.downArrow) { move(1, count: results.count) }
                    .onKeyPress(.upArrow) { move(-1, count: results.count) }
                    .onSubmit { if results.indices.contains(cursor) { jump(results[cursor]) } }
                    .accessibilityIdentifier("findJump.field")
            }
            .padding(metrics.space(.l))
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: metrics.space(.xxs)) {
                        if results.isEmpty {
                            Text("findJump.nothing")
                                .font(metrics.font(.body))
                                .foregroundStyle(theme[.textTertiary])
                                .padding(metrics.space(.xxl))
                        }
                        ForEach(Array(results.enumerated()), id: \.element) { index, item in
                            row(item, selected: index == cursor)
                                .id(index)
                                .onTapGesture { jump(item) }
                                .onHover { if $0 { cursor = index } }
                        }
                    }
                    .padding(metrics.space(.s))
                }
                .onChange(of: cursor) { _, index in proxy.scrollTo(index) }
            }
            .frame(height: metrics.size(340))
        }
        .frame(width: metrics.size(560))
        .background(theme[.surfaceModal])
        .onAppear { fieldFocused = true }
        .onExitCommand { dismiss() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("findJump")
    }

    private func move(_ delta: Int, count: Int) -> KeyPress.Result {
        guard count > 0 else { return .handled }
        cursor = min(max(cursor + delta, 0), count - 1)
        return .handled
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        let info = describe(item)
        return HStack(spacing: metrics.space(.m)) {
            Image(systemName: info.symbol)
                .foregroundStyle(info.tint.map { theme[$0] } ?? theme[.textSecondary])
                .frame(width: metrics.size(18))
            Text(verbatim: info.title)
                .font(metrics.font(.body).weight(.medium))
                .foregroundStyle(theme[.textPrimary])
                .lineLimit(1)
            if let subtitle = info.subtitle {
                Text(verbatim: "· \(subtitle)")
                    .font(metrics.font(.footnote))
                    .foregroundStyle(theme[.textSecondary])
                    .lineLimit(1)
            }
            Spacer(minLength: metrics.space(.m))
            if let detail = info.detail {
                Text(verbatim: detail)
                    .font(metrics.font(.caption).monospaced())
                    .foregroundStyle(theme[.textTertiary])
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        }
        .padding(.horizontal, metrics.space(.m))
        .padding(.vertical, metrics.space(.s))
        .background(selected ? theme[.accentFaint] : Color.clear, in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: [info.title, info.subtitle].compactMap { $0 }.joined(separator: ", ")))
        .accessibilityAddTraits(selected ? [.isSelected, .isButton] : .isButton)
        .accessibilityIdentifier("findJump.row.\(info.title)")
    }

    private struct Info {
        var symbol: String
        var tint: ThemeToken?
        var title: String
        var subtitle: String?
        var detail: String?
    }

    private func describe(_ item: Item) -> Info {
        if case .terminal(let id) = item {
            guard let (project, pane) = document.paneHolding(id), let tab = pane.tabs.first(where: { $0.id == id }) else {
                return Info(symbol: "terminal", title: id.rawValue)
            }
            return Info(symbol: tab.agent == "shell" ? "terminal" : "sparkles", tint: AgentTokens.accent(for: tab.agent),
                        title: tab.title ?? AgentLabels.name(for: tab.agent), subtitle: project.name,
                        detail: tab.workingDirectory ?? project.folder)
        } else if case .project(let id) = item {
            let project = document.project(id)
            return Info(symbol: "folder", tint: project?.color.token, title: project?.name ?? id.rawValue,
                        subtitle: String(localized: "findJump.project"), detail: project?.folder)
        } else if case .plugin(let id) = item {
            return describePlugin(id)
        } else if case .command(let command) = item {
            return Info(symbol: command.symbol, title: String(localized: command.title),
                        subtitle: String(localized: "findJump.command"), detail: command.shortcut)
        }
        preconditionFailure("Unreachable item")
    }

    private func describePlugin(_ id: String) -> Info {
        guard let command = pluginCommands.first(where: { $0.id == id }) else { return Info(symbol: "command", title: id) }
        return Info(symbol: "command", title: command.title, subtitle: String(localized: "findJump.command"),
                    detail: command.keyEquivalent.map { "⌘" + $0.uppercased() })
    }

    private func fields(_ item: Item) -> [String] {
        let info = describe(item)
        return [info.title, info.subtitle, info.detail].compactMap { $0 }
    }

    private func jump(_ item: Item) {
        dismiss()
        if case .terminal(let id) = item {
            workspace.update { doc in
                guard let project = doc.paneHolding(id)?.project else { return }
                doc.openInTab(project.id)
                doc.activateTab(id)
            }
        } else if case .project(let id) = item {
            workspace.update { $0.openInTab(id) }
        } else if case .plugin(let id) = item {
            guard let command = pluginCommands.first(where: { $0.id == id }) else { return }
            DispatchQueue.main.async { command.perform() }
        } else if case .command(let command) = item {
            DispatchQueue.main.async { command.run(environment: environment, undoManager: undoManager) }
        }
    }
}

enum JumpCommand: String, CaseIterable, Hashable {
    case newTerminal, newProject, newGroup, addContent, reopenTab, flatWorkspace, focusPane
    case layoutAuto, layoutSpotlight, layoutSidebar, layoutGrid, designGrid, importTauri, settings, conversations

    var title: String.LocalizationValue {
        if case .newTerminal = self { return "menu.file.newTerminal" }
        if case .newProject = self { return "menu.file.newProject" }
        if case .newGroup = self { return "menu.file.newGroup" }
        if case .addContent = self { return "menu.file.addContent" }
        if case .reopenTab = self { return "menu.history.reopenTab" }
        if case .flatWorkspace = self { return "menu.view.flat" }
        if case .focusPane = self { return "focusMode.enter" }
        if case .layoutAuto = self { return "findJump.layout.auto" }
        if case .layoutSpotlight = self { return "findJump.layout.spotlight" }
        if case .layoutSidebar = self { return "findJump.layout.sidebar" }
        if case .layoutGrid = self { return "findJump.layout.grid" }
        if case .designGrid = self { return "workspace.layout.design" }
        if case .importTauri = self { return "menu.file.importTauri" }
        if case .settings = self { return "findJump.settings" }
        return "menu.history.conversations"
    }

    var symbol: String {
        if case .newTerminal = self { return "plus.rectangle" }
        if case .newProject = self { return "folder.badge.plus" }
        if case .newGroup = self { return "folder" }
        if case .addContent = self { return "doc.badge.plus" }
        if case .reopenTab = self { return "arrow.uturn.backward" }
        if case .flatWorkspace = self { return "rectangle.grid.1x2" }
        if case .focusPane = self { return "scope" }
        if case .layoutAuto = self { return PaneLayoutMode.auto.symbol }
        if case .layoutSpotlight = self { return PaneLayoutMode.spotlight.symbol }
        if case .layoutSidebar = self { return PaneLayoutMode.sidebar.symbol }
        if case .layoutGrid = self { return PaneLayoutMode.grid.symbol }
        if case .designGrid = self { return PaneLayoutMode.grid.symbol }
        if case .importTauri = self { return "square.and.arrow.down" }
        if case .settings = self { return "gearshape" }
        return "clock.arrow.circlepath"
    }

    var shortcut: String? {
        if case .newTerminal = self { return "⌘T" }
        if case .newProject = self { return "⌘N" }
        if case .newGroup = self { return "⇧⌘N" }
        if case .addContent = self { return "⇧⌘A" }
        if case .reopenTab = self { return "⇧⌘T" }
        if case .focusPane = self { return "⇧⌘F" }
        if case .settings = self { return "⌘," }
        if case .conversations = self { return "⌘Y" }
        return nil
    }

    @MainActor func isAvailable(_ document: WorkspaceDocument) -> Bool {
        if case .newTerminal = self { return !document.projects.isEmpty }
        if case .addContent = self { return !document.projects.isEmpty }
        if case .reopenTab = self { return !document.workspace.closedTabs.isEmpty }
        if case .focusPane = self { return document.workspace.focusedPaneID != nil }
        if case .layoutAuto = self { return document.workspace.selectedProjectID.flatMap(document.project) != nil }
        if case .layoutSpotlight = self { return document.workspace.selectedProjectID.flatMap(document.project) != nil }
        if case .layoutSidebar = self { return document.workspace.selectedProjectID.flatMap(document.project) != nil }
        if case .layoutGrid = self { return document.workspace.selectedProjectID.flatMap(document.project) != nil }
        if case .designGrid = self { return document.workspace.selectedProjectID.flatMap(document.project) != nil }
        return true
    }

    private static let layoutModes: [Self: PaneLayoutMode] = [
        .layoutAuto: .auto, .layoutSpotlight: .spotlight, .layoutSidebar: .sidebar, .layoutGrid: .grid
    ]

    @MainActor func run(environment: AppEnvironment, undoManager: UndoManager?) {
        let workspace = environment.workspace
        let selected = workspace?.document.workspace.selectedProjectID
        if case .newTerminal = self {
            environment.editorRequest = .newTerminal(nil)
        } else if case .newProject = self {
            environment.editorRequest = .newProject(.ungrouped)
        } else if case .newGroup = self {
            environment.editorRequest = .newGroup(parent: nil)
        } else if case .addContent = self {
            environment.editorRequest = .addContent(nil)
        } else if case .reopenTab = self {
            workspace?.update { $0.reopenClosedWorkspaceTab() }
        } else if case .flatWorkspace = self {
            workspace?.update { $0.workspace.flat.toggle() }
        } else if case .focusPane = self {
            environment.focusModePaneID = workspace?.document.workspace.focusedPaneID
        } else if let mode = Self.layoutModes[self] {
            if let selected { workspace?.update { $0.setLayoutMode(mode, for: selected) } }
        } else if case .designGrid = self {
            if let selected { environment.editorRequest = .layoutDesigner(.project(selected)) }
        } else if case .importTauri = self {
            environment.editorRequest = .importTauri
        } else if case .settings = self {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        } else {
            environment.editorRequest = .conversations(nil)
        }
    }
}
