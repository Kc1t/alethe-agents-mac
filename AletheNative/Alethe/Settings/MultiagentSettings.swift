import AletheDesign
import AletheFoundation
import AletheGit
import AletheIntegrations
import AletheModel
import AletheOrchestrator
import SwiftUI

struct MultiagentSettings: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var model = MultiagentSettingsModel()
    @State private var cancelling: SchedulerTask?

    private var projects: [Project] { environment.workspace?.document.projects ?? [] }

    var body: some View {
        SettingsPageForm {
            schedulerSection
            metricsSection
            tracesSection
            auditSection
            if metrics.isWebInterface {
                MultiagentWorkerSettings()
            }
        }
        .formStyle(.grouped)
        .frame(minHeight: metrics.isWebInterface ? nil : metrics.size(520) / metrics.scale)
        .accessibilityIdentifier("settings.multiagent")
        .task { await model.run(controller: environment.multiagent) }
        .task(id: projectKey) { await model.select(project: selectedProject, controller: environment.multiagent) }
        .onChange(of: model.correlationFilter) { _, _ in model.refreshTelemetrySoon() }
        .onAppear {
            if model.projectID == nil {
                model.projectID = environment.multiagent.focusedProject?.id ?? projects.first?.id.rawValue
            }
        }
        .webConfirm(isPresented: cancelPresented, message: String(localized: "settings.multiagent.cancel.message"),
                    title: format("settings.multiagent.cancel.title", cancelling?.title ?? ""),
                    confirmTitle: String(localized: "settings.multiagent.cancel.confirm"), destructive: true) {
            if let task = cancelling { model.cancel(task) }
        }
        .confirmationDialog(cancelTitle, isPresented: Binding(get: { !metrics.isWebInterface && cancelling != nil },
                                                              set: { if !$0 { cancelling = nil } }),
                            titleVisibility: .visible) {
            Button("settings.multiagent.cancel.confirm", role: .destructive) {
                if let task = cancelling { model.cancel(task) }
                cancelling = nil
            }
            .accessibilityIdentifier("multiagent.cancel.confirm")
            Button("settings.multiagent.cancel.keep", role: .cancel) { cancelling = nil }
        } message: {
            Text("settings.multiagent.cancel.message")
        }
    }

    private var schedulerSection: some View {
        Section {
            HStack(spacing: metrics.space(.m)) {
                if metrics.isWebInterface {
                    WebDropdown(selection: $model.projectID,
                                 options: [String?.none] + projects.map { Optional($0.id.rawValue) }) { id in
                        Text(verbatim: id.flatMap { id in projects.first {
                            $0.id.rawValue == id
                        }?.name
                        } ?? String(localized: "settings.multiagent.project.none"))
                    }
                    .accessibilityLabel(Text("settings.multiagent.project"))
                    .accessibilityIdentifier("multiagent.project")
                .settingsRowSurface(.standalone)
                } else {
                Picker(selection: $model.projectID) {
                    Text("settings.multiagent.project.none").tag(String?.none)
                    ForEach(projects) { Text(verbatim: $0.name).tag(Optional($0.id.rawValue)) }
                } label: {
                    Text("settings.multiagent.project")
                }
                .accessibilityIdentifier("multiagent.project")
                }
                if selectedProject != nil {
                    Button("settings.multiagent.tick") { model.tick() }
                        .disabled(model.isTicking)
                        .accessibilityIdentifier("multiagent.tick")
                }
            }
            if let problem = model.problem {
                Text(verbatim: problem)
                    .font(metrics.isWebInterface ? metrics.font(size: 11) : .callout)
                    .foregroundStyle(theme[.statusStopped])
                    .textSelection(.enabled)
                    .accessibilityIdentifier("multiagent.problem")
            }
            if selectedProject == nil {
                note("settings.multiagent.selectHint", id: "multiagent.tasks.hint")
            } else if model.isLoadingTasks && model.tasks.isEmpty {
                note("settings.multiagent.tasks.loading", id: "multiagent.tasks.loading")
            } else if model.tasks.isEmpty {
                note("settings.multiagent.tasks.empty", id: "multiagent.tasks.empty")
            } else {
                ForEach(Array(model.tasks.enumerated()), id: \.element.id) { index, task in
                    TaskRow(task: task, index: index, titles: model.titles) { cancelling = task }
                        .settingsRowSurface(.task)
                }
            }
        } header: {
            Text(metrics.isWebInterface ? "settings.web.reference.prefs.multiagentSchedulerTitle" : "settings.multiagent.scheduler.title")
        } footer: {
            Text(metrics.isWebInterface ? "settings.web.reference.prefs.multiagentSchedulerDesc" : "settings.multiagent.scheduler.help")
        }
    }

    private var metricsSection: some View {
        Section {
            if model.metrics.isEmpty {
                note("settings.multiagent.metrics.empty", id: "multiagent.metrics.empty")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: metrics.isWebInterface ? metrics.size(140) : 140),
                    spacing: metrics.space(.m))],
                          alignment: .leading, spacing: metrics.space(.m)) {
                    ForEach(model.metrics) { metric in
                        VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                            Text(verbatim: metric.name)
                                .font(metrics.isWebInterface ? metrics.font(size: 10) : .caption)
                                .foregroundStyle(theme[.textSecondary])
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(verbatim: String(metric.data.count))
                                .font(metrics.isWebInterface ? metrics.font(size: 16).monospacedDigit() : .title3.monospacedDigit())
                                .id(metric.data.count)
                            if metric.data.lastValue > 0 {
                                Text(verbatim: format("settings.multiagent.metrics.last",
                                                      metric.data.lastValue.formatted(.number.precision(.fractionLength(2)))))
                                    .font(metrics.isWebInterface ? metrics.font(size: 10) : .caption)
                                    .foregroundStyle(theme[.textTertiary])
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("multiagent.metric.\(metric.id)")
                        .modifier(AletheSettingsRowSurfaceModifier(.metric))
                    }
                }
            }
        } header: {
            Text(metrics.isWebInterface ? "settings.web.reference.prefs.multiagentMetricsTitle" : "settings.multiagent.metrics.title")
        } footer: {
            Text(metrics.isWebInterface ? "settings.web.reference.prefs.multiagentMetricsDesc" : "settings.multiagent.metrics.help")
        }
    }

    private var tracesSection: some View {
        Section {
            TextField(text: $model.correlationFilter, prompt: Text("settings.multiagent.traces.filter.prompt")) {
                Text("settings.multiagent.traces.filter")
            }
            .accessibilityIdentifier("multiagent.traces.filter")
            if model.traces.isEmpty {
                note("settings.multiagent.traces.empty", id: "multiagent.traces.empty")
            } else {
                ForEach(Array(model.traces.enumerated()), id: \.offset) { index, event in
                    TraceRow(event: event) { model.correlationFilter = event.correlationID }
                        .accessibilityIdentifier("multiagent.trace.\(index)")
                .settingsRowSurface(.standalone)
                }
            }
        } header: {
            Text(metrics.isWebInterface ? "settings.web.reference.prefs.multiagentTracesTitle" : "settings.multiagent.traces.title")
        } footer: {
            Text(metrics.isWebInterface ? "settings.web.reference.prefs.multiagentTracesDesc" : "settings.multiagent.traces.help")
        }
    }

    private var auditSection: some View {
        Section {
            Toggle(isOn: autocommit) {
                Text("settings.multiagent.autocommit")
                Text("settings.multiagent.autocommit.help")
            }
            .accessibilityIdentifier("multiagent.autocommit")
            if selectedProject == nil {
                note("settings.multiagent.audit.selectHint", id: "multiagent.audit.hint")
            } else if model.isLoadingHistory && model.history.isEmpty {
                note("settings.multiagent.audit.loading", id: "multiagent.audit.loading")
            } else if model.history.isEmpty {
                note("settings.multiagent.audit.empty", id: "multiagent.audit.empty")
            } else {
                ForEach(Array(model.history.enumerated()), id: \.element.hash) { index, commit in
                    AuditRow(commit: commit)
                        .accessibilityIdentifier("multiagent.audit.\(index)")
                .settingsRowSurface(.standalone)
                }
            }
        } header: {
            Text(metrics.isWebInterface ? "settings.web.reference.prefs.multiagentAuditTitle" : "settings.multiagent.audit.title")
        } footer: {
            Text(metrics.isWebInterface ? "settings.web.reference.prefs.multiagentAuditDesc" : "settings.multiagent.audit.help")
        }
    }

    private var selectedProject: Project? {
        guard let id = model.projectID else { return nil }
        return projects.first { $0.id.rawValue == id }
    }

    private var projectKey: String {
        guard let project = selectedProject else { return "" }
        return "\(project.id.rawValue)|\(project.folder)|\(project.effectiveWorktreeMode.rawValue)"
    }

    private var autocommit: Binding<Bool> {
        Binding {
            environment.multiagent.isAutocommitEnabled
        } set: { enabled in
            Task { await environment.multiagent.setAutocommit(enabled) }
        }
    }

    private var cancelPresented: Binding<Bool> {
        Binding { cancelling != nil } set: { if !$0 { cancelling = nil } }
    }

    private var cancelTitle: Text {
        Text(verbatim: format("settings.multiagent.cancel.title", cancelling?.title ?? ""))
    }

    private func note(_ key: LocalizedStringKey, id: String) -> some View {
        Text(key)
            .foregroundStyle(theme[.textSecondary])
            .accessibilityIdentifier(id)
    }
}

