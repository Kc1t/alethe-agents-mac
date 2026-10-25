import AletheDesign
import AletheGit
import AletheIntegrations
import AletheMerge
import AletheModel
import SwiftUI

@MainActor @Observable
final class ProjectMergeWatcher {
    private(set) var sessions: [MergeSessionSummary] = []
    static let interval: Duration = .seconds(4)

    func watch(folder: URL, projectID: ProjectID) async {
        guard let root = try? await GitRepository.discover(folder) else { return }
        while !Task.isCancelled {
            let found = await Task.detached { ConflictResolution(root: root).inProgress() }.value
            let mine = found.filter { $0.meta.projectId == nil || $0.meta.projectId == projectID.rawValue }
            if mine != sessions { sessions = mine }
            try? await Task.sleep(for: Self.interval)
        }
    }
}

struct SidebarMergePanel: View {
    let session: MergeSessionSummary
    let project: Project
    @AppStorage("sidebar.mergeGrouping") private var grouping = MergeTreeGrouping.folder
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    @State private var hovering = false

    var body: some View {
        if metrics.isWebInterface { webCard } else { nativeBody }
    }

    private var webCard: some View {
        let groups = MergeTree.groups(session.conflicts, by: grouping)
        let tone: ThemeToken = session.conflicts.isEmpty ? .statusWorking : .statusWaiting
        let radius = metrics.radius(.md)
        return VStack(alignment: .leading, spacing: metrics.size(8)) {
            Button(action: open) {
                HStack(spacing: metrics.size(6)) {
                    Image(systemName: "arrow.triangle.merge").font(metrics.font(size: 12))
                        .foregroundStyle(theme[tone])
                    Text(verbatim: String(format: String(localized: "sidebar.merge.title"),
                                          session.meta.source, session.meta.target))
                        .font(metrics.monoFont(size: 12, weight: .semibold))
                        .foregroundStyle(theme[.fg])
                        .lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(stageTitle(session.stage))
                        .font(metrics.font(size: 10, weight: .semibold))
                        .foregroundStyle(theme[tone])
                        .lineLimit(1)
                        .padding(.horizontal, metrics.size(6)).padding(.vertical, metrics.size(2))
                        .background(theme[tone == .statusWorking ? .statusWorkingSoft : .statusWaitingSoft],
                                    in: RoundedRectangle(cornerRadius: metrics.size(4)))
                        .overlay(RoundedRectangle(cornerRadius: metrics.size(4))
                            .strokeBorder(theme[tone], lineWidth: metrics.size(1)))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("sidebar.merge.open"))
            if !groups.isEmpty {
                Text(verbatim: String(format: String(localized: "sidebar.merge.conflicts"), session.conflicts.count))
                    .font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted])
                ForEach(groups) { group in
                    WebDisclosure {
                        HStack(spacing: metrics.size(6)) {
                            Image(systemName: grouping == .folder ? "folder" : "tag")
                                .font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted])
                            Text(verbatim: group.title).font(metrics.font(size: 12, weight: .semibold))
                                .foregroundStyle(theme[.fg]).lineLimit(1).truncationMode(.middle)
                        }
                    } content: {
                        VStack(alignment: .leading, spacing: metrics.size(2)) {
                            ForEach(group.files, id: \.path) { file in
                                Button(action: open) {
                                    HStack(spacing: metrics.size(6)) {
                                        Image(systemName: "exclamationmark.triangle").font(metrics.font(size: 10))
                                            .foregroundStyle(theme[.statusWaiting])
                                        Text(verbatim: grouping == .folder ? MergeTree.fileName(of: file.path) : file.path)
                                            .font(metrics.font(size: 11)).foregroundStyle(theme[.fgMuted])
                                            .lineLimit(1).truncationMode(.middle)
                                    }
                                    .padding(.vertical, metrics.size(2))
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .help(Text(verbatim: "\(file.path) — \(file.class.variantName)"))
                                .accessibilityIdentifier("sidebar.merge.file")
                            }
                        }
                    }
                }
            }
        }
        .padding(metrics.size(10))
        .background(theme[.panel], in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius)
            .strokeBorder(theme[hovering ? .borderStrong : .border], lineWidth: metrics.size(1)))
        .padding(.vertical, metrics.size(4))
        .onHover { hovering = $0 }
        .contextMenu {
            Button("sidebar.merge.open", action: open)
            Divider()
            Button { grouping = .folder } label: {
                Label("sidebar.merge.groupByFolder", systemImage: grouping == .folder ? "checkmark" : "")
            }
            Button { grouping = .class } label: {
                Label("sidebar.merge.groupByClass", systemImage: grouping == .class ? "checkmark" : "")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("sidebar.merge.\(session.id)")
    }

    @ViewBuilder private var nativeBody: some View {
        let groups = MergeTree.groups(session.conflicts, by: grouping)
        if groups.isEmpty {
            header
        } else {
            DisclosureGroup {
                ForEach(groups) { group in
                    DisclosureGroup {
                        ForEach(group.files, id: \.path) { file in
                            Button(action: open) {
                                Label {
                                    Text(verbatim: grouping == .folder ? MergeTree.fileName(of: file.path) : file.path)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } icon: {
                                    Image(systemName: "exclamationmark.triangle").webProfileSized(14)
                                        .foregroundStyle(theme[.statusWaiting])
                                }
                            }
                            .buttonStyle(.plain)
                            .help(Text(verbatim: "\(file.path) — \(file.class.variantName)"))
                            .accessibilityIdentifier("sidebar.merge.file")
                        }
                    } label: {
                        Label {
                            Text(verbatim: group.title).lineLimit(1).truncationMode(.middle)
                        } icon: {
                            Image(systemName: grouping == .folder ? "folder" : "tag").webProfileSized(14)
                                .foregroundStyle(theme[.textSecondary])
                        }
                    }
                }
            } label: {
                header
            }
        }
    }

    private var header: some View {
        Button(action: open) {
            Label {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: String(format: String(localized: "sidebar.merge.title"),
                                          session.meta.source, session.meta.target))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: metrics.space(.xs)) {
                        Text(stageTitle(session.stage))
                        if !session.conflicts.isEmpty {
                            Text(verbatim: "·")
                            Text(verbatim: String(format: String(localized: "sidebar.merge.conflicts"), session.conflicts.count))
                        }
                    }
                    .font(metrics.font(.footnote))
                    .foregroundStyle(theme[.textSecondary])
                }
            } icon: {
                Image(systemName: "arrow.triangle.merge").webProfileSized(14)
                    .foregroundStyle(theme[session.conflicts.isEmpty ? .accent : .statusWaiting])
            }
        }
        .buttonStyle(.plain)
        .help(Text("sidebar.merge.open"))
        .contextMenu {
            Button("sidebar.merge.open", action: open)
            Divider()
            Picker("sidebar.merge.groupBy", selection: $grouping) {
                Text("sidebar.merge.groupByFolder").tag(MergeTreeGrouping.folder)
                Text("sidebar.merge.groupByClass").tag(MergeTreeGrouping.class)
            }
        }
        .accessibilityIdentifier("sidebar.merge.\(session.id)")
    }

    private func open() {
        environment.editorRequest = .mergeCenter(project.id, resume: session.id)
    }

    private func stageTitle(_ stage: MergeCenterStage) -> LocalizedStringKey {
        if case .analyze = stage {
            return "merge.stage.analyze"
        } else if case .prepare = stage {
            return "merge.stage.prepare"
        } else if case .validate = stage {
            return "merge.stage.validate"
        } else {
            return "merge.stage.finish"
        }
    }
}

struct SidebarPlanningStatus: View {
    let session: GSDSyncSession
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        Button {
            environment.editorRequest = .gsdSyncActivity(GSDSyncActivityTarget(session))
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: format("sidebar.planning.title", session.name))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    HStack(spacing: metrics.space(.xs)) {
                        GSDSyncStateGlyph(session: session)
                        Text(verbatim: GSDPlanningText.progress(session) ?? String(localized: "gsdSync.planning.started"))
                    }
                    .font(metrics.font(.footnote))
                    .foregroundStyle(theme[.textSecondary])
                }
            } icon: {
                Image(systemName: session.planning.reportedComplete ? "checkmark.circle" : "list.bullet.clipboard").webProfileSized(14)
                    .foregroundStyle(theme[session.planning.reportedComplete ? .statusActive : .accent])
            }
        }
        .buttonStyle(.plain)
        .help(Text("sidebar.planning.open"))
        .accessibilityIdentifier("sidebar.planning.\(session.name)")
    }
}
