import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct GroupRow: View {
    @AppStorage(SidebarProjectVisibility.archivedGroupsKey) private var archivedGroups = "[]"
    @AppStorage(SidebarProjectVisibility.revealKey) private var revealHidden = false

    let group: ProjectGroup
    let actions: SidebarActions
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    private func groupArchived(_ id: GroupID) -> Bool {
        SidebarProjectVisibility.contains(archivedGroups, project: ProjectID(rawValue: id.rawValue), profile: environment.profileID)
    }

    @State private var hovering = false
    @State private var dropTarget = false

    var body: some View {
        let doc = actions.workspace.document
        let projectIDs = group.projectIDs.filter {
            !metrics.isWebInterface || SidebarProjectVisibility.visible(doc.project($0), reveal: revealHidden)
        }
        let webChildren = metrics.isWebInterface ? doc.sidebarChildren(of: group.id).filter { child in
            if case .group(let id) = child {
                return !SidebarProjectVisibility.containsGroup(archivedGroups, group: id, profile: environment.profileID)
            } else if case .project(let id) = child {
                return SidebarProjectVisibility.visible(doc.project(id), reveal: revealHidden)
            }
            preconditionFailure("Unexpected case")
        } : []
        SidebarDisclosure(isGroup: true, item: .group(group.id),
                          firstRootGroup: doc.childGroups(of: nil).first?.id == group.id, isExpanded: Binding {
            !group.isCollapsed
        } set: { expanded in
            actions.setCollapsed(group.id, !expanded)
        }) {
            if projectIDs.isEmpty && doc.childGroups(of: group.id).isEmpty {
                if metrics.isWebInterface {
                    SidebarWebGroupEmpty()
                        .modifier(SidebarWebDrop(target: .groupBody(group.id), actions: actions))
                } else {
                    Text("sidebar.group.empty")
                        .font(metrics.font(.caption))
                        .foregroundStyle(theme[.fgFaint])
                }
            }
            if metrics.isWebInterface {
                ForEach(webChildren, id: \.self) { child in
                    if case .group(let id) = child {
                        if let nested = doc.group(id) { GroupRow(group: nested, actions: actions) }
                    } else if case .project(let id) = child {
                        if let project = doc.project(id) { ProjectRow(project: project, actions: actions) }
                    }
                }
            } else {
                ForEach(doc.childGroups(of: group.id)) { child in
                    GroupRow(group: child, actions: actions)
                }
                .onInsert(of: [.plainText]) { index, providers in
                    SidebarDrag.load(providers) { actions.insertGroup($0, under: group.id, at: index) }
                }
                ForEach(projectIDs, id: \.self) { id in
                    if let project = doc.project(id) {
                        ProjectRow(project: project, actions: actions)
                    }
                }
                .onMove { source, destination in actions.reorder(in: .group(group.id), from: source, to: destination, visibleIDs: nil) }
                .onInsert(of: [.plainText]) { index, providers in
                    SidebarDrag.load(providers) { actions.insert($0, into: .group(group.id), at: index) }
                }
            }
        } label: {
            Label {
                HStack(spacing: metrics.isWebInterface ? metrics.size(8) : metrics.space(.s)) {
                    if metrics.isWebInterface, let icon = group.iconUrl, !icon.isEmpty {
                        SidebarCoverImage(source: icon, side: 16) {
                            Image(systemName: "folder").webProfileSized(16)
                                .foregroundStyle(theme[group.color?.token ?? .fgFaint])
                        }
                        .saturation(group.suspended == true ? 0 : 1)
                        .opacity(group.suspended == true ? 0.6 : 1)
                    }
                    Text(verbatim: group.name)
                        .font(metrics.font(size: 11))
                        .tracking(metrics.size(11) * 0.04)
                        .foregroundStyle(theme[group.suspended == true ? .textQuaternary : .fgFaint])
                        .lineLimit(1)
                        .layoutPriority(1)
                    if group.suspended == true {
                        Image(systemName: metrics.isWebInterface ? "pause" : "pause.circle.fill")
                            .webProfileSized(metrics.isWebInterface ? 10 : 14)
                            .modifier(SidebarSymbolAppearance(size: 10))
                            .foregroundStyle(theme[metrics.isWebInterface ? .fgFaint : .statusDisabled])
                            .help(Text("sidebar.suspended"))
                            .accessibilityLabel(Text("sidebar.suspended"))
                    }
                    Rectangle()
                        .fill(theme[.border])
                        .frame(height: metrics.size(1))
                        .frame(maxWidth: .infinity)
                    Button { environment.editorRequest = .newProject(.group(group.id)) } label: {
                        Label { Text("sidebar.newProjectHere") } icon: { Image(systemName: "plus").webProfileSized(14) }
                            .modifier(SidebarSymbolAppearance(size: 14))
                    }
                    .buttonStyle(AletheIconButtonStyle(side: metrics.isWebInterface ? 18 : 20))
                    .help(Text("sidebar.newProjectHere"))
                    .opacity(hovering ? 1 : 0)
                }
            } icon: {
                if metrics.isWebInterface {
                    EmptyView()
                } else if let color = group.color {
                    AletheMonogram(name: group.name, color: theme[color.token], side: 14)
                } else {
                    Image(systemName: "folder").webProfileSized(14)
                        .foregroundStyle(theme[.fgFaint])
                }
            }
            .modifier(SidebarLabelAppearance(isGroup: true))
            .modifier(SidebarWebGroupOpen {
                actions.openGroup(group.id, adding: false, web: metrics.isWebInterface)
                environment.showingHome = false
            })
            .modifier(SidebarWebRow(kind: .group,
                first: doc.childGroups(of: metrics.style == .clean ? group.parentID : nil).first?.id == group.id))
            .modifier(SidebarGroupRowDrop(target: group.id, actions: actions, targeted: $dropTarget))
            .modifier(SidebarWebDragSource(payload: SidebarDrag.payload(group.id), name: group.name))
            .onHover { hovering = $0 }
            .webContextMenu {
                SidebarMenuButton("sidebar.openOnlyGroup", symbol: "rectangle") {
                    actions.openGroup(group.id, adding: false, web: metrics.isWebInterface)
                    if metrics.isWebInterface { environment.showingHome = false }
                }
                    .disabled(!metrics.isWebInterface && !doc.groups.contains { doc.isGroup($0.id,
                        inside: group.id) && !$0.projectIDs.isEmpty })
                SidebarMenuButton("sidebar.addGroupToTab", symbol: "rectangle.badge.plus") {
                    actions.openGroup(group.id, adding: true, web: metrics.isWebInterface)
                    if metrics.isWebInterface { environment.showingHome = false }
                }
                    .disabled(!metrics.isWebInterface && !doc.groups.contains { doc.isGroup($0.id,
                        inside: group.id) && !$0.projectIDs.isEmpty })
                WebMenuDivider()
                if metrics.isWebInterface {
                    SidebarMenuButton("sidebar.designLayout", symbol: "rectangle.split.2x2") {
                        environment.editorRequest = .layoutDesigner(.group(group.id))
                    }
                    SidebarMenuButton("sidebar.web.archiveGroup", symbol: "archivebox") {
                        archivedGroups = SidebarProjectVisibility.setting(archivedGroups,
                            project: ProjectID(rawValue: group.id.rawValue), profile: environment.profileID, enabled: true)
                    }
                    SidebarMenuButton(group.isCollapsed ? "sidebar.web.expandGroup" : "sidebar.web.collapseGroup", symbol: "chevron.down") {
                        actions.setCollapsed(group.id, !group.isCollapsed)
                    }
                    SidebarMenuButton("sidebar.rename", symbol: "pencil") {
                        SidebarRenamePrompt.name(initial: group.name,
                            width: metrics.size(280), height: metrics.size(24)) { name in
                            actions.workspace.update { $0.updateGroup(group.id) { $0.name = name } }
                        }
                    }
                    if group.parentID != nil {
                        SidebarMenuButton("sidebar.web.makeRoot", symbol: "arrow.up") {
                            actions.workspace.update { $0.moveGroup(group.id, toParent: nil, at: Int.max) }
                        }
                    } else {
                        WebSubmenu("sidebar.web.moveGroup") {
                            ForEach(doc.groups.filter { !doc.isGroup($0.id, inside: group.id) }) { parent in
                                Button { actions.workspace.update { $0.moveGroup(group.id, toParent: parent.id, at: Int.max) } }
                                    label: { Text(verbatim: parent.name) }
                            }
                        }
                    }
                }
                SidebarMenuButton("sidebar.editGroup", symbol: "pencil") { environment.editorRequest = .editGroup(group.id) }
                SidebarMenuButton("sidebar.newProjectHere", symbol: "plus") { environment.editorRequest = .newProject(.group(group.id)) }
                SidebarMenuButton("sidebar.newSubgroup", symbol: "folder.badge.plus") {
                    environment.editorRequest = .newGroup(parent: group.id) }
                WebMenuDivider()
                if group.suspended == true {
                    SidebarMenuButton("sidebar.resumeGroup", symbol: "play") { actions.resumeGroup(group.id) }
                } else {
                    SidebarMenuButton("sidebar.suspendGroupEllipsis", symbol: "pause") { actions.suspendGroup(group) }
                }
                WebMenuDivider()
                if metrics.isWebInterface {
                    SidebarMenuButton("sidebar.designLayout", symbol: "rectangle.split.2x2") {
                        environment.editorRequest = .layoutDesigner(.group(group.id))
                    }
                    SidebarMenuButton("sidebar.web.archiveGroup", symbol: "archivebox") {
                        archivedGroups = SidebarProjectVisibility.settingGroup(archivedGroups, group: group.id,
                            profile: environment.profileID, enabled: true)
                    }
                }
                SidebarMenuButton("sidebar.deleteGroup", symbol: "trash") { actions.deleteGroup(group.id) }
                SidebarMenuButton("sidebar.deleteGroupAndProjects", symbol: "trash", role: .destructive) {
                    actions.deleteGroupAndProjects(group) }
            }
            .accessibilityIdentifier("sidebar.group.\(group.name)")
        }
        .modifier(SidebarWebGroupRegion(group: group.id))
        .modifier(SidebarNativeDragSource(payload: SidebarDrag.payload(group.id)))
    }
}
