import AletheAgents
import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct QuickLaunch: View {
    let workspace: WorkspaceModel
    var compactToolbar = false
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @Environment(\.undoManager) private var undoManager
    @State private var prompt = ""
    @State private var agent: AgentKind = .claude
    @State private var workingDirectory: String?
    @State private var unrestricted = false
    @FocusState private var focused: Bool

    private var agents: [AgentKind] {
        let enabled = AgentRegistry.builtin.enabledKinds(environment.preferences?.document.enabledAgents)
        if metrics.isWebInterface {
            return [AgentKind.claude, .codex, .copilot, .cursor, .antigravity, .opencode]
                .filter { enabled.contains($0) }
        }
        return enabled.filter { $0 != .shell }
    }
    private var project: Project? {
        workspace.document.recentProjectIDs(limit: 1).first.flatMap(workspace.document.project)
    }
    private var descriptor: AgentDescriptor? { AgentRegistry.builtin.descriptor(for: agent) }

    private func webAgentName(_ kind: AgentKind) -> String {
        kind == .claude ? "Claude" : AgentLabels.name(for: kind.rawValue)
    }

    private func compactWebPath(_ path: String) -> String {
        let parts = path.split(whereSeparator: { $0 == "/" || $0 == "\\" })
        guard parts.count > 4 else { return path }
        let separator = path.contains("\\") ? "\\" : "/"
        return (path.hasPrefix("~") ? "~" + separator : "") + "…" + separator
            + parts.suffix(3).joined(separator: separator)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.size(4)) {
            HStack(spacing: metrics.size(6)) {
                AletheStatusDot(.statusOffline, side: 7)
                AletheStatusDot(.statusWaiting, side: 7)
                AletheStatusDot(.statusWorking, side: 7)
                Text("home.quick.title")
                    .font(metrics.monoFont(size: 9))
                    .foregroundStyle(theme[metrics.isWebInterface ? .fg : .textTertiary])
                    .padding(.leading, metrics.size(metrics.isWebInterface ? 4 : 0))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.size(11))
            .frame(height: metrics.size(27))
            .background(theme[.bgSunken].opacity(metrics.isWebInterface ? 0.78 : 1))
            .modifier(HomeWebTerminalBarClip())
            .padding(.horizontal, -metrics.size(7))
            .padding(.top, -metrics.size(7))
            .overlay(alignment: .bottom) { theme[.border].frame(height: metrics.size(1)) }
            HStack(spacing: metrics.size(8)) {
                Text(verbatim: "›").font(metrics.monoFont(size: 17)).foregroundStyle(theme[.accent])
                Group {
                    if metrics.isWebInterface {
                        TextField(text: $prompt) {
                            Text("home.quick.placeholder").foregroundStyle(theme[.fg])
                        }
                        .lineLimit(1)
                        .foregroundStyle(theme[.fg])
                    } else {
                        TextField("home.quick.placeholder", text: $prompt, axis: .vertical)
                            .lineLimit(1...(focused ? 6 : 1))
                    }
                }
                .textFieldStyle(.plain)
                .font(metrics.monoFont(size: 12))
                .focused($focused)
                .onSubmit(send)
                .accessibilityIdentifier("home.quick.prompt")
            }
            .padding(.horizontal, metrics.size(9))
            .frame(minHeight: metrics.size(42))
            .overlay(alignment: .bottom) { theme[.border].frame(height: metrics.size(1)) }
            if metrics.isWebInterface {
                toolbar(horizontal: !compactToolbar)
            } else {
                toolbar(horizontal: true)
            }
        }
        .padding(metrics.size(7))
        .frame(maxWidth: metrics.size(620))
        .background(theme[.bg].opacity(metrics.isWebInterface ? 0.76 : 1), in: RoundedRectangle(cornerRadius: metrics.radius(.lg)))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.lg)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
        .shadow(color: metrics.isWebInterface
                ? (metrics.style == .clean ? .clear : theme[.bg].opacity(0.48)) : theme.shadow(.lg).color.color,
                radius: metrics.size(metrics.isWebInterface ? 36 : theme.shadow(.lg).blur),
                x: metrics.isWebInterface ? 0 : metrics.size(theme.shadow(.lg).x),
                y: metrics.size(metrics.isWebInterface ? 14 : theme.shadow(.lg).y))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.lg)).strokeBorder(focused && !metrics.isWebInterface ?
            theme[.accentBorder] : .clear))
        .onAppear {
            if metrics.isWebInterface {
                agent = agents.contains(.claude) ? .claude : agents.first ?? .claude
                unrestricted = false
            } else {
                let last = AgentRegistry.builtin.parse(environment.preferences?.document.lastAgent)
                agent = last.flatMap { agents.contains($0) ? $0 : nil } ?? agents.first ?? .claude
                unrestricted = environment.preferences?.document.alwaysStartUnrestricted == true
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.quick")
    }

    @ViewBuilder private func toolbar(horizontal: Bool) -> some View {
        if horizontal {
            HStack(spacing: metrics.size(5)) {
                agentControl
                projectControl
                modeControl
                sendControl
            }
            .labelsHidden()
            .controlSize(.small)
        } else {
            VStack(spacing: metrics.size(5)) {
                HStack(spacing: metrics.size(5)) {
                    agentControl
                    projectControl
                }
                HStack(spacing: metrics.size(5)) {
                    modeControl
                        .frame(maxWidth: .infinity, alignment: .leading)
                    sendControl
                }
            }
            .labelsHidden()
            .controlSize(.small)
        }
    }

    @ViewBuilder private var agentControl: some View {
        Group {
            if metrics.isWebInterface {
                WebDropdown(selection: $agent, options: agents, menuStyle: .homeAgent, trigger: { value, state in
                    AnyView(HStack(spacing: metrics.size(6)) {
                        AgentLogo(agent: value.rawValue, size: 15,
                                  templateColor: theme[AgentTokens.accent(for: value.rawValue)])
                            .frame(width: metrics.size(15), height: metrics.size(15)).clipped()
                        Text("home.web.agent").foregroundStyle(theme[.fgMuted]).fixedSize()
                        Text(verbatim: webAgentName(value)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").webProfileSized(10).font(metrics.font(size: 10))
                    }.modifier(HomeChoiceTrigger(open: state.open, agent: true)))
                }) { kind in
                    HStack(spacing: metrics.size(9)) {
                        AgentLogo(agent: kind.rawValue, size: 19)
                            .frame(width: metrics.size(19), height: metrics.size(19))
                        Text(verbatim: webAgentName(kind)).frame(maxWidth: .infinity, alignment: .leading)
                        if agent == kind {
                            Image(systemName: "checkmark").font(metrics.font(size: 12)).foregroundStyle(theme[.accent])
                        }
                    }
                }
            } else {
                AletheSelect(selection: $agent, options: agents) {
                    Text(verbatim: AgentLabels.name(for: $0.rawValue))
                }
            }
        }
        .frame(width: metrics.size(145))
        .modifier(HomeWebHelp(text: String(localized: "home.quick.agent")))
        .accessibilityLabel(Text("home.quick.agent"))
        .accessibilityIdentifier("home.quick.agent")
    }

    @ViewBuilder private var projectControl: some View {
        Button(action: chooseFolder) {
            if metrics.isWebInterface {
            HStack(spacing: metrics.size(5)) {
                Image(systemName: "folder").webProfileSized(13).font(metrics.font(size: 13))
                if metrics.isWebInterface { Text("home.web.path").foregroundStyle(theme[.fgMuted]).fixedSize() }
                if let folder = workingDirectory ?? project?.folder {
                    Text(verbatim: compactWebPath(folder))
                        .lineLimit(1).truncationMode(.tail)
                } else { Text("home.quick.project") }
                if metrics.isWebInterface {
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down").webProfileSized(10).font(metrics.font(size: 10))
                }
            }
            } else {
                Label {
                    if let folder = workingDirectory ?? project?.folder {
                        Text(verbatim: (folder as NSString).abbreviatingWithTildeInPath)
                            .lineLimit(1).truncationMode(.middle)
                    } else { Text("home.quick.project") }
                } icon: { Image(systemName: "folder").webProfileSized(14) }
            }
        }
        .modifier(QuickProjectStyle())
        .modifier(HomeWebHelp(text: workingDirectory ?? project?.folder ?? String(localized: "home.quick.project")))
        .accessibilityLabel(Text("home.quick.project"))
        .accessibilityIdentifier("home.quick.project")
    }

    @ViewBuilder private var modeControl: some View {
        if metrics.isWebInterface || descriptor?.unrestrictedFlag != nil {
            Group {
                if metrics.isWebInterface {
                    WebDropdown(selection: $unrestricted, options: [false, true], menuStyle: .homeMode, trigger: { value, state in
                        AnyView(HStack(spacing: metrics.size(5)) {
                            AletheStatusDot(.accent, side: 5)
                            Text("home.web.mode").foregroundStyle(theme[.fgMuted]).fixedSize()
                            Text(value ? "home.quick.unrestricted" : "home.quick.normal").lineLimit(1)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.down").webProfileSized(10).font(metrics.font(size: 10))
                        }.modifier(HomeChoiceTrigger(open: state.open)))
                    }) { value in
                        HStack(spacing: metrics.size(8)) {
                            AletheStatusDot(.accent, side: 5)
                            Text(value ? "home.quick.unrestricted" : "home.quick.normal")
                        }
                    }.frame(width: compactToolbar ? nil : metrics.size(132))
                } else {
                    Picker("home.quick.mode", selection: $unrestricted) {
                        Text("home.quick.normal").tag(false)
                        Text("home.quick.unrestricted").tag(true)
                    }
                }
            }
            .fixedSize(horizontal: !metrics.isWebInterface || !compactToolbar, vertical: true)
            .accessibilityLabel(Text("home.quick.mode"))
            .accessibilityIdentifier("home.quick.mode")
        }
    }

    @ViewBuilder private var sendControl: some View {
        if metrics.isWebInterface {
            Button(action: send) {
                Image(systemName: "paperplane").webProfileSized(14)
            }
            .buttonStyle(HomeQuickSendStyle())
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(project == nil || agents.isEmpty)
            .help(Text("home.quick.send"))
            .accessibilityLabel(Text("home.quick.send"))
            .accessibilityIdentifier("home.quick.send")
        } else {
        Button(action: send) { Label { Text("home.quick.send") } icon: { Image(systemName: "paperplane").webProfileSized(14) }
            .labelStyle(.iconOnly)
            .frame(width: metrics.size(38), height: metrics.size(30))
            .background(theme[.accent], in: RoundedRectangle(cornerRadius: metrics.radius(metrics.isWebInterface ? .md : .sm)))
            .foregroundStyle(theme[.accentOn])
        }
            .buttonStyle(.plain)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(project == nil || agents.isEmpty || (!metrics.isWebInterface &&
                prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty))
            .opacity(project == nil || agents.isEmpty || (!metrics.isWebInterface &&
                prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) ? (metrics.isWebInterface ? 0.45 : 0.5) : 1)
            .accessibilityLabel(Text("home.quick.send"))
            .accessibilityIdentifier("home.quick.send")
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = (workingDirectory ?? project?.folder).map { URL(fileURLWithPath: $0) }
        panel.begin { response in
            if response == .OK, let url = panel.url { workingDirectory = url.path }
        }
    }

    private func send() {
        let text = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let project, !text.isEmpty, agents.contains(agent) else { return }
        let tab = PaneTab(agent: agent.rawValue, workingDirectory: workingDirectory ?? project.folder,
                          unrestricted: descriptor?.unrestrictedFlag != nil && unrestricted, initialPrompt: text)
        workspace.update(undoManager: undoManager, actionName: String(localized: "undo.newTerminal")) {
            $0.openInTab(project.id)
            $0.addPane(to: project.id, tab: tab)
        }
        environment.preferences?.update { $0.lastAgent = agent.rawValue }
        prompt = ""
        environment.showingHome = false
    }
}
