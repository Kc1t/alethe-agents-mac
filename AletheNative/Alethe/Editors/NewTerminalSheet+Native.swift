import AletheAgents
import AletheDesign
import AletheGit
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

extension NewTerminalSheet {
    var nativeBody: some View {
        Form {
            if canOrchestrate {
                Picker(selection: $mode) {
                    Text("newTerminal.mode.terminal").tag(SessionMode.terminal)
                    Text("newTerminal.mode.orchestration").tag(SessionMode.orchestration)
                } label: {
                    Text("newTerminal.mode")
                    Text(orchestrating ? LocalizedStringKey("newTerminal.mode.orchestration.detail") : "newTerminal.mode.terminal.detail")
                }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("newTerminal.mode")
                .onChange(of: mode) { _, _ in
                    if !modeAgents.contains(agent) { agent = modeAgents.first ?? agent }
                }
            }

            Picker(selection: $agent) {
                ForEach(modeAgents, id: \.self) { kind in
                    Label {
                        Text(verbatim: AgentLabels.name(for: kind.rawValue))
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(theme[AgentTokens.accent(for: kind.rawValue)])
                    }
                    .tag(kind)
                }
            } label: { Text(orchestrating ? LocalizedStringKey("newTerminal.planner") : "newTerminal.agent") }
                .pickerStyle(.radioGroup)
                .accessibilityIdentifier("newTerminal.agent")

            if targetPane == nil {
                Picker(selection: $projectID) {
                    ForEach(workspace.document.projects) { project in
                        Text(verbatim: project.name).tag(ProjectID?.some(project.id))
                    }
                } label: { Text("newTerminal.project") }
                    .onChange(of: projectID) { _, _ in
                        folder = project?.folder ?? ""
                        gridID = project?.shownGridID
                        loadWorktreeDefaults()
                    }
                if let project, !project.namedGrids.isEmpty {
                    Picker(selection: $gridID) {
                        Text("projectGrid.main").tag(ProjectGridID?.none)
                        ForEach(project.namedGrids) { grid in
                            Text(verbatim: grid.name).tag(Optional(grid.id))
                        }
                    } label: { Text("newTerminal.grid") }
                        .accessibilityIdentifier("newTerminal.grid")
                }
            }

            LabeledContent("newTerminal.folder") {
                HStack {
                    TextField(text: $folder) { Text("newTerminal.folder") }
                        .labelsHidden()
                        .accessibilityIdentifier("newTerminal.folder")
                    Button("editor.project.chooseFolder") { chooseFolder() }
                }
            }

            if ModelDiscovery.modelFlag(for: agent) != nil {
                LabeledContent("newTerminal.model") {
                    HStack {
                        TextField(text: $model) { Text("newTerminal.model.default") }
                            .labelsHidden()
                            .accessibilityIdentifier("newTerminal.model")
                        if !models.isEmpty {
                            Menu {
                                Button("newTerminal.model.defaultItem") { model = "" }
                                Divider()
                                ForEach(models, id: \.self) { id in
                                    Button { model = id } label: { Text(verbatim: id) }
                                }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .accessibilityLabel(Text("newTerminal.model.choices"))
                            .accessibilityIdentifier("newTerminal.model.choices")
                        }
                    }
                }
                .task(id: agent) { await discoverModels() }
            }

            if let flag = descriptor?.unrestrictedFlag {
                Toggle(isOn: $unrestricted) {
                    Text("newTerminal.unrestricted")
                    Text(verbatim: flag).font(metrics.font(.footnote).monospaced())
                }
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
                    Picker(selection: $worktreeMode) {
                        Text("newTerminal.worktree.mode.gitWorktree").tag(WorktreeMode.gitWorktree)
                        Text("newTerminal.worktree.mode.localCopy").tag(WorktreeMode.localCopy)
                    } label: { Text("newTerminal.worktree.mode") }
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

            if descriptor?.isShell == false {
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

            if let problem {
                Text(problem)
                    .foregroundStyle(.secondary)
                    .font(metrics.font(.footnote))
                    .accessibilityIdentifier("editor.problem")
            }
        }
        .formStyle(.grouped)
        .frame(width: metrics.size(480))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("editor.cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(targetPane != nil ? LocalizedStringKey("newSubTab.add")
                       : orchestrating ? "newTerminal.createOrchestration" : "newTerminal.create") { create() }
                    .disabled(problem != nil || provisioning)
                    .accessibilityIdentifier("editor.confirm")
            }
        }
        .navigationTitle(Text(targetPane == nil ? LocalizedStringKey("newTerminal.title") : "newSubTab.title"))
        .onAppear(perform: loadInitial)
        .task { if router9.preferences.enabled { await router9.watch() } }
        .onChange(of: agent) { _, _ in
            unrestricted = startsUnrestricted
            model = ""
        }
    }

    func close() {
        if let closeOverlay { closeOverlay() } else { dismiss() }
    }
}
