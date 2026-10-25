import AletheDesign
import AletheDocuments
import AletheFoundation
import AletheIntegrations
import AletheModel
import AletheOrchestrator
import SwiftUI

extension OrchestratorWorkerActions {
    @ViewBuilder var diffView: some View {
        Group {
            if case .idle = diff {
                Text("orchestrator.diffLoading")
                    .font(units.font(.caption))
                    .foregroundStyle(theme[.textTertiary])
                    .padding(units.space(.s))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if case .loading = diff {
                Text("orchestrator.diffLoading")
                    .font(units.font(.caption))
                    .foregroundStyle(theme[.textTertiary])
                    .padding(units.space(.s))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if case .loaded(let document) = diff, document.isEmpty {
                Text("diff.empty")
                    .font(units.font(.caption))
                    .foregroundStyle(theme[.textTertiary])
                    .padding(units.space(.s))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if case .loaded(let document) = diff {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(document.files) { file in
                            diffFile(file)
                        }
                    }
                    .font(units.font(.caption).monospaced())
                    .textSelection(.enabled)
                }
                .frame(height: diffHeight(document))
            }
        }
        .background(theme[.bg], in: RoundedRectangle(cornerRadius: units.radius(.sm)))
        .clipShape(RoundedRectangle(cornerRadius: units.radius(.sm)))
        .overlay { RoundedRectangle(cornerRadius: units.radius(.sm)).strokeBorder(theme[.borderSubtle], lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("orchestrator.worker.\(job.id).diff")
    }

    @ViewBuilder private func diffFile(_ file: DiffFile) -> some View {
        Text(verbatim: file.path)
            .font(units.font(.caption).weight(.semibold))
            .foregroundStyle(theme[.textPrimary])
            .padding(.horizontal, units.space(.s))
            .padding(.vertical, units.space(.xxs))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme[.bgElevated])
        ForEach(Array(file.hunks.enumerated()), id: \.offset) { _, hunk in
            Text(verbatim: hunk.header)
                .foregroundStyle(theme[.accent])
                .padding(.horizontal, units.space(.s))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme[.accentFaint])
            ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                Text(verbatim: WorkerActions.diffText(line))
                    .foregroundStyle(theme[line.kind == .note ? .textTertiary : .textPrimary])
                    .fixedSize()
                    .padding(.horizontal, units.space(.s))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(diffBackground(line.kind))
            }
        }
    }

    private func diffBackground(_ kind: DiffLine.Kind) -> Color {
        if case .added = kind {
            return theme[.statusActive].opacity(0.14)
        } else if case .removed = kind {
            return theme[.statusStopped].opacity(0.14)
        } else if case .context = kind {
            return .clear
        } else {
            return .clear
        }
    }

    private func diffHeight(_ document: DiffDocument) -> CGFloat {
        let rows = document.files.reduce(0) { total, file in
            total + 1 + file.hunks.reduce(0) { $0 + 1 + $1.lines.count }
        }
        return units.size(CGFloat(min(rows, 18)) * 14 + 4)
    }
}
