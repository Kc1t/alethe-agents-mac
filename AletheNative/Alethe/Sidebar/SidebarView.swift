import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct SidebarView: View {
    @AppStorage(SidebarProjectVisibility.archivedGroupsKey) private var archivedGroups = "[]"
    @AppStorage(SidebarProjectVisibility.revealKey) private var revealHidden = false

    @Environment(AppEnvironment.self) private var environment
    @Environment(\.undoManager) private var undoManager
    @Environment(\.metrics) private var metrics

    var body: some View {
        if let workspace = environment.workspace {
            content(workspace)
        } else {
            List {}.modifier(SidebarListAppearance())
        }
    }

    @ViewBuilder private func content(_ workspace: WorkspaceModel) -> some View {
        if metrics.isWebInterface {
            VStack(spacing: 0) {
                SidebarProjectsHeader(actions: SidebarActions(workspace: workspace, undoManager: undoManager))
                if workspace.document.projects.isEmpty && workspace.document.groups.isEmpty {
                    GeometryReader { geometry in
                        ScrollView {
                            SidebarWebEmptyState()
                                .frame(minHeight: geometry.size.height)
                        }
                    }
                    .accessibilityIdentifier("sidebar.list")
                    .dropDestination(for: URL.self) { urls, _ in
                        !SidebarActions(workspace: workspace, undoManager: undoManager).addProjects(folders: urls).isEmpty
                    }
                    .webContextMenu {
                        SidebarMenuButton("menu.file.newProject", symbol: "plus") {
                            environment.editorRequest = .newProject(.ungrouped)
                        }
                        SidebarMenuButton("sidebar.addProject", symbol: "folder.badge.plus") {
                            SidebarActions(workspace: workspace, undoManager: undoManager).chooseFolders()
                        }
                        SidebarMenuButton("menu.file.newGroup", symbol: "folder.badge.plus") {
                            environment.editorRequest = .newGroup(parent: nil)
                        }
                    }
                } else { projectList(workspace) }
                if workspace.document.groups.contains(where: { groupArchived($0.id) }) || workspace.document.projects.contains(where: {
                    $0.hidden == true
                    || $0.archived == true
                }) {
                    WebMenu { visibilityControls(workspace) } label: {
                        Label { Text("sidebar.web.projectVisibility") } icon: { Image(systemName: "eye").webProfileSized(14) }
                            .font(metrics.font(size: 11))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(metrics.size(8))
                    }
                    .menuStyle(.borderlessButton)
                    .padding(.horizontal, metrics.size(8))
                    .accessibilityIdentifier("sidebar.projectVisibility")
                }
            }
        } else { projectList(workspace) }
    }

    private func projectList(_ workspace: WorkspaceModel) -> some View {
        let actions = SidebarActions(workspace: workspace, undoManager: undoManager)
        let doc = workspace.document
        let projectIDs = doc.ungroupedProjectIDs.filter {
            !metrics.isWebInterface || SidebarProjectVisibility.visible(doc.project($0), reveal: revealHidden)
        }
        return List(selection: selection(workspace, actions)) {
            Section {
                if doc.projects.isEmpty && doc.groups.isEmpty {
                    VStack(alignment: .leading, spacing: metrics.space(.s)) {
                        Label { Text("sidebar.empty.title") } icon: { Image(systemName: "folder").webProfileSized(14) }
                            .font(metrics.font(.headline))
                        Text("sidebar.empty.detail")
                            .font(metrics.font(.caption))
                        Button("menu.file.newProject") { environment.editorRequest = .newProject(.ungrouped) }
                    }
                    .padding(metrics.space(.s))
                    .accessibilityIdentifier("sidebar.empty")
                }
                ForEach(doc.childGroups(of: nil).filter {
                    !metrics.isWebInterface || !SidebarProjectVisibility.containsGroup(archivedGroups, group: $0.id,
                        profile: environment.profileID) }) { group in
                    GroupRow(group: group, actions: actions)
                }
                .onInsert(of: metrics.isWebInterface ? [] : [.plainText]) { index, providers in
                    SidebarDrag.load(providers) { actions.insertGroup($0, under: nil, at: index) }
                }
                if metrics.isWebInterface && projectIDs.isEmpty {
                    SidebarUngroupedDropArea(actions: actions)
                }
                ForEach(projectIDs, id: \.self) { id in
                    if let project = doc.project(id) {
                        ProjectRow(project: project, actions: actions)
                    }
                }
                .onMove(perform: metrics.isWebInterface ? nil : { source, destination in actions.reorder(in: .ungrouped,
                    from: source, to: destination, visibleIDs: nil) })
                .onInsert(of: metrics.isWebInterface ? [] : [.plainText]) { index, providers in
                    SidebarDrag.load(providers) { actions.insert($0, into: .ungrouped,
                        at: metrics.isWebInterface ? actions.insertionIndex(index, in: .ungrouped, visibleIDs: projectIDs) : index) }
                }
            } header: {
                if !metrics.isWebInterface { SidebarProjectsHeader(actions: actions) }
            }
        }
        .modifier(SidebarListAppearance())
        .modifier(SidebarWebDropSurface(actions: actions))
        .environment(\.sidebarRowSize, metrics.style == .clean ? .small : .medium)
        .accessibilityIdentifier("sidebar.list")
        .modifier(SidebarNativeFolderDrop(actions: actions))
        .webContextMenu {
            SidebarMenuButton("menu.file.newProject", symbol: "plus") { environment.editorRequest = .newProject(.ungrouped) }
            SidebarMenuButton("sidebar.addProject", symbol: "folder.badge.plus") { actions.chooseFolders() }
            SidebarMenuButton("menu.file.newGroup", symbol: "folder.badge.plus") { environment.editorRequest = .newGroup(parent: nil) }
            if metrics.isWebInterface {
                visibilityControls(workspace)
            }
        }
    }

    @ViewBuilder private func visibilityControls(_ workspace: WorkspaceModel) -> some View {
        let groups = workspace.document.groups.filter { groupArchived($0.id) }
        if !groups.isEmpty {
            WebSubmenu("sidebar.web.restoreGroups") {
                ForEach(groups) { group in
                    Button {
                        archivedGroups = SidebarProjectVisibility.setting(archivedGroups,
                            project: ProjectID(rawValue: group.id.rawValue), profile: environment.profileID, enabled: false)
                    } label: { Text(verbatim: group.name) }
                }
            }
        }
        let hidden = workspace.document.projects.filter {
            $0.hidden == true
                && $0.archived != true
        }
        let archived = workspace.document.projects.filter {
            $0.archived == true
        }
        if !hidden.isEmpty || revealHidden {
            WebMenuDivider()
            SidebarMenuButton(revealHidden ? "sidebar.web.hideHidden" : "sidebar.web.revealHidden",
                              symbol: revealHidden ? "eye.slash" : "eye") { revealHidden.toggle() }
        }
        if !archived.isEmpty {
            WebSubmenu("sidebar.web.restoreArchived", symbol: "archivebox") {
                ForEach(archived) { project in
                    Button {
                        workspace.update { $0.updateProject(project.id) { $0.archived = false } }
                    } label: { Label { Text(verbatim: project.name) } icon: { Image(systemName: "arrow.uturn.backward")
                        .webProfileSized(14) } }
                }
            }
        }
    }

    private func groupArchived(_ id: GroupID) -> Bool {
        SidebarProjectVisibility.contains(archivedGroups, project: ProjectID(rawValue: id.rawValue), profile: environment.profileID)
    }

    private func selection(_ workspace: WorkspaceModel, _ actions: SidebarActions) -> Binding<SidebarItem?> {
        Binding {
            if metrics.isWebInterface { return nil }
            let state = workspace.document.workspace
            if let focused = state.focusedPaneID, let (project, pane) = workspace.document.pane(focused),
               project.id == state.selectedProjectID, let tab = pane.activeTab {
                return .tab(tab.id)
            }
            return state.selectedProjectID.map(SidebarItem.project)
        } set: { item in
            if !metrics.isWebInterface { actions.select(item) }
        }
    }
}
