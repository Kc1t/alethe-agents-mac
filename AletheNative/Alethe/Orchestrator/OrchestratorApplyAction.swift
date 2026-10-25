import AletheDesign
import AletheMerge
import AletheModel
import AletheOrchestrator
import SwiftUI

struct OrchestratorApplyAction: View {
    let job: JobSnapshot
    let project: ProjectID
    let board: OrchestratorBoardModel
    let units: BoardUnits
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme

    private var center: ApplyWorktreeCenter { .shared }
    private static let listedFiles = 8

    var body: some View {
        let phase = center.phase(job.id)
        if !job.native, job.worktree != nil, job.status == .done || phase != .idle {
            content(phase)
                .font(units.font(.caption))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("orchestrator.apply.\(job.id).panel")
        }
    }

    @ViewBuilder private func content(_ phase: ApplyWorktreePhase) -> some View {
        if case .idle = phase {
            button("orchestrator.apply.action", symbol: "arrow.triangle.merge", prominent: true, id: "action") {
                center.review(job)
            }
            .help(Text("orchestrator.apply.help"))
        } else if case .previewing = phase {
            progress(Text("orchestrator.apply.previewing"), cancelable: true)
        } else if case .confirming(let preview) = phase {
            confirmation(preview)
        } else if case .running(let step) = phase {
            progress(Text(step.title), cancelable: step.isCancelable)
        } else if case .applied(let target) = phase {
            note(String(format: String(localized: "orchestrator.apply.applied"), target),
                 symbol: "checkmark.circle", token: .statusWorking, id: "applied")
        } else if case .nothingToApply = phase {
            HStack(spacing: units.space(.s)) {
                note(String(localized: "orchestrator.apply.nothing"), symbol: "minus.circle", token: .textSecondary, id: "nothing")
                dismissButton
            }
        } else if case .handedOff(let environmentID) = phase {
            VStack(alignment: .leading, spacing: units.space(.xs)) {
                note(String(localized: "orchestrator.apply.handedOff"), symbol: "exclamationmark.triangle",
                     token: .statusWaiting, id: "handedOff")
                HStack(spacing: units.space(.s)) {
                    button("orchestrator.apply.openMergeCenter", symbol: "arrow.triangle.branch", prominent: false, id: "mergeCenter") {
                        openMergeCenter(environmentID)
                    }
                    dismissButton
                }
            }
        } else if case .failed(let message) = phase {
            VStack(alignment: .leading, spacing: units.space(.xs)) {
                note(String(format: String(localized: "orchestrator.apply.failed"), message),
                     symbol: "xmark.octagon", token: .statusOffline, id: "failed")
                HStack(spacing: units.space(.s)) {
                    button("orchestrator.apply.retry", symbol: "arrow.clockwise", prominent: false, id: "retry") {
                        center.dismiss(job.id)
                        center.review(job)
                    }
                    dismissButton
                }
            }
        }
    }

