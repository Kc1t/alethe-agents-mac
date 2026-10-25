import AletheDesign
import AletheModel
import SwiftUI

struct WorkspaceTabBar: View {
    let workspace: WorkspaceModel
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var hovered: WorkspaceTabID?
    @State private var closeHovered: WorkspaceTabID?
    @State private var dragging: WorkspaceTabID?

    private var document: WorkspaceDocument { workspace.document }

    var body: some View {
        HStack(spacing: metrics.space(.xs)) {
            if metrics.isWebInterface {
                HStack(spacing: metrics.size(2)) { historyButtons }
            } else {
                historyButtons
            }
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: metrics.space(.xs)) {
                        ForEach(document.workspace.tabs) { tab in
                            tabView(tab).id(tab.id)
                        }
                    }
                }
                .onChange(of: document.workspace.activeTabID) { _, id in
                    guard metrics.isWebInterface, let id else { return }
                    withAnimation(Motion.WorkspaceEffect.tab.animation(reduceMotion: metrics.reducesMotion)) {
                        proxy.scrollTo(id)
                    }
                }
            }
        }
        .padding(.horizontal, metrics.size(metrics.isWebInterface ? 8 : 6))
        .frame(height: metrics.size(32))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme[.bgElevated])
        .overlay(alignment: .bottom) { if !metrics.isWebInterface { theme[.border].frame(height: metrics.size(1)) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspaceTabs")
    }

    @ViewBuilder
    private var historyButtons: some View {
        navigationButton("arrow.left", label: "menu.view.back", id: "workspaceTabs.back",
                         enabled: document.canGoBack) { navigate(-1) }
        navigationButton("arrow.right", label: "menu.view.forward", id: "workspaceTabs.forward",
                         enabled: document.canGoForward) { navigate(1) }
    }

    private func coverSource(_ tab: WorkspaceTab) -> String? {
        if let id = tab.webGroupID { return document.group(id)?.iconUrl }
        if tab.kind == .project, let id = tab.projectID { return document.project(id)?.iconUrl }
        return nil
    }

    private func tabView(_ tab: WorkspaceTab) -> some View {
        let isActive = tab.id == document.workspace.activeTabID
        let isHovered = hovered == tab.id
        let label = document.label(of: tab)
        let name = label?.name ?? String(localized: "workspaceTabs.empty")
        let radius = metrics.radius(.sm)
        return tabContents(tab, name: name, more: label?.more, isActive: isActive, isHovered: isHovered)
        .padding(.leading, metrics.size(8))
        .padding(.trailing, metrics.size(4))
        .frame(minWidth: metrics.size(96), maxWidth: metrics.size(190))
        .frame(height: metrics.size(26))
        .background(
            RoundedRectangle(cornerRadius: radius)
                .fill(isActive ? theme[metrics.isWebInterface && metrics.style == .clean ? .panelHover
                    : .bgSunken] : theme[.panelHover].opacity(isHovered ? 1 : 0))
                .shadow(color: isActive && (!metrics.isWebInterface || metrics.style != .clean) ? theme.shadow(.sm).color.color : .clear,
                        radius: metrics.size(4), y: metrics.size(2))
        )
        .overlay {
            if (isActive || (metrics.isWebInterface && tab.pinned)) && (!metrics.isWebInterface
                || metrics.style != .clean) {
                RoundedRectangle(cornerRadius: radius).strokeBorder(theme[.borderStrong],
                lineWidth: metrics.isWebInterface ? metrics.size(1) : 1) }
        }
        .offset(y: (isActive || isHovered) && metrics.style == .normal ? -metrics.size(1) : 0)
        .animation(metrics.isWebInterface
            ? Motion.WorkspaceEffect.tab.animation(reduceMotion: metrics.reducesMotion) : nil, value: isHovered)
        .animation(metrics.isWebInterface
            ? Motion.WorkspaceEffect.tab.animation(reduceMotion: metrics.reducesMotion) : nil, value: isActive)
        .opacity(dragging == tab.id ? 0.5 : 1)
        .contentShape(Rectangle())
        .onHover { hovered = $0 ? tab.id : (hovered == tab.id ? nil : hovered) }
        .onTapGesture {
            workspace.update { $0.activateWorkspaceTab(tab.id) }
            if metrics.isWebInterface { environment.showingHome = false }
        }
        .background {
            if metrics.isWebInterface {
                WorkspaceTabEvents(
                    activate: {
                        workspace.update { $0.activateWorkspaceTab(tab.id) }
                        environment.showingHome = false
                    }, close: { workspace.update { $0.closeWorkspaceTab(tab.id) } })
            }
        }
        .onDrag {
            dragging = tab.id
            return NSItemProvider(object: tab.id.rawValue as NSString)
        }
        .onDrop(of: [.text], delegate: TabDropDelegate(target: tab.id, dragging: $dragging, workspace: workspace))
        .webContextMenu {
            tabMenu(tab)
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : .isButton)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityIdentifier("workspaceTabs.tab.\(name)")
    }

    private func navigate(_ direction: Int) {
        workspace.update { $0.navigateHistory(direction) }
        if metrics.isWebInterface { environment.showingHome = false }
    }

    private func navigationButton(_ symbol: String, label: LocalizedStringKey, id: String, enabled: Bool,
                                  action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
        }
        .buttonStyle(AletheIconButtonStyle(side: 24))
        .disabled(!enabled)
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }
    private func closeButton(_ tab: WorkspaceTab, name: String, isActive: Bool, isHovered: Bool) -> some View {
        Image(systemName: "xmark")
            .font(metrics.font(size: metrics.isWebInterface ? 11 : 8, weight: .bold))
            .frame(width: metrics.size(metrics.isWebInterface && !isActive && !isHovered ? 0 : 18), height: metrics.size(18))
            .background(theme[metrics.isWebInterface ? .bgSunken : .panelHover].opacity(closeHovered == tab.id ? 1 : 0), in: Circle())
            .contentShape(Circle())
            .onHover { closeHovered = $0 ? tab.id : (closeHovered == tab.id ? nil : closeHovered) }
            .onTapGesture { workspace.update { $0.closeWorkspaceTab(tab.id) } }
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { workspace.update { $0.closeWorkspaceTab(tab.id) } }
        .foregroundStyle(theme[closeHovered == tab.id ? .fg : .fgFaint])
        .opacity(isActive || isHovered ? 1 : 0)
        .animation(metrics.isWebInterface
            ? Motion.WorkspaceEffect.close.animation(reduceMotion: metrics.reducesMotion) : nil, value: isHovered)
        .help(Text("workspaceTabs.close"))
        .accessibilityLabel(Text("workspaceTabs.close"))
        .accessibilityIdentifier("workspaceTabs.close.\(name)")
    }

    private func tabContents(_ tab: WorkspaceTab, name: String, more: Int?, isActive: Bool, isHovered: Bool) -> some View {
        return HStack(spacing: metrics.isWebInterface ? metrics.size(2) : metrics.space(.s)) {
            if tab.pinned {
                Image(systemName: "pin.fill")
                    .font(metrics.font(size: metrics.isWebInterface ? 11 : 9))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(theme[.accent])
            }
            if metrics.isWebInterface, let icon = coverSource(tab), !icon.isEmpty {
                SidebarCoverImage(source: icon, side: 14, cornerRadius: 3) {
                    Circle().fill(document.color(of: tab).map { theme[$0.token] } ?? theme[.fgFaint])
                        .frame(width: metrics.size(8), height: metrics.size(8))
                }
            } else if metrics.isWebInterface, tab.kind == .composition, tab.webGroupID == nil, tab.webPaneID == nil {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(metrics.font(size: 14))
                    .foregroundStyle(theme[.accent])
                    .fixedSize()
            } else {
                Circle()
                    .fill(document.color(of: tab).map { theme[$0.token] } ?? theme[.fgFaint])
                    .frame(width: metrics.size(8), height: metrics.size(8))
                    .padding(.trailing, metrics.isWebInterface ? metrics.size(5) : 0)
            }
            Text(verbatim: name)
                .font(metrics.font(size: 11, weight: .semibold))
                .foregroundStyle(theme[isActive || isHovered ? .fg : .fgMuted])
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if metrics.isWebInterface {
                Text(verbatim: String(tab.snapshot.openProjectIDs.reduce(0) { total, id in
                    total + (tab.webPaneID == nil ? (document.projects.first(where: { $0.id == id })?.visiblePanes.count ?? 0) : 1)
                }))
                    .font(metrics.font(size: 9, weight: metrics.style == .clean ? .medium : .bold))
                    .foregroundStyle(theme[.fgFaint])
                    .padding(.horizontal, metrics.size(5))
                    .frame(minWidth: metrics.size(18), minHeight: metrics.size(14))
                    .background(theme[.panel].opacity(metrics.style == .clean ? 0 : 1), in: Capsule())
            } else if let more, more > 0 {
                AletheCountPill(more)
            }
            closeButton(tab, name: name, isActive: isActive, isHovered: isHovered)
        }
    }

    @ViewBuilder
    private func tabMenu(_ tab: WorkspaceTab) -> some View {
        if metrics.isWebInterface {
            Button("workspaceTabs.openIndividually") {
                workspace.update { $0.activateWorkspaceTab(tab.id) }
                environment.showingHome = false
            }
            Button("workspaceTabs.addToCurrent") {
                workspace.update { document in
                    for project in tab.snapshot.openProjectIDs { document.open(project) }
                }
                environment.showingHome = false
            }
            WebMenuDivider()
            Button { workspace.update { $0.togglePinned(tab.id) } } label: {
                Label(tab.pinned ? LocalizedStringKey("workspaceTabs.unpin") : "workspaceTabs.pin",
                      systemImage: tab.pinned ? "pin.slash" : "pin")
            }
            WebMenuDivider()
            Button { workspace.update { $0.closeWorkspaceTab(tab.id) } } label: {
                Label("workspaceTabs.close", systemImage: "xmark")
            }
        } else {
            Button(tab.pinned ? LocalizedStringKey("workspaceTabs.unpin") : "workspaceTabs.pin") {
                workspace.update { $0.togglePinned(tab.id) }
            }
            WebMenuDivider()
            Button("workspaceTabs.close") { workspace.update { $0.closeWorkspaceTab(tab.id) } }
        }
    }
}

private struct TabDropDelegate: DropDelegate {
    let target: WorkspaceTabID
    @Binding var dragging: WorkspaceTabID?
    let workspace: WorkspaceModel

    func dropEntered(info: DropInfo) {
        MainActor.assumeIsolated {
            guard let dragging, dragging != target,
                  let index = workspace.document.workspace.tabs.firstIndex(where: { $0.id == target }) else { return }
            workspace.update { $0.moveWorkspaceTab(dragging, to: index) }
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        return true
    }
}
