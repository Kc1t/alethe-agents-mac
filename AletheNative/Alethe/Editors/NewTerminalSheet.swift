import AletheAgents
import AletheDesign
import AletheGit
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct NewTerminalSheet: View {
    let workspace: WorkspaceModel
    let undoManager: UndoManager?
    let initialProject: ProjectID?
    var targetPane: PaneID?
    var closeOverlay: (() -> Void)?
    @Environment(AppEnvironment.self) var environment
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics

    enum SessionMode: Hashable { case terminal, orchestration }

    static let plannerAgents: [AgentKind] = [.claude, .codex]

    @State var mode: SessionMode = .terminal
    @State var agent: AgentKind = .claude
    @State var projectID: ProjectID?
    @State var folder = ""
    @State var unrestricted = false
    @State var prompt = ""
    @State var gridID: ProjectGridID?
    @State var model = ""
    @State var models: [String] = []
    @State var modelsLoading = false
    @State var ownWorktree = false
    @State var worktreeMode: WorktreeMode = .gitWorktree
    @State var provisioning = false
    @State var worktreeError: String?
    @State var useRouter9 = false

    var registry: AgentRegistry { environment.agentRegistry }
    var agents: [AgentKind] { registry.enabledKinds(environment.preferences?.document.enabledAgents) }
    var project: Project? { projectID.flatMap { workspace.document.project($0) } }
    var descriptor: AgentDescriptor? { registry.descriptor(for: agent) }
    private var plannerAgents: [AgentKind] { agents.filter(Self.plannerAgents.contains) }
    var canOrchestrate: Bool { targetPane == nil && !plannerAgents.isEmpty }
    var orchestrating: Bool { canOrchestrate && mode == .orchestration }
    var modeAgents: [AgentKind] { orchestrating ? plannerAgents : agents }
    var router9: Router9Controller { environment.router9 }
    var routingAvailable: Bool {
        Router9.routingAvailable(router9.preferences, hasAPIKey: router9.hasAPIKey, hasInstall: router9.hasInstall,
                                 agent: agent)
    }

    @Environment(\.newTerminalModalHeight) private var modalHeight
    @Environment(\.webModalHasExplicitHeight) private var explicitModalHeight
    @State private var webContentHeight: CGFloat = 440
    @State private var advanced = false
    @State var createMore = false
    @FocusState private var pathFocused: Bool

    var body: some View {
        Group {
            if metrics.isWebInterface { webBody } else { nativeBody }
        }
    }

    private var webBody: some View {
        VStack(spacing: 0) {
            HStack {
                Text(targetPane == nil ? LocalizedStringKey("newTerminal.web.title") : "newSubTab.title")
                    .font(metrics.font(size: 17, weight: .semibold))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(metrics.font(size: 14))
                        .frame(width: metrics.size(26), height: metrics.size(26))
                }
                .buttonStyle(AletheWorkspaceActionStyle())
                .accessibilityLabel(Text("editor.cancel"))
            }
            .padding(.horizontal, metrics.size(22))
            .padding(.top, metrics.size(20))
            .padding(.bottom, metrics.size(2))
            .webModalHeader()
            .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: metrics.size(14)) {
                    if canOrchestrate {
                        webField("newTerminal.mode") {
                            NewTerminalRowSelect(selection: $mode, options: [.terminal, .orchestration],
                                title: {
                                    String(localized: $0 == .terminal
                                        ? "newTerminal.mode.terminal"
                                        : "newTerminal.mode.orchestration")
                                },
                                detail: {
                                    String(localized: $0 == .terminal
                                        ? "newTerminal.mode.terminal.detail"
                                        : "newTerminal.web.orchestrationDetail")
                                },
                                side: {
                                    String(localized: $0 == .terminal
                                        ? "newTerminal.web.terminalSide"
                                        : "newTerminal.web.orchestrationSide")
                                },
                                autofocus: true) { value in
                                Image(systemName: value == .terminal ? "terminal" : "point.3.connected.trianglepath.dotted")
                                    .font(metrics.font(size: 15))
                            }
                            .accessibilityIdentifier("newTerminal.mode")
                        }.zIndex(4)
                    }
                    webField(orchestrating ? "newTerminal.planner" : "newTerminal.agent") {
                        NewTerminalRowSelect(selection: $agent, options: modeAgents,
                            title: { AgentLabels.name(for: $0.rawValue) }, autofocus: !canOrchestrate) { kind in
                            if registry.descriptor(for: kind)?.isShell == true {
                                Image(systemName: "terminal").font(metrics.font(size: 17))
                            } else {
                                AgentLogo(agent: kind.rawValue, size: 17)
                                    .frame(width: metrics.size(17), height: metrics.size(17))
                                    .clipped()
                            }
                        }
                        .accessibilityIdentifier("newTerminal.agent")
                    }.zIndex(3)
                    VStack(alignment: .leading, spacing: metrics.size(7)) {
                        HStack {
                            Text("newTerminal.folder")
                            Spacer()
                            Button("editor.project.chooseFolder", action: chooseFolder)
                                .buttonStyle(.plain)
                                .font(metrics.font(size: 11))
                        }
                        .font(metrics.font(size: 12)).foregroundStyle(theme[.fgMuted])
                        NewTerminalRowSelect(selection: $folder, options: folderChoices,
                            title: { URL(filePath: $0).lastPathComponent }, detail: { $0 }, side: { path in
                                let parts = path.split(separator: "/")
                                return parts.count > 2 ? "…/" + parts.suffix(2).joined(separator: "/") : path
                            }) { _ in
                            Image(systemName: "folder").font(metrics.font(size: 15))
                        }
                        .accessibilityIdentifier("newTerminal.folder")
                    }.zIndex(2)
                    if orchestrating {
                        webField("newTerminal.goal") {
                            TextEditor(text: $prompt)
                                .font(metrics.font(size: 13))
                                .scrollContentBackground(.hidden)
                                .frame(height: metrics.size(64))
                                .padding(metrics.size(11))
                                .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.size(12)))
                                .accessibilityIdentifier("newTerminal.prompt")
                        }
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Button { advanced.toggle() } label: {
                            HStack(spacing: metrics.size(6)) {
                                Image(systemName: advanced ? "chevron.down" : "chevron.right")
                                    .font(metrics.font(size: 9))
                                Text("newTerminal.web.advanced").font(metrics.font(size: 12))
                                Text("newTerminal.web.advancedHint").font(metrics.font(size: 11))
                                    .foregroundStyle(theme[.fgFaint])
                            }
                        }.buttonStyle(.plain)
                        if advanced {
                            webAdvanced
                                .padding(metrics.size(12))
                                .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.size(14)))
                                .padding(.top, metrics.size(12))
                        }
                    }
                    .foregroundStyle(theme[.fgMuted])
                    .padding(.top, metrics.size(2))
                    if let problem {
                        Text(problem).font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted])
                            .accessibilityIdentifier("editor.problem")
                    }
                }
                .padding(.horizontal, metrics.size(20))
                .padding(.top, metrics.size(14))
                .padding(.bottom, metrics.size(18))
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { webContentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: explicitModalHeight ? nil : min(webContentHeight, max(0, modalHeight - metrics.size(125))))
            .frame(maxHeight: explicitModalHeight ? .infinity : nil)
            Rectangle().fill(theme[.border]).frame(height: metrics.size(1))
            HStack(spacing: metrics.size(10)) {
                if !orchestrating && targetPane == nil {
                    Button { createMore.toggle() } label: {
                        HStack(spacing: metrics.size(9)) {
                            Capsule().fill(theme[createMore ? .panelHover : .bgSunken])
                                .frame(width: metrics.size(32), height: metrics.size(18))
                                .overlay(Capsule().strokeBorder(theme[.borderStrong], lineWidth: metrics.size(1)))
                                .overlay(Circle().fill(theme[createMore ? .accent : .fgFaint])
                                    .frame(width: metrics.size(12), height: metrics.size(12))
                                    .offset(x: metrics.size(createMore ? 7 : -7)))
                            Text("newTerminal.web.createMore")
                        }
                    }
                    .buttonStyle(.plain)
                    .font(metrics.font(size: 12)).foregroundStyle(theme[.fgMuted])
                    .accessibilityValue(Text(createMore ? "newTerminal.web.on" : "newTerminal.web.off"))
                    .animation(metrics.reducesMotion ? nil : .easeOut(duration: 0.12), value: createMore)
                }
                Spacer(minLength: 0)
                Button("editor.cancel", action: close).buttonStyle(AletheButtonStyle())
                Button(action: create) {
                    HStack(spacing: metrics.size(9)) {
                        if targetPane != nil {
                            Text("newSubTab.add")
                        } else if orchestrating {
                            Text("newTerminal.createOrchestration")
                        } else {
                            Text(verbatim: String(format: String(localized: "newTerminal.web.openAgent"),
                                                  AgentLabels.name(for: agent.rawValue)))
                        }
                        Text(verbatim: "⌘↵")
                            .font(metrics.monoFont(size: 10, weight: .regular))
                            .padding(.horizontal, metrics.size(5)).padding(.vertical, metrics.size(1))
                            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm))
                                .strokeBorder(theme[.accentOn].opacity(0.5), lineWidth: metrics.size(1)))
                    }
                }
                .buttonStyle(AletheButtonStyle(.primary))
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(problem != nil || provisioning)
                .accessibilityIdentifier("editor.confirm")
            }
            .padding(.horizontal, metrics.size(22))
            .padding(.top, metrics.size(14)).padding(.bottom, metrics.size(18))
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(theme[.fg])
        .background(theme[.bgElevated], in: RoundedRectangle(cornerRadius: metrics.size(20)))
        .overlay(RoundedRectangle(cornerRadius: metrics.size(20))
            .strokeBorder(theme[.borderStrong], lineWidth: metrics.size(1)))
        .newTerminalDropdownLayer()
        .onAppear(perform: loadInitial)
        .task { if router9.preferences.enabled { await router9.watch() } }
        .onChange(of: agent) { _, _ in unrestricted = startsUnrestricted; model = "" }
        .onChange(of: mode) { _, _ in
            if !modeAgents.contains(agent) { agent = modeAgents.first ?? agent }
        }
    }

    private func webField<Content: View>(_ key: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: metrics.size(7)) {
            Text(key).font(metrics.font(size: 12)).foregroundStyle(theme[.fgMuted])
            content()
        }
    }

    private var webAdvanced: some View {
        VStack(alignment: .leading, spacing: metrics.size(10)) {
            if targetPane == nil {
                WebDropdown(selection: $projectID, options: workspace.document.projects.map { Optional($0.id) }) { id in
                    Text(verbatim: workspace.document.projects.first { Optional($0.id) == id }?.name ?? "")
                }.accessibilityLabel(Text("newTerminal.project"))
                .onChange(of: projectID) { _, _ in
                    folder = project?.folder ?? ""
                    gridID = project?.shownGridID
                    loadWorktreeDefaults()
                }
                if let project, !project.namedGrids.isEmpty {
                    NewTerminalRowSelect(selection: $gridID,
                        options: [ProjectGridID?.none] + project.namedGrids.map { Optional($0.id) },
                        title: { id in id.flatMap { key in project.namedGrids.first { $0.id == key }?.name } ??
                            String(localized: "projectGrid.main") }) { id in
                        Image(systemName: id == nil ? "terminal" : "square.grid.2x2").font(metrics.font(size: 15))
                    }.accessibilityLabel(Text("newTerminal.grid")).accessibilityIdentifier("newTerminal.grid")
                }
            }
            if ModelDiscovery.modelFlag(for: agent) != nil {
                LabeledContent("newTerminal.model") {
                    HStack {
                        WebModelDropdown(selection: $model, models: models, provider: AgentLabels.name(for: agent.rawValue),
                            loading: modelsLoading, includesDefault: true)
                            .accessibilityLabel(Text("newTerminal.model.choices"))
                            .accessibilityIdentifier("newTerminal.model.choices")
                    }.accessibilityElement(children: .contain)
                        .accessibilityIdentifier("newTerminal.model")
                }
                .task(id: agent) { await discoverModels() }
            }

            if descriptor?.unrestrictedFlag != nil {
                webPermission("newTerminal.unrestricted", detail: String(localized: "newTerminal.web.permissionDetail"),
                              symbol: "bolt", value: $unrestricted)
                .accessibilityIdentifier("newTerminal.unrestricted")
            }

            if routingAvailable { router9Rows }

            if descriptor?.isShell == false {
                Toggle(isOn: $ownWorktree) {
                    Text("newTerminal.worktree")
                    Text("newTerminal.worktree.detail").font(metrics.font(.footnote))
                }
                .accessibilityIdentifier("newTerminal.worktree")
                if ownWorktree {
                    WebDropdown(selection: $worktreeMode, options: [.gitWorktree, .localCopy]) {
                        Text($0 == .gitWorktree ? "newTerminal.worktree.mode.gitWorktree" : "newTerminal.worktree.mode.localCopy")
                    }.accessibilityLabel(Text("newTerminal.worktree.mode"))
                        .accessibilityIdentifier("newTerminal.worktreeMode")
                }
                if let worktreeError {
                    VStack(alignment: .leading, spacing: metrics.space(.xs)) {
                        Text("newTerminal.worktree.failed")
                        Text(verbatim: worktreeError).font(metrics.font(.footnote).monospaced())
                    }
                    .foregroundStyle(theme[.statusStopped])
                    .accessibilityIdentifier("newTerminal.worktreeError")
                }
            }

            if descriptor?.isShell == false && !orchestrating {
                LabeledContent(orchestrating ? LocalizedStringKey("newTerminal.goal") : "newTerminal.prompt") {
                    TextEditor(text: $prompt)
                        .font(metrics.font(.body))
                        .frame(minHeight: metrics.size(70))
                        .scrollContentBackground(.hidden)
                        .padding(metrics.space(.xs))
                        .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm)).strokeBorder(theme[.border]))
                        .accessibilityIdentifier("newTerminal.prompt")
                }
            }

            webField("newTerminal.web.folderPath") {
                TextField(text: $folder) { Text("newTerminal.folder") }
                    .textFieldStyle(.plain)
                    .font(metrics.monoFont(size: 11, weight: .regular))
                    .focused($pathFocused)
                    .padding(.horizontal, metrics.size(10))
                    .frame(height: metrics.size(32))
                    .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.size(8)))
                    .overlay(RoundedRectangle(cornerRadius: metrics.size(8))
                        .strokeBorder(theme[pathFocused ? .accent : .border], lineWidth: metrics.size(1)))
                    .accessibilityIdentifier("newTerminal.folder.path")
            }
        }
        .font(metrics.font(size: 12))
    }

    private var folderChoices: [String] {
        var seen = Set<String>()
        return ([folder] + workspace.document.projects.map(\.folder)).filter {
            !$0.isEmpty && seen.insert($0).inserted
        }
    }

    private func webPermission(_ title: LocalizedStringKey, detail: String, symbol: String,
                               value: Binding<Bool>) -> some View {
        Button { value.wrappedValue.toggle() } label: {
            HStack(spacing: metrics.size(11)) {
                Image(systemName: symbol).font(metrics.font(size: 16))
                    .frame(width: metrics.size(26), height: metrics.size(26))
                    .background(theme[.panel], in: RoundedRectangle(cornerRadius: metrics.size(8)))
                VStack(alignment: .leading, spacing: metrics.size(3)) {
                    Text(title).font(metrics.font(size: 12, weight: .semibold))
                    Text(verbatim: detail).font(metrics.font(size: 10)).foregroundStyle(theme[.fgMuted])
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(value.wrappedValue ? "newTerminal.web.on" : "newTerminal.web.off")
                    .textCase(.uppercase)
                    .font(metrics.font(size: 9, weight: .bold))
                    .padding(.horizontal, metrics.size(7)).padding(.vertical, metrics.size(3))
                    .background(theme[.panel], in: Capsule())
            }
            .padding(.horizontal, metrics.size(12)).padding(.vertical, metrics.size(9))
            .frame(minHeight: metrics.size(52))
            .background(theme[value.wrappedValue ? .statusWaitingSoft : .bgElevated],
                        in: RoundedRectangle(cornerRadius: metrics.size(12)))
            .overlay(RoundedRectangle(cornerRadius: metrics.size(12))
                .strokeBorder(theme[value.wrappedValue ? .statusWaiting : .border], lineWidth: metrics.size(1)))
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(value.wrappedValue ? "newTerminal.web.on" : "newTerminal.web.off"))
    }

    @ViewBuilder var router9Rows: some View {
        Toggle(isOn: $useRouter9) {
            Text("newTerminal.router9")
            Text("newTerminal.router9.detail").font(metrics.font(.footnote))
        }
        .accessibilityIdentifier("newTerminal.router9")
        if useRouter9, !router9.isRunning {
            Button(router9.busy ? LocalizedStringKey("newTerminal.router9.starting") : "newTerminal.router9.stopped") {
                Task { await router9.startRouter() }
            }
            .disabled(router9.busy)
            .accessibilityIdentifier("newTerminal.router9.start")
        }
        Toggle(isOn: Binding(get: { router9.preferences.defaultForNewAgents },
                             set: { value in router9.update { $0.defaultForNewAgents = value } })) {
            Text("router9.defaultForNewAgents")
        }
        .accessibilityIdentifier("newTerminal.router9.always")
    }


}
