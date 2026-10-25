import AletheDesign
import AletheDocuments
import AletheFoundation
import AletheIntegrations
import AletheModel
import AletheOrchestrator
import SwiftUI

struct OrchestratorWorkerActions: View {
    let job: JobSnapshot
    let project: ProjectID
    let board: OrchestratorBoardModel
    let units: BoardUnits

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) var theme
    @State private var answering = false
    @State private var draft = ""
    @State private var sending = false
    @State private var busy = false
    @State private var confirmingCancel = false
    @State private var diffOpen = false
    @State var diff: WorkerDiffState = .idle
    @State private var failure: WorkerActionFailure? {
        didSet { if let failure, failure != oldValue { AppLog.shown(failure.logLine, .orchestrator) } }
    }

    private var service: OrchestratorService { environment.orchestrator }

    var body: some View {
        if !job.native {
            VStack(alignment: .leading, spacing: units.space(.s)) {
                if job.status == .blocked, let ask = WorkerAsk(job) {
                    askView(ask)
                }
                if WorkerActions.canMessage(job) {
                    composer
                }
                actionRow
                if diffOpen {
                    diffView
                }
                if let failure {
                    failureView(failure)
                }
            }
            .confirmationDialog(Text(verbatim: String(format: String(localized: "orchestrator.cancelConfirmTitle"), job.id)),
                                isPresented: $confirmingCancel, titleVisibility: .visible) {
                Button("orchestrator.cancelConfirm", role: .destructive) { cancel() }
                    .accessibilityIdentifier("orchestrator.cancel.confirm")
                Button("orchestrator.cancelKeep", role: .cancel) {}
                    .accessibilityIdentifier("orchestrator.cancel.keep")
            } message: {
                Text("orchestrator.cancelConfirmMessage")
            }
            .task(id: diffKey) {
                guard diffOpen else { return }
                await loadDiff()
            }
        }
    }

    private func askView(_ ask: WorkerAsk) -> some View {
        VStack(alignment: .leading, spacing: units.space(.xs)) {
            HStack(spacing: units.space(.xs)) {
                Image(systemName: ask.kind == .fileChange ? "doc.badge.ellipsis" : "terminal")
                    .accessibilityHidden(true)
                Text("orchestrator.askLabel")
                    .textCase(.uppercase)
                    .tracking(units.size(1))
            }
            .font(units.font(.caption).weight(.bold))
            .foregroundStyle(theme[.statusWaiting])

            Text(ask.kind == .fileChange ? "orchestrator.askFileChange" : "orchestrator.askCommand")
                .font(units.font(.footnote).weight(.medium))
                .foregroundStyle(theme[.textPrimary])
            if let command = ask.command {
                askCommand(command)
            }
            if let reason = ask.reason {
                Text(verbatim: reason)
                    .font(units.font(.footnote))
                    .foregroundStyle(theme[.textSecondary])
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let elsewhere = WorkerActions.elsewhere(ask: ask, job: job) {
                HStack(spacing: units.space(.xxs)) {
                    Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
                    Text(verbatim: String(format: String(localized: "orchestrator.askIn"), elsewhere))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(units.font(.caption).weight(.semibold))
                .foregroundStyle(theme[.statusWaiting])
                .help(Text("orchestrator.askOutside"))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("orchestrator.worker.\(job.id).askIn")
            }
            FlowLayout(spacing: units.space(.xs), lineSpacing: units.space(.xs), leading: true) {
                ForEach(WorkerDecision.all) { entry in
                    actionButton(entry.label, help: entry.hint, prominent: entry.decision == .accept,
                                 id: "orchestrator.worker.\(job.id).answer.\(entry.decision.rawValue)") {
                        answer(entry.decision)
                    }
                    .disabled(answering)
                }
            }
            Text("orchestrator.askHint")
                .font(units.font(.caption))
                .foregroundStyle(theme[.textTertiary])
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(units.space(.s))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme[.statusWaitingSoft], in: RoundedRectangle(cornerRadius: units.radius(.sm)))
        .overlay {
            RoundedRectangle(cornerRadius: units.radius(.sm)).strokeBorder(theme[.statusWaiting], lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orchestrator.worker.\(job.id).ask")
    }

    private func askCommand(_ command: String) -> some View {
        Text(verbatim: command)
            .font(units.font(.caption).monospaced())
            .foregroundStyle(theme[.textPrimary])
            .lineLimit(4)
            .textSelection(.enabled)
            .padding(.horizontal, units.space(.s))
            .padding(.vertical, units.space(.xxs))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: units.radius(.sm)))
            .help(Text(verbatim: command))
            .accessibilityIdentifier("orchestrator.worker.\(job.id).askCommand")
    }

    private func answer(_ decision: CodexApprovalDecision) {
        guard !answering else { return }
        answering = true
        failure = nil
        Task {
            defer { answering = false }
            do {
                _ = try await service.answer(job: job.id, decision: decision.rawValue)
            } catch {
                failure = WorkerActionFailure(title: String(localized: "orchestrator.answerFailed"), error: error)
            }
        }
    }

    private var composer: some View {
        let mode = WorkerMessageMode(job)
        return VStack(alignment: .leading, spacing: units.space(.xxs)) {
            HStack(spacing: units.space(.xs)) {
                TextField(text: $draft, prompt: Text(mode.placeholder)) { Text("orchestrator.messageLabel") }
                    .textFieldStyle(.plain)
                    .font(units.font(.footnote))
                    .foregroundStyle(theme[.textPrimary])
                    .disabled(sending)
                    .onSubmit(send)
                    .accessibilityIdentifier("orchestrator.worker.\(job.id).message")
                Text(mode.label)
                    .textCase(.uppercase)
                    .font(units.font(.caption).weight(.semibold))
                    .foregroundStyle(theme[mode == .steer ? .accent : .textTertiary])
                    .help(Text(mode.hint))
                    .accessibilityIdentifier("orchestrator.worker.\(job.id).mode.\(mode.rawValue)")
                Button(action: send) {
                    Image(systemName: "arrow.turn.down.left")
                        .font(units.font(.caption).weight(.semibold))
                        .frame(width: units.size(18), height: units.size(18))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .foregroundStyle(theme[.accent])
                .disabled(sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(Text(mode.hint))
                .accessibilityLabel(Text(mode.hint))
                .accessibilityIdentifier("orchestrator.worker.\(job.id).send")
            }
            .padding(.horizontal, units.space(.s))
            .padding(.vertical, units.space(.xs))
            .background(theme[.bgElevated], in: RoundedRectangle(cornerRadius: units.radius(.sm)))
            .overlay {
                RoundedRectangle(cornerRadius: units.radius(.sm)).strokeBorder(theme[.border], lineWidth: 1)
            }
            if mode == .resume {
                Text("orchestrator.resumeNote")
                    .font(units.font(.caption))
                    .foregroundStyle(theme[.textTertiary])
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !sending, WorkerActions.canMessage(job) else { return }
        let steer = WorkerMessageMode(job) == .steer
        sending = true
        failure = nil
        Task {
            defer { sending = false }
            do {
                _ = try await service.message(job: job.id, text: text, steer: steer)
                if draft.trimmingCharacters(in: .whitespacesAndNewlines) == text { draft = "" }
            } catch {
                failure = WorkerActionFailure(title: String(localized: "orchestrator.sendFailed"), error: error)
            }
        }
    }

    @ViewBuilder private var actionRow: some View {
        let canCancel = WorkerActions.canCancel(job)
        let canRelease = WorkerActions.canRelease(job)
        let worktree = job.worktree
        if job.hasDiff || canCancel || canRelease || worktree != nil {
            FlowLayout(spacing: units.space(.xs), lineSpacing: units.space(.xs), leading: true) {
                if job.hasDiff {
                    actionButton(diffOpen ? "orchestrator.hideDiff" : "orchestrator.viewDiff", help: nil,
                                 id: "orchestrator.worker.\(job.id).diffToggle") {
                        diffOpen.toggle()
                        if !diffOpen { diff = .idle }
                    }
                }
                if canCancel {
                    actionButton("orchestrator.cancelAction", help: "orchestrator.cancelTitle", destructive: true,
                                 id: "orchestrator.worker.\(job.id).cancel") {
                        if WorkerActions.cancelAsks(job) { confirmingCancel = true } else { cancel() }
                    }
                    .disabled(busy)
                }
                if canRelease {
                    actionButton("orchestrator.releaseAction", help: "orchestrator.releaseTitle",
                                 id: "orchestrator.worker.\(job.id).release") { release() }
                        .disabled(busy)
                }
                if let worktree {
                    actionButton("orchestrator.showInFinder", help: nil,
                                 id: "orchestrator.worker.\(job.id).reveal") {
                        OpenInActions.revealInFinder(worktree)
                    }
                    .help(Text(verbatim: worktree))
                    .disabled(!FileManager.default.fileExists(atPath: worktree))
                }
            }
        }
    }

    private func cancel() {
        guard !busy else { return }
        busy = true
        failure = nil
        Task {
            defer { busy = false }
            do {
                _ = try await service.cancel(job: job.id)
            } catch {
                failure = WorkerActionFailure(title: String(localized: "orchestrator.cancelFailed"), error: error)
            }
        }
    }

    private func release() {
        guard !busy else { return }
        busy = true
        failure = nil
        Task {
            defer { busy = false }
            do {
                _ = try await service.release(job: job.id)
            } catch {
                failure = WorkerActionFailure(title: String(localized: "orchestrator.releaseFailed"), error: error)
            }
        }
    }

    private var diffKey: String {
        "\(diffOpen)|\(job.status.rawValue)|\(job.hasDiff)|\(job.summary.count)"
    }

    private func loadDiff() async {
        if case .loaded = diff {} else { diff = .loading }
        guard let text = await service.diff(job: job.id) else {
            failure = WorkerActionFailure(title: String(localized: "orchestrator.diffFailed"),
                                          detail: String(format: String(localized: "orchestrator.unknownWorker"), job.id))
            diffOpen = false
            diff = .idle
            return
        }
        let document = await Task.detached(priority: .userInitiated) { DiffParser.parse(text) }.value
        guard !Task.isCancelled, diffOpen else { return }
        diff = .loaded(document)
    }

    private func failureView(_ failure: WorkerActionFailure) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: units.space(.xs)) {
            Image(systemName: "exclamationmark.octagon.fill").accessibilityHidden(true)
            VStack(alignment: .leading, spacing: units.size(1)) {
                Text(verbatim: failure.title).font(units.font(.caption).weight(.semibold))
                Text(verbatim: failure.detail).font(units.font(.caption)).lineLimit(3)
            }
            Spacer(minLength: 0)
            Button { self.failure = nil } label: {
                Image(systemName: "xmark").font(units.font(.caption))
            }
            .buttonStyle(.borderless)
            .help(Text("orchestrator.dismissError"))
            .accessibilityLabel(Text("orchestrator.dismissError"))
        }
        .foregroundStyle(theme[.statusOffline])
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orchestrator.worker.\(job.id).failure")
    }

    private func actionButton(_ label: LocalizedStringKey, help: LocalizedStringKey?, prominent: Bool = false,
                              destructive: Bool = false, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(units.font(.caption).weight(.medium))
                .padding(.horizontal, units.space(.s))
                .padding(.vertical, units.size(3))
                .foregroundStyle(theme[prominent ? .bg : destructive ? .statusOffline : .textPrimary])
                .background(theme[prominent ? .accent : .bgElevated], in: RoundedRectangle(cornerRadius: units.radius(.sm)))
                .overlay {
                    RoundedRectangle(cornerRadius: units.radius(.sm))
                        .strokeBorder(theme[prominent ? .accent : .border], lineWidth: 1)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help.map { Text($0) } ?? Text(verbatim: ""))
        .accessibilityIdentifier(id)
    }
}