    private func confirmation(_ preview: WorktreeApplyPreview) -> some View {
        let files = preview.files
        return VStack(alignment: .leading, spacing: units.space(.s)) {
            Text(String(format: String(localized: "orchestrator.apply.confirmTitle"), preview.source, preview.target))
                .font(units.font(.footnote).weight(.semibold))
                .foregroundStyle(theme[.textPrimary])
                .fixedSize(horizontal: false, vertical: true)
            Text(String(format: String(localized: "orchestrator.apply.confirmMessage"), preview.target))
                .foregroundStyle(theme[.textSecondary])
                .fixedSize(horizontal: false, vertical: true)
            if files.isEmpty {
                Text("orchestrator.apply.noFiles")
                    .foregroundStyle(theme[.textTertiary])
            } else {
                VStack(alignment: .leading, spacing: units.space(.xxs)) {
                    Text(String(format: String(localized: "orchestrator.apply.fileCount"), files.count))
                        .foregroundStyle(theme[.textTertiary])
                    ForEach(files.prefix(Self.listedFiles), id: \.self) { file in
                        HStack(spacing: units.space(.xs)) {
                            Image(systemName: preview.pending.contains(file) ? "pencil" : "doc")
                                .foregroundStyle(theme[.textTertiary])
                            Text(verbatim: file)
                                .foregroundStyle(theme[.textPrimary])
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .help(Text(preview.pending.contains(file) ? "orchestrator.apply.pendingFile" : "orchestrator.apply.committedFile"))
                    }
                    if files.count > Self.listedFiles {
                        Text(String(format: String(localized: "orchestrator.apply.moreFiles"), files.count - Self.listedFiles))
                            .foregroundStyle(theme[.textTertiary])
                    }
                }
                .font(units.font(.caption).monospaced())
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("orchestrator.apply.\(job.id).files")
            }
            HStack(spacing: units.space(.s)) {
                button("orchestrator.apply.confirm", symbol: "arrow.triangle.merge", prominent: true, id: "confirm") {
                    let project = project
                    let environment = environment
                    center.confirm(job.id, projectID: project.rawValue, bus: environment.multiagent.bus) { id in
                        environment.editorRequest = .mergeCenter(project, resume: id)
                    }
                }
                button("orchestrator.apply.cancel", symbol: nil, prominent: false, id: "cancel") {
                    center.cancel(job.id)
                }
            }
        }
        .padding(units.space(.s))
        .background(theme[.bg], in: RoundedRectangle(cornerRadius: units.radius(.sm)))
        .overlay(RoundedRectangle(cornerRadius: units.radius(.sm)).strokeBorder(theme[.borderSubtle]))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orchestrator.apply.\(job.id).confirmation")
    }

    private func progress(_ label: Text, cancelable: Bool) -> some View {
        HStack(spacing: units.space(.s)) {
            ProgressView().controlSize(.small)
            label
                .foregroundStyle(theme[.textSecondary])
                .accessibilityIdentifier("orchestrator.apply.\(job.id).step")
            if cancelable {
                button("orchestrator.apply.cancel", symbol: nil, prominent: false, id: "cancel") {
                    center.cancel(job.id)
                }
            }
        }
    }

    private func note(_ text: String, symbol: String, token: ThemeToken, id: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: units.space(.xs)) {
            Image(systemName: symbol).foregroundStyle(theme[token])
            Text(verbatim: text)
                .foregroundStyle(theme[.textPrimary])
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("orchestrator.apply.\(job.id).\(id)")
    }

    private var dismissButton: some View {
        button("orchestrator.apply.dismiss", symbol: nil, prominent: false, id: "dismiss") {
            center.dismiss(job.id)
        }
    }

    private func button(_ title: LocalizedStringKey, symbol: String?, prominent: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: units.space(.xxs)) {
                if let symbol { Image(systemName: symbol) }
                Text(title)
            }
            .font(units.font(.caption).weight(.medium))
            .foregroundStyle(theme[prominent ? .accentOn : .textPrimary])
            .padding(.horizontal, units.space(.s))
            .padding(.vertical, units.space(.xxs))
            .background(theme[prominent ? .accent : .bgSunken], in: RoundedRectangle(cornerRadius: units.radius(.sm)))
            .overlay(RoundedRectangle(cornerRadius: units.radius(.sm)).strokeBorder(theme[prominent ? .accent : .border]))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("orchestrator.apply.\(job.id).\(id)")
    }

    private func openMergeCenter(_ environmentID: String) {
        environment.editorRequest = .mergeCenter(project, resume: environmentID)
    }
}

extension WorktreeApplyStep {
    private static let titleValues: [WorktreeApplyStep: String] = [
        .committing: "orchestrator.apply.step.committing",
        .fetching: "orchestrator.apply.step.fetching",
        .analyzing: "orchestrator.apply.step.analyzing",
        .preparing: "orchestrator.apply.step.preparing",
    ]

    var title: LocalizedStringKey {
        LocalizedStringKey(Self.titleValues[self] ?? "orchestrator.apply.step.finalizing")
    }
}
