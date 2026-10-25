import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct ProjectRow: View {
    @State private var dropInside = false
    @AppStorage("sidebar.web.collapsedProjects") private var collapsedProjects = "[]"
    let project: Project
    let actions: SidebarActions
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var merges = ProjectMergeWatcher()
    @State private var hovering = false
    @State private var dropTarget = false

    var body: some View {
        let tabs = project.panes.flatMap(\.tabs)
        let planning = environment.gsdSync.sessions(of: project.id)
        Group {
            if !metrics.isWebInterface && tabs.isEmpty && merges.sessions.isEmpty && planning.isEmpty {
                label
            } else {
                SidebarDisclosure(isGroup: false, item: .project(project.id), isExpanded: metrics.isWebInterface ? Binding(
                    get: { !SidebarProjectVisibility.contains(collapsedProjects, project: project.id, profile: environment.profileID) },
                    set: { collapsedProjects = SidebarProjectVisibility.setting(collapsedProjects, project: project.id,
                        profile: environment.profileID, enabled: !$0)
                    }
                ) : nil) {
                    if metrics.isWebInterface {
                        ForEach(project.panes) { pane in
                            if let tab = pane.activeTab {
                                SidebarTerminalRow(tab: tab, project: project, actions: actions)
                                    .id(pane.id)
                            } else if !pane.content.isTerminal {
                                SidebarFileRow(pane: pane, project: project, actions: actions)
                            }
                        }
                    } else {
                        ForEach(tabs) { tab in
                            SidebarTerminalRow(tab: tab, project: project, actions: actions)
                        }
                    }
                    ForEach(merges.sessions) { session in
                        SidebarMergePanel(session: session, project: project)
                    }
                    ForEach(planning) { session in
                        SidebarPlanningStatus(session: session)
                    }
                } label: {
                    label
                }
            }
        }
        .modifier(SidebarNativeDragSource(payload: SidebarDrag.payload(project.id)))
        .task(id: project.folder) {
            await merges.watch(folder: URL(filePath: project.folder, directoryHint: .isDirectory), projectID: project.id)
        }
    }

    private var label: some View {
        let doc = actions.workspace.document
        let dimmed = doc.isProjectDisabled(project.id) || doc.isSuspended(project.id)
        let selected = doc.workspace.selectedProjectID == project.id
        let working = project.panes.flatMap(\.tabs).contains { environment.terminals.activity[$0.id] == .working }
        return Label {
            HStack(spacing: metrics.isWebInterface ? metrics.size(9) : metrics.space(.xs)) {
                Text(verbatim: project.name)
                    .font(metrics.font(size: 12.5,
                        weight: selected && (!metrics.isWebInterface || metrics.style == .normal) ? .medium : .regular))
                    .foregroundStyle(theme[dimmed ? .textTertiary : .textPrimary])
                    .lineLimit(metrics.isWebInterface ? 1 : nil)
                    .frame(maxWidth: metrics.isWebInterface ? .infinity : nil, alignment: .leading)
                if working && !metrics.isWebInterface {
                    AletheActivitySpinner()
                        .accessibilityLabel(Text("agentStatus.working"))
                }
                if !project.panes.isEmpty && project.panes.allSatisfy(\.isDisabled) {
                    Image(systemName: metrics.isWebInterface ? "pause" : "pause.circle")
                        .webProfileSized(metrics.isWebInterface ? 11 : 14)
                        .modifier(SidebarSymbolAppearance(size: 11))
                        .foregroundStyle(theme[metrics.isWebInterface ? .fgFaint : .statusDisabled])
                        .accessibilityLabel(Text("sidebar.disableProject"))
                }
                if !metrics.isWebInterface { Spacer(minLength: metrics.space(.xxs)) }
                Button { environment.editorRequest = .newTerminal(project.id) } label: {
                    Label { Text("terminal.new") } icon: { Image(systemName: "plus")
                        .webProfileSized(metrics.isWebInterface ? (metrics.style == .clean ? 12 : 15) : 14)
                    }
                        .modifier(SidebarSymbolAppearance(size: metrics.style == .clean ? 12 : 15))
                }
                .buttonStyle(AletheIconButtonStyle(side: 20))
                .help(Text("terminal.new"))
                .opacity(hovering || (metrics.isWebInterface && project.panes.isEmpty) ? 1 : 0)
                if metrics.isWebInterface {
                    SidebarRowEndSlot(active: working, hovering: hovering) {
                        if working {
                            AletheSidebarSizeSpinner()
                                .accessibilityLabel(Text("agentStatus.working"))
                        }
                    } action: {
                        WebMenu { ProjectContextMenu(project: project, actions: actions) } label: {
                            Label { Text("sidebar.rowMenu") } icon: { Image(systemName: "ellipsis")
                                .webProfileSized(metrics.style == .clean ? 13 : 14)
                            }
                        }
                        .menuIndicator(.hidden)
                        .menuStyle(.borderlessButton)
                        .modifier(SidebarMenuAppearance(size: metrics.style == .clean ? 13 : 14))
                        .fixedSize()
                        .help(Text("sidebar.rowMenu"))
                    }
                } else {
                    Menu { ProjectContextMenu(project: project, actions: actions) } label: {
                        Label { Text("sidebar.rowMenu") } icon: { Image(systemName: "ellipsis").webProfileSized(14) }
                    }
                    .menuIndicator(.hidden)
                    .menuStyle(.borderlessButton)
                    .modifier(SidebarMenuAppearance())
                    .fixedSize()
                    .frame(width: metrics.isWebInterface ? metrics.size(hovering ? 20 : working ? 16 : 0) : nil)
                    .help(Text("sidebar.rowMenu"))
                    .opacity(hovering ? 1 : 0)
                    .overlay {
                        if metrics.isWebInterface && working && !hovering {
                            AletheActivitySpinner()
                                .accessibilityLabel(Text("agentStatus.working"))
                                .allowsHitTesting(false)
                        }
                    }
                }
            }
        } icon: {
            if metrics.isWebInterface {
                SidebarCoverImage(source: project.iconUrl ?? "", side: metrics.style == .normal ? 16 : 15) {
                    Image(systemName: "folder").webProfileSized(metrics.style == .clean ? 15 : 16)
                        .font(metrics.font(size: metrics.style == .clean ? 15 : 16))
                        .foregroundStyle(theme[project.color.token])
                }
                .saturation(dimmed ? 0 : 1)
                .opacity(dimmed ? 0.6 : 1)
            } else {
                AletheMonogram(name: project.name, color: theme[project.color.token])
                    .opacity(dimmed ? 0.6 : 1)
            }
        }
        .modifier(SidebarLabelAppearance(isGroup: false, iconSize: 16))
        .modifier(SidebarWebRow(kind: .project))
        .modifier(SidebarWebClick(single: {
            actions.workspace.update { $0.openWebProject(project.id) }
            environment.showingHome = false
        }))
        .onHover { hovering = $0 }
        .tag(SidebarItem.project(project.id))
        .help(Text(verbatim: project.folder))
        .modifier(SidebarProjectRowDrop(project: project.id, actions: actions,
                                        targeted: $dropTarget, inside: $dropInside))
        .modifier(SidebarWebDragSource(payload: SidebarDrag.payload(project.id), name: project.name))
        .webContextMenu { ProjectContextMenu(project: project, actions: actions) }
        .accessibilityIdentifier("sidebar.project.\(project.name)")
    }
}