private struct TraceRow: View {
    let event: BusEvent
    let onFilter: () -> Void
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.space(.m)) {
            VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                HStack(spacing: metrics.space(.s)) {
                    Text(verbatim: event.type)
                        .font(metrics.isWebInterface ? metrics.monoFont(size: 11, weight: .regular) : .callout.monospaced())
                    if let task = event.taskID {
                        Text(verbatim: format("settings.multiagent.traces.task", task))
                            .font(metrics.isWebInterface ? metrics.font(size: 10) : .caption)
                            .foregroundStyle(theme[.textSecondary])
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Button(action: onFilter) {
                    Text(verbatim: format("settings.multiagent.traces.correlation", event.correlationID))
                        .font(metrics.isWebInterface ? metrics.monoFont(size: 10, weight: .regular) : .caption.monospaced())
                        .foregroundStyle(theme[.textTertiary])
                }
                .buttonStyle(.plain)
                .help("settings.multiagent.traces.filterBy")
            }
            Spacer(minLength: 0)
            Text(verbatim: event.date.formatted(date: .omitted, time: .standard))
                .font(metrics.isWebInterface ? metrics.font(size: 10).monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(theme[.textSecondary])
        }
    }
}

private struct AuditRow: View {
    let commit: PlanningCommit
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        HStack(alignment: .top, spacing: metrics.space(.m)) {
            VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                HStack(spacing: metrics.space(.s)) {
                    Text(verbatim: String(commit.hash.prefix(7)))
                        .font(metrics.isWebInterface ? metrics.monoFont(size: 11, weight: .regular) : .callout.monospaced())
                        .foregroundStyle(theme[.accent])
                    Text(verbatim: commit.subject)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Text(verbatim: byline)
                    .font(metrics.isWebInterface ? metrics.font(size: 10) : .caption)
                    .foregroundStyle(theme[.textSecondary])
            }
            Spacer(minLength: 0)
            Text(verbatim: Date(timeIntervalSince1970: Double(commit.timestampMS) / 1000)
                .formatted(date: .abbreviated, time: .shortened))
                .font(metrics.isWebInterface ? metrics.font(size: 10).monospacedDigit() : .caption.monospacedDigit())
                .foregroundStyle(theme[.textSecondary])
        }
        .accessibilityElement(children: .combine)
    }

    private var byline: String {
        let author = format("settings.multiagent.audit.author", commit.author)
        guard let agent = commit.agentID else { return author }
        return "\(author) · \(format("settings.multiagent.audit.agent", agent))"
    }
}

