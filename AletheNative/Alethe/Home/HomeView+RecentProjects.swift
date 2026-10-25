import AletheAgents
import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct RecentProjects: View {
    let workspace: WorkspaceModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    @State private var hoveredProject: ProjectID?

    var body: some View {
        let recent = workspace.document.recentProjectIDs(limit: 6).compactMap(workspace.document.project)
        VStack(alignment: .leading, spacing: metrics.size(metrics.isWebInterface ? 12 : 8)) {
            HStack {
                HomeSectionHeader(title: "home.recent", count: recent.isEmpty ? nil : recent.count)
                Spacer()
                if metrics.isWebInterface {
                    Button("home.recent.viewAll") { environment.editorRequest = .findJump }
                        .buttonStyle(.plain).font(metrics.font(size: 10))
                        .textCase(.uppercase).tracking(metrics.size(0.6))
                        .foregroundStyle(theme[.textQuaternary])
                        .accessibilityIdentifier("home.action.findJump")
                } else {
                    Button("home.recent.viewAll") { environment.editorRequest = .findJump }.buttonStyle(.link)
                }
            }
            if recent.isEmpty {
                VStack(alignment: .leading, spacing: metrics.space(.s)) {
                    Text("home.recent.empty").foregroundStyle(theme[.textSecondary])
                    Button("home.recent.create") { environment.editorRequest = .newProject(.ungrouped) }
                        .buttonStyle(AletheButtonStyle(size: .small))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .aletheCard()
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: metrics.size(8)), count: 2),
                          spacing: metrics.size(5)) {
                    ForEach(recent) { project in card(project) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func lastUsed(_ id: ProjectID) -> Date? {
        let history = workspace.document.workspace.history.filter {
            $0.snapshot.selectedProjectID == id || $0.snapshot.openProjectIDs.contains(id)
        }.map(\.visitedAt)
        let tabs = workspace.document.workspace.tabs.filter {
            $0.projectID == id || $0.snapshot.openProjectIDs.contains(id)
        }.map(\.updatedAt)
        return (history + tabs).max()
    }

    private func card(_ project: Project) -> some View {
        let terminals = project.panes.filter { $0.content.isTerminal }.count
        return Button {
            workspace.update { $0.openInTab(project.id) }
            environment.showingHome = false
        } label: {
            HStack(spacing: metrics.size(metrics.isWebInterface ? 9 : 8)) {
                if metrics.isWebInterface {
                    SidebarCoverImage(source: project.iconUrl ?? "", side: 34) {
                        Text(verbatim: String(project.name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                            .font(metrics.font(size: 15, weight: .semibold))
                            .foregroundStyle(theme[.accentOn])
                            .frame(width: metrics.size(34), height: metrics.size(34))
                            .background(theme[project.color.token], in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
                    }
                    .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm))
                        .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                } else { AletheMonogram(name: project.name, color: theme[project.color.token], side: 28) }
                VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                    Text(verbatim: project.name).font(metrics.font(size: 11, weight: .semibold)).lineLimit(1)
                    TimelineView(.everyMinute) { _ in
                        HStack(spacing: metrics.space(.xxs)) {
                            Text(String(format: String(localized: terminals == 1 && metrics.isWebInterface
                                        ? "home.web.oneTerminal" : "home.recent.terminals"), terminals))
                            if let lastUsed = lastUsed(project.id) {
                                Text(verbatim: "·")
                                Text(lastUsed, format: .relative(presentation: .named))
                            }
                        }
                        .font(metrics.monoFont(size: 9)).foregroundStyle(theme[.textTertiary])
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.right").webProfileSized(14).foregroundStyle(theme[.textTertiary])
                    .offset(x: hoveredProject == project.id && !metrics.reducesMotion && (!metrics.isWebInterface ||
                        metrics.style != .clean) ? metrics.size(2) : 0)
                    .animation(Motion.animation(Motion.quick, reduceMotion: metrics.reducesMotion), value: hoveredProject)
            }
            .contentShape(Rectangle())
            .padding(.vertical, metrics.size(7))
            .padding(.horizontal, metrics.size(10))
            .frame(minHeight: metrics.size(44))
            .background(theme[.bgSunken].opacity(metrics.isWebInterface ? 0.86 : 1),
                in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
            .overlay {
                if metrics.isWebInterface {
                    RoundedRectangle(cornerRadius: metrics.radius(.sm))
                        .strokeBorder(theme[hoveredProject == project.id ? .borderStrong : .border].opacity(0.82),
                            lineWidth: metrics.size(1))
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hoveredProject = $0 ? project.id : nil }
        .accessibilityIdentifier("home.recent.\(project.name)")
    }
}
