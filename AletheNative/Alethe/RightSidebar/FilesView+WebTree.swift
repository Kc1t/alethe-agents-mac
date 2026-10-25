import AletheDesign
import AletheFiles
import AletheFoundation
import AletheGit
import AletheModel
import AlethePluginKit
import AppKit
import AVKit
import PDFKit
import Quartz
import SwiftUI

extension FileTreeList {
    var webTree: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                HStack(spacing: metrics.size(5)) {
                    Text(verbatim: project.name).font(metrics.font(size: 11, weight: 650)).lineLimit(1)
                    Text(verbatim: project.folder).font(metrics.font(size: 10)).foregroundStyle(theme[.fgFaint])
                        .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Button { NSWorkspace.shared.activateFileViewerSelecting([tree.root]) } label: {
                        Label("files.revealInFinder", systemImage: "folder.badge.magnifyingglass").font(metrics.font(size: 13))
                    }.help(Text("files.revealInFinder"))
                    Button { attempt { try tree.reload() } } label: {
                        Label("rightSidebar.files.refresh", systemImage: "arrow.clockwise").font(metrics.font(size: 13))
                    }.help(Text("rightSidebar.files.refresh"))
                }
                .buttonStyle(AletheAnimatedRightSidebarTabStyle(width: 24, height: 24))
                .padding(.leading, metrics.size(12)).padding(.trailing, metrics.size(8)).frame(height: metrics.size(38))
                .overlay(alignment: .bottom) { Rectangle().fill(theme[.border]).frame(height: metrics.size(1)) }
                .help(project.folder)
                Button { rootExpanded.toggle() } label: {
                    HStack(spacing: metrics.size(6)) {
                        Image(systemName: rootExpanded ? "chevron.down" : "chevron.right").resizable().scaledToFit()
                            .frame(width: metrics.size(13), height: metrics.size(13)).foregroundStyle(theme[.fgFaint])
                        Image(systemName: "folder").resizable().scaledToFit()
                            .frame(width: metrics.size(14), height: metrics.size(14)).foregroundStyle(theme[.fgMuted])
                        Text(verbatim: tree.root.lastPathComponent.uppercased()).font(metrics.font(size: 11, weight: .bold)).lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, metrics.size(8)).padding(.trailing, metrics.size(8)).frame(height: metrics.size(28))
                    .contentShape(Rectangle())
                }.buttonStyle(.plain).modifier(WebFileHover())
                if rootExpanded {
                    ForEach(tree.visibleRows()) { row in
                        webRow(row).contextMenu { webMenu(for: row.node) }
                    }
                    if tree.rootNodes.isEmpty {
                        Text("files.empty").font(metrics.font(size: 11)).foregroundStyle(theme[.fgFaint])
                            .padding(.leading, metrics.size(36)).padding(.trailing, metrics.size(12)).padding(.vertical, metrics.size(8))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .foregroundStyle(theme[.fg]).background(theme[.bg])
        .focusable()
        .onKeyPress(.upArrow) {
            guard renaming == nil else { return .ignored }
            moveSelection(-1); return .handled
        }
        .onKeyPress(.downArrow) {
            guard renaming == nil else { return .ignored }
            moveSelection(1); return .handled
        }
        .onKeyPress(.rightArrow) { setExpanded(true) }
        .onKeyPress(.leftArrow) { setExpanded(false) }
        .onKeyPress(.return) {
            guard renaming == nil, let node = tree.visibleRows().first(where: { $0.node.url == selection })?.node else { return .ignored }
            activate(node); return .handled
        }
        .onKeyPress(.space) {
            guard renaming == nil, let selection else { return .ignored }
            preview(selection); return .handled
        }
    }

    private func setExpanded(_ expanded: Bool) -> KeyPress.Result {
        guard renaming == nil, let row = tree.visibleRows().first(where: { $0.node.url == selection }),
              row.node.isDirectory else { return .ignored }
        if row.isExpanded != expanded { attempt { try tree.toggle(row.node.url) } }
        return .handled
    }

    private func moveSelection(_ offset: Int) {
        guard renaming == nil else { return }
        let rows = tree.visibleRows()
        guard !rows.isEmpty else { return }
        let index = rows.firstIndex { $0.node.url == selection } ?? (offset > 0 ? -1 : rows.count)
        selection = rows[min(max(0, index + offset), rows.count - 1)].node.url
    }

    private func webRow(_ row: FileTreeRow) -> some View {
        let node = row.node
        return HStack(spacing: metrics.size(6)) {
            if node.isDirectory {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right").resizable().scaledToFit()
                    .frame(width: metrics.size(13), height: metrics.size(13)).foregroundStyle(theme[.fgFaint])
            }
            Image(systemName: node.iconName).resizable().scaledToFit()
                .frame(width: metrics.size(node.isDirectory ? 14 : 13), height: metrics.size(node.isDirectory ? 14 : 13))
                .foregroundStyle(theme[.fgMuted])
            if renaming == node.url {
                TextField("files.name", text: $draftName).textFieldStyle(.plain).focused($renameFocused)
                    .onSubmit { commitRename(node.url) }.onExitCommand { renaming = nil }.onAppear { renameFocused = true }
            } else {
                Text(verbatim: node.name).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(webBadgeColor(tree.badge(for: node)) ?? theme[.fgMuted])
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !node.isDirectory && hoveredFile == node.url {
                HStack(spacing: metrics.size(2)) {
                    Button { open(node) } label: {
                        Label("rightSidebar.files.addToGrid", systemImage: "square.grid.2x2").font(metrics.font(size: 12))
                    }.help(Text("rightSidebar.files.addToGrid"))
                    Button { preview(node.url) } label: {
                        Label("rightSidebar.files.preview", systemImage: "eye").font(metrics.font(size: 12))
                    }.help(Text("rightSidebar.files.preview"))
                    if ["md", "markdown"].contains(node.url.pathExtension.lowercased()) {
                        Button { openMarkdown(node.url) } label: {
                            Label("rightSidebar.files.openMarkdown", systemImage: "sidebar.right").font(metrics.font(size: 12))
                        }.help(Text("rightSidebar.files.openMarkdown"))
                    }
                }.buttonStyle(AletheAnimatedRightSidebarTabStyle(width: 20, height: 20))
            }
            if let badge = tree.badge(for: node) {
                if node.isDirectory {
                    Circle().fill(webBadgeColor(badge) ?? theme[.fgMuted]).frame(width: metrics.size(6), height: metrics.size(6))
                        .padding(.trailing, metrics.size(4))
                } else {
                    Text(verbatim: badge.letter).font(metrics.monoFont(size: 11, weight: .bold))
                        .foregroundStyle(webBadgeColor(badge) ?? theme[.fgMuted]).frame(width: metrics.size(16))
                }
            }
        }
        .font(metrics.font(size: 12))
        .padding(.leading, metrics.size(22 + CGFloat(row.depth) * 14))
        .padding(.trailing, metrics.size(8)).frame(height: metrics.size(24))
        .contentShape(Rectangle()).modifier(WebFileHover())
        .overlay { Rectangle().strokeBorder(theme[.accent].opacity(selection == node.url ? 1 : 0), lineWidth: metrics.size(1)) }
        .onTapGesture(count: 2) { if !node.isDirectory { open(node) } }
        .onTapGesture {
            selection = node.url
            if node.isDirectory { attempt { try tree.toggle(node.url) } }
            else { preview(node.url) }
        }
        .modifier(WebFileDrag(url: node.url, enabled: !node.isDirectory))
        .onHover { hoveredFile = $0 ? node.url : hoveredFile == node.url ? nil : hoveredFile }
        .help(node.url.path)
    }

    func preview(_ url: URL) {
        if metrics.isWebInterface { previewURL = url }
        else { QuickLook.shared.show(url) }
    }

    func openMarkdown(_ url: URL) {
        NotificationCenter.default.post(name: .sidebarOpenMarkdown, object: url)
        environment.rightSidebarTab = DocsView.tabID
        environment.rightSidebarVisible = true
    }

    private func webBadgeColor(_ badge: GitBadge?) -> Color? {
        if ({ if case .conflict? = badge { return true }; return false }()) ||
            ({ if case .deleted? = badge { return true }; return false }()) {
            theme[.statusOffline]
        } else if ({ if case .modified? = badge { return true }; return false }()) ||
            ({ if case .stagedModified? = badge { return true }; return false }()) {
            theme[.statusWaiting]
        } else if case .renamed? = badge {
            theme[.agentCodex]
        } else if ({ if case .added? = badge { return true }; return false }()) ||
            ({ if case .untracked? = badge { return true }; return false }()) {
            theme[.statusWorking]
        } else {
            nil
        }
    }

    @ViewBuilder private func webMenu(for node: FileNode) -> some View {
        if !node.isDirectory {
            Button { open(node) } label: { Label("rightSidebar.files.addToGrid", systemImage: "square.grid.2x2") }
            Button { preview(node.url) } label: { Label("rightSidebar.files.preview", systemImage: "eye") }
            if ["md", "markdown"].contains(node.url.pathExtension.lowercased()) {
                Button {
                    openMarkdown(node.url)
                } label: { Label("rightSidebar.files.openMarkdown", systemImage: "sidebar.right") }
            }
        }
        Button { NSWorkspace.shared.activateFileViewerSelecting([node.url]) } label: {
            Label("files.revealInFinder", systemImage: "folder.badge.magnifyingglass")
        }
        Button { draftName = node.name; renaming = node.url } label: { Label("files.rename", systemImage: "pencil") }
        Button(role: .destructive) { trash(node.url) } label: { Label("files.moveToTrash", systemImage: "trash") }
    }

}