extension SchedulerTaskStatus {
    var label: LocalizedStringKey {
        if case .pending = self {
            return "settings.multiagent.status.pending"
        } else if case .ready = self {
            return "settings.multiagent.status.ready"
        } else if case .running = self {
            return "settings.multiagent.status.running"
        } else if case .completed = self {
            return "settings.multiagent.status.completed"
        } else if case .failed = self {
            return "settings.multiagent.status.failed"
        } else {
            return "settings.multiagent.status.blocked"
        }
    }

    func color(_ theme: Theme) -> Color {
        if case .pending = self {
            return theme[.statusIdle]
        } else if case .ready = self {
            return theme[.statusWaiting]
        } else if case .running = self {
            return theme[.statusWorking]
        } else if case .completed = self {
            return theme[.statusActive]
        } else if case .failed = self {
            return theme[.statusStopped]
        } else {
            return theme[.statusDisabled]
        }
    }
}

@Observable
@MainActor
final class MultiagentSettingsModel {
    struct Metric: Identifiable, Equatable {
        var id: String
        var data: MetricData
        var name: String { id.replacingOccurrences(of: "alethe_event_", with: "").uppercased() }
    }

    static let traceLimit = 15
    static let historyLimit = 15
    static let coalescing: Duration = .milliseconds(150)

    var projectID: String?
    var correlationFilter = ""
    private(set) var tasks: [SchedulerTask] = []
    private(set) var titles: [String: String] = [:]
    private(set) var metrics: [Metric] = []
    private(set) var traces: [BusEvent] = []
    private(set) var history: [PlanningCommit] = []
    private(set) var isLoadingTasks = false
    private(set) var isLoadingHistory = false
    private(set) var isTicking = false
    private(set) var problem: String?

