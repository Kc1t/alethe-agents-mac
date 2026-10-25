import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct SidebarFileRow: View {
    let pane: Pane
    let project: Project
    let actions: SidebarActions
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @State private var hovering = false

    private var path: String { pane.content.filePath ?? "" }

    private var symbol: String {
        if case .orchestrator = pane.content {
            return "rectangle.3.group"
        } else if case .graphify = pane.content {
            return "point.3.connected.trianglepath.dotted"
        } else if case .web = pane.content {
            return "globe"
        } else if case .diff = pane.content {
            return "plusminus"
        } else if case .image = pane.content {
            return "photo"
        } else if case .video = pane.content {
            return "film"
        } else {
            return "doc.text"
        }
    }

    private var title: Text {
        if case .orchestrator = pane.content {
            return Text("orchestrator.title")
        } else if case .graphify = pane.content {
            return Text("graphify.title")
        } else if case .web(let url, _) = pane.content {
            return Text(verbatim: URL(string: url)?.host ?? url)
        } else if case .diff(let diffPath, _) = pane.content {
            return Text(verbatim: diffPath.map { URL(filePath: $0).lastPathComponent } ?? "Diff")
        } else {
            return Text(verbatim: URL(filePath: path).lastPathComponent)
        }
    }

    var body: some View {
        HStack(spacing: metrics.size(9)) {
            AletheSidebarItemIcon(symbol: symbol)
                .foregroundStyle(theme[.fgMuted])
            title
                .font(metrics.font(size: 12.5))
                .lineLimit(1)
            Spacer(minLength: 0)
            WebMenu {
                if metrics.isWebInterface {
                    SidebarMenuButton("terminalInspector.open", symbol: "info.circle") { environment.inspectedPaneID = pane.id }
                }
                if metrics.isWebInterface, ["md", "markdown"].contains(URL(filePath: path).pathExtension.lowercased()) {
                    SidebarMenuButton("rightSidebar.files.openMarkdown", symbol: "sidebar.right") {
                        NotificationCenter.default.post(name: .sidebarOpenMarkdown, object: URL(filePath: path))
                        environment.rightSidebarTab = DocsView.tabID
                        environment.rightSidebarVisible = true
                    }
                }
                if pane.content.filePath != nil {
                    SidebarMenuButton("sidebar.revealInFinder", symbol: "folder") { OpenInActions.revealInFinder(path) }
                }
                SidebarMenuButton("terminal.close", symbol: "xmark") { actions.workspace.update { $0.closePane(pane.id) } }
            } label: {
                Label { Text("sidebar.rowMenu") } icon: { Image(systemName: "ellipsis").webProfileSized(14) }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .modifier(SidebarMenuAppearance(size: 13))
            .fixedSize()
            .opacity(hovering ? 1 : 0)
            .animation(nil, value: hovering)
            .frame(width: metrics.size(hovering ? 20 : 0))
            .animation(Motion.SidebarEffect.rowSlot.animation(reduceMotion: metrics.reducesMotion), value: hovering)
            .help(Text("sidebar.rowMenu"))
        }
        .foregroundStyle(theme[.fg])
        .contentShape(Rectangle())
        .onTapGesture {
            if metrics.isWebInterface {
                actions.workspace.update {
                    if pane.content == .orchestrator { $0.openWebPane(pane.id) } else { $0.focusWebPane(pane.id) }
                }
                environment.showingHome = false
            } else {
                actions.select(.project(project.id))
                actions.workspace.update {
                    $0.activateGrid(pane.gridID, in: project.id)
                    $0.workspace.focusedPaneID = pane.id
                }
            }
        }
        .modifier(SidebarWebRow(kind: .terminal,
            focused: actions.workspace.document.workspace.focusedPaneID == pane.id, project: project.id))
        .modifier(SidebarWebDragSource(payload: SidebarDrag.payload(pane.id), name: pane.content.filePath ?? project.name))
        .onHover { hovering = $0 }
        .help(Text(verbatim: path))
        .accessibilityIdentifier("sidebar.file.\(pane.id.rawValue)")
    }
}
