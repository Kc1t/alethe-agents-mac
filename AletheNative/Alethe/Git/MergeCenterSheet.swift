import AletheAgents
import AletheDesign
import AletheFoundation
import AletheGit
import AletheMerge
import AletheModel
import SwiftUI

struct MergeCenterSheet: View {
    let workspace: WorkspaceModel
    let undoManager: UndoManager?
    let projectID: ProjectID?
    var resumeID: String?
    @Environment(AppEnvironment.self) var environment
    @State var agent: AgentKind = .claude
    @State var model: MergeCenterModel?
    @State var confirmAbort = false
    @State var confirmCleanup = false
    @State var testingBranch = false
    @Environment(\.dismiss) var dismiss
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics

    var project: Project? { projectID.flatMap { workspace.document.project($0) } }

    @Environment(\.gitModalClose) var closeOverlay

    var body: some View {
        Group {
            if metrics.isWebInterface {
                webContent
            } else {
                nativeContent
            }
        }
    }

    var nativeContent: some View {
        sheetContent
        .frame(width: metrics.size(560), height: metrics.size(600))
        .navigationTitle(Text("merge.title"))
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("merge.close") { dismiss() }
                    .accessibilityIdentifier("merge.close")
            }
        }
    }

    var sheetContent: some View {
        Group {
            if let model {
                content(model)
            } else {
                Text("merge.noProject")
                    .foregroundStyle(theme[.textSecondary])
                    .padding(metrics.space(.xl))
            }
        }
        .task { await loadModel() }
        .onDisappear { model?.cancel() }
        .accessibilityIdentifier("merge.center")
    }

    func loadModel() async {
        guard let project else { return }
        let model = MergeCenterModel(folder: URL(filePath: project.folder, directoryHint: .isDirectory),
                                     projectID: project.id, bus: environment.multiagent.bus)
        self.model = model
        let last = AgentRegistry.builtin.parse(environment.preferences?.document.lastAgent)
        agent = last.flatMap { agents.contains($0) ? $0 : nil } ?? (agents.contains(.claude) ? .claude : agents.first ?? .claude)
        await model.load(resume: resumeID)
        if metrics.isWebInterface {
            if let provider = project.conflictAgentProvider,
               let selected = environment.agentRegistry.parse(provider), agents.contains(selected) { agent = selected }
            if let commands = project.validationCommands { model.commandsText = commands.joined(separator: "\n") }
            model.healthCheckCommand = project.healthCheckCommand
            model.healthCheckPath = project.healthCheckPath
        }
    }

    @ViewBuilder
    func content(_ model: MergeCenterModel) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            stageHeader(model.stage)
                .padding(metrics.space(.l))
            Divider()
            if let error = model.error {
                Label { Text(verbatim: error).textSelection(.enabled) } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.callout)
                .foregroundStyle(theme[.statusStopped])
                .padding(metrics.space(.m))
                .accessibilityIdentifier("merge.error")
            }
            if model.loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if model.stage == .analyze {
                    analyze(model)
                } else if model.stage == .prepare {
                    prepare(model)
                } else if model.stage == .validate {
                    validate(model)
                } else {
                    finish(model)
                }
            }
        }
        .confirmationDialog("merge.abort.confirm", isPresented: $confirmAbort) {
            Button("merge.abort", role: .destructive) { model.abort() }
        }
        .confirmationDialog("merge.cleanup.confirm", isPresented: $confirmCleanup) {
            Button("merge.cleanup", role: .destructive) { model.forceCleanup() }
        }
        .gitWebSheet(isPresented: $testingBranch, width: 560) {
            BranchTestingSheet(folder: model.folder, initialBranch: model.source)
        }
    }

    @ViewBuilder
    func actionRow(_ model: MergeCenterModel, @ViewBuilder _ actions: () -> some View) -> some View {
        HStack {
            if model.running {
                ProgressView().controlSize(.small)
                Text("merge.working").foregroundStyle(theme[.textSecondary])
                Button("merge.cancel") { model.cancel() }
                    .accessibilityIdentifier("merge.cancel")
            } else {
                actions()
            }
            Spacer()
        }
    }

    func outputBox(_ text: String) -> some View {
        ScrollView {
            Text(verbatim: text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("merge.output")
    }

    func abortButton(_ model: MergeCenterModel) -> some View {
        Button("merge.abort", role: .destructive) { confirmAbort = true }
            .disabled(model.environment == nil)
            .accessibilityIdentifier("merge.abort")
    }

    func prepare(_ model: MergeCenterModel) -> some View {
        VStack(alignment: .leading, spacing: metrics.space(.m)) {
            actionRow(model) {
                Picker("merge.agent", selection: $agent) {
                    ForEach(agents, id: \.self) { kind in
                        Text(verbatim: AgentLabels.name(for: kind.rawValue)).tag(kind)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(agents.isEmpty)
                .help(Text("merge.agent"))
                .accessibilityIdentifier("merge.agent")
                Button("merge.resolveWithAgent") { resolveWithAgent(model) }
                    .disabled(model.environment == nil || !agents.contains(agent))
                    .accessibilityIdentifier("merge.resolveWithAgent")
                Button("merge.refresh") { model.refreshConflicts() }
                Button("merge.rebase") { model.rebase() }
                    .accessibilityIdentifier("merge.rebase")
                abortButton(model)
                Button("merge.continue") { model.stage = .validate }
                    .disabled(!model.conflicts.isEmpty)
                    .accessibilityIdentifier("merge.continue")
            }
            if let path = model.environment?.path.path {
                Text(verbatim: path)
                    .font(.caption.monospaced())
                    .foregroundStyle(theme[.textSecondary])
                    .textSelection(.enabled)
            }
            if let note = model.note { outputBox(note).frame(maxHeight: metrics.size(80)) }
            Divider()
            conflictList(model.conflicts)
        }
        .padding(metrics.space(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    var agents: [AgentKind] {
        let preferences = environment.preferences?.document
        return environment.agentRegistry.enabledKinds(preferences?.enabledAgents).filter { kind in
            guard let command = environment.agentRegistry.descriptor(for: kind)?.cliCommand else { return false }
            return environment.launchers.resolve(command, override: preferences?.cliPaths?[kind.rawValue]) != nil
        }
    }

    func resolveWithAgent(_ model: MergeCenterModel) {
        guard let project, let path = model.environment?.path.path, agents.contains(agent) else { return }
        let tab = PaneTab(agent: agent.rawValue, title: String(localized: "merge.agentPaneName"),
                          workingDirectory: path,
                          extraArguments: metrics.isWebInterface
                              ? ModelDiscovery.arguments([], model: project.conflictAgentModel ?? "", for: agent) : [],
                          initialPrompt: ConflictResolution.agentInstruction())
        workspace.update(undoManager: undoManager, actionName: String(localized: "undo.newTerminal")) {
            $0.addPane(to: project.id, tab: tab)
        }
        environment.preferences?.update { $0.lastAgent = agent.rawValue }
        if metrics.isWebInterface, let closeOverlay { closeOverlay() } else { dismiss() }
    }

    func validate(_ model: MergeCenterModel) -> some View {
        VStack(alignment: .leading, spacing: metrics.space(.m)) {
            Text("merge.validate.commands").font(.headline)
            TextEditor(text: Bindable(model).commandsText)
                .font(.body.monospaced())
                .frame(height: metrics.size(90))
                .accessibilityIdentifier("merge.validate.commands")
            actionRow(model) {
                Button("merge.validate.run") { model.validate() }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("merge.validate.run")
                abortButton(model)
                Button("merge.continue") { model.stage = .finish }
                    .accessibilityIdentifier("merge.continue")
            }
            outcomeDetails(model)
        }
        .padding(metrics.space(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func outcomeDetails(_ model: MergeCenterModel) -> some View {
        if model.note != nil || model.outcome != nil {
            ScrollView {
                VStack(alignment: .leading, spacing: metrics.space(.m)) {
                    if let note = model.note {
                        Text(verbatim: note)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("merge.output")
                    }
                    if let outcome = model.outcome {
                        ValidationStepsView(steps: outcome.validation?.steps ?? [])
                        if let probe = outcome.validation?.healthProbe { HealthProbeSummaryView(result: probe) }
                        if let warnings = outcome.contractWarnings { ContractWarningsView(warnings: warnings) }
                    }
                }
            }
        } else {
            Spacer()
        }
    }

    func finish(_ model: MergeCenterModel) -> some View {
        VStack(alignment: .leading, spacing: metrics.space(.m)) {
            actionRow(model) {
                Button("merge.finalize") { model.finalize() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.environment == nil)
                    .accessibilityIdentifier("merge.finalize")
                abortButton(model)
                Button("merge.cleanup", role: .destructive) { confirmCleanup = true }
                    .disabled(model.environment == nil)
                    .accessibilityIdentifier("merge.cleanup")
            }
            if model.merged {
                Label("merge.merged", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(theme[.statusActive])
            }
            outcomeDetails(model)
        }
        .padding(metrics.space(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    func stageHeader(_ current: MergeCenterStage) -> some View {
        HStack(spacing: metrics.space(.s)) {
            ForEach(Array(MergeCenterStage.allCases.enumerated()), id: \.element) { index, stage in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(theme[.textSecondary])
                }
                Text(stageTitle(stage))
                    .font(.callout.weight(stage == current ? .semibold : .regular))
                    .foregroundStyle(stage == current ? theme[.accent] : theme[.textSecondary])
            }
            Spacer()
        }
        .accessibilityIdentifier("merge.stages")
    }

    func stageTitle(_ stage: MergeCenterStage) -> LocalizedStringKey {
        Self.stageTitles[stage] ?? "merge.stage.finish"
    }

    private static let stageTitles: [MergeCenterStage: LocalizedStringKey] = [
        .analyze: "merge.stage.analyze", .prepare: "merge.stage.prepare",
        .validate: "merge.stage.validate", .finish: "merge.stage.finish",
    ]

    func analyze(_ model: MergeCenterModel) -> some View {
        VStack(alignment: .leading, spacing: metrics.space(.m)) {
            Picker("merge.source", selection: Bindable(model).source) {
                ForEach(model.branches, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            .accessibilityIdentifier("merge.source")
            Picker("merge.target", selection: Bindable(model).target) {
                ForEach(model.branches, id: \.self) { Text(verbatim: $0).tag($0) }
            }
            .accessibilityIdentifier("merge.target")
            HStack {
                if model.running {
                    ProgressView().controlSize(.small)
                    Text("merge.analyzing").foregroundStyle(theme[.textSecondary])
                    Button("merge.cancel") { model.cancel() }
                        .accessibilityIdentifier("merge.cancel")
                } else {
                    Button("merge.analyze") { model.analyze() }
                        .disabled(!model.canAnalyze)
                        .keyboardShortcut(.defaultAction)
                        .accessibilityIdentifier("merge.analyze")
                }
                Spacer()
            }
            HStack {
                if model.analysis != nil, !model.running {
                    Button("merge.prepare") { model.prepare() }
                        .accessibilityIdentifier("merge.prepare")
                }
                Button("menu.merge.branchTesting") { testingBranch = true }
                    .disabled(model.source.isEmpty || model.running)
                    .accessibilityIdentifier("merge.testBranch")
            }
            Divider()
            if let analysis = model.analysis {
                result(analysis)
            } else {
                Spacer()
            }
        }
        .padding(metrics.space(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    func result(_ analysis: MergeAnalysis) -> some View {
        if analysis.clean {
            Label("merge.clean", systemImage: "checkmark.circle.fill")
                .foregroundStyle(theme[.statusActive])
                .accessibilityIdentifier("merge.clean")
            Spacer()
        } else {
            HStack {
                Text("merge.conflicts").font(.headline)
                Text(verbatim: "\(analysis.conflicts.count)")
                    .font(.headline)
                    .foregroundStyle(theme[.statusStopped])
            }
            conflictList(analysis.conflicts)
        }
    }

    func conflictList(_ conflicts: [ConflictFile]) -> some View {
            List(conflicts, id: \.path) { conflict in
                VStack(alignment: .leading, spacing: metrics.space(.xs)) {
                    HStack {
                        Text(verbatim: conflict.path)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Text(verbatim: conflict.class.variantName)
                            .font(.caption)
                            .foregroundStyle(theme[.accent])
                    }
                    Text(verbatim: conflict.class.strategy)
                        .font(.caption)
                        .foregroundStyle(theme[.textSecondary])
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, metrics.space(.xs))
            }
            .accessibilityIdentifier("merge.conflictList")
    }
}