    @ObservationIgnored private var controller: MultiagentController?
    @ObservationIgnored private var project: MultiagentController.FocusedProject?
    @ObservationIgnored private var mode: WorktreeMode = .gitWorktree
    @ObservationIgnored private var flush: Task<Void, Never>?
    @ObservationIgnored private var historyStale = false

    func run(controller: MultiagentController) async {
        self.controller = controller
        let events = await controller.bus.subscribe()
        await refreshTelemetry()
        for await event in events {
            if event.type == BusEventType.planningCommitted { historyStale = true }
            guard flush == nil else { continue }
            flush = Task { [weak self] in
                try? await Task.sleep(for: Self.coalescing)
                guard !Task.isCancelled, let self else { return }
                self.flush = nil
                await self.refreshAll()
            }
        }
        flush?.cancel()
        flush = nil
    }

    func select(project: Project?, controller: MultiagentController) async {
        self.controller = controller
        problem = nil
        guard let project else {
            self.project = nil
            try? await controller.focus(nil)
            tasks = []
            history = []
            return
        }
        let focused = MultiagentController.FocusedProject(
            id: project.id.rawValue,
            folder: URL(filePath: (project.folder as NSString).expandingTildeInPath, directoryHint: .isDirectory)
                .standardizedFileURL)
        self.project = focused
        mode = WorktreeMode(rawValue: project.effectiveWorktreeMode.rawValue) ?? .gitWorktree
        do {
            try await controller.focus(focused)
        } catch {
            problem = String(localized: "settings.multiagent.notRepository")
        }
        isLoadingTasks = true
        try? await controller.scheduler.load(projectID: focused.id, repo: focused.folder)
        isLoadingTasks = false
        guard self.project == focused else { return }
        await refreshTasks()
        historyStale = true
        await refreshHistory()
    }

    func tick() {
        guard let controller, let project, !isTicking else { return }
        isTicking = true
        problem = nil
        let mode = mode
        Task {
            do {
                try await controller.scheduler.trigger(projectID: project.id, repo: project.folder, mode: mode)
            } catch SchedulerError.notARepository {
                problem = String(localized: "settings.multiagent.notRepository")
            } catch {
                problem = format("settings.multiagent.tickFailed", String(describing: error))
            }
            isTicking = false
            await refreshTasks()
        }
    }

    func cancel(_ task: SchedulerTask) {
        guard let controller else { return }
        Task {
            await controller.scheduler.cancel(taskID: task.id)
            await refreshTasks()
        }
    }

    func refreshTelemetrySoon() {
        Task { await refreshTelemetry() }
    }

    private func refreshAll() async {
        await refreshTasks()
        await refreshTelemetry()
        await refreshHistory()
    }

    private func refreshTasks() async {
        guard let controller, let project else { return }
        let list = await controller.scheduler.tasks(projectID: project.id)
        guard self.project == project else { return }
        tasks = Self.chainOrder(list)
        titles = Dictionary(list.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
    }

    private func refreshTelemetry() async {
        guard let controller else { return }
        let telemetry = controller.telemetry
        let filter = correlationFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        let all = await telemetry.metrics()
        let events = await telemetry.traces(correlationID: filter.isEmpty ? nil : filter)
        metrics = all.map { Metric(id: $0.key, data: $0.value) }.sorted { $0.id < $1.id }
        traces = Array(events.suffix(Self.traceLimit).reversed())
    }

    private func refreshHistory() async {
        guard historyStale, let controller, let project else { return }
        historyStale = false
        isLoadingHistory = true
        let list = (try? await controller.planningAudit.history(repository: project.folder, limit: Self.historyLimit)) ?? []
        isLoadingHistory = false
        guard self.project == project else { return }
        history = list
    }

    static func chainOrder(_ tasks: [SchedulerTask]) -> [SchedulerTask] {
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var depths: [String: Int] = [:]
        func depth(_ id: String, _ visiting: Set<String>) -> Int {
            if let known = depths[id] { return known }
            guard let task = byID[id], !visiting.contains(id) else { return 0 }
            let value = task.dependencies.map { depth($0, visiting.union([id])) + 1 }.max() ?? 0
            depths[id] = value
            return value
        }
        return tasks.sorted {
            let (left, right) = (depth($0.id, []), depth($1.id, []))
            return left == right ? $0.title < $1.title : left < right
        }
    }
}
