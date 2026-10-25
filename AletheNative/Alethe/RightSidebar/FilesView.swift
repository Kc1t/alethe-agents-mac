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

struct FilesView: View {
    @Environment(AppEnvironment.self) var environment
    @Environment(\.metrics) var metrics

    static let tabID = "files"
    static let tab = SidebarTabContribution(id: tabID, title: "Files", symbol: "folder", side: .right, viewID: tabID)

    var project: Project? {
        environment.workspace.flatMap { model in
            model.document.workspace.selectedProjectID.flatMap(model.document.project)
        }
    }

    var body: some View {
        if let project {
            FileTreeList(project: project).id(project.folder)
        } else if metrics.isWebInterface {
            WebSidebarEmpty(title: "docs.noProject", symbol: "folder")
        } else {
            ContentUnavailableView("docs.noProject", systemImage: "folder")
        }
    }
}

struct FileTreeList: View {
    let project: Project
    @Environment(AppEnvironment.self) var environment
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics
    @State var rootExpanded = true
    @State var hoveredFile: URL?
    @State var tree: FileTree
    @State var renaming: URL?
    @State var draftName = ""
    @State private var pendingDelete: URL?
    @State private var errorMessage: String? { didSet { if errorMessage != oldValue { AppLog.shown(errorMessage, .app) } } }
    @State var previewURL: URL?
    @State var selection: URL?
    @FocusState var renameFocused: Bool

    init(project: Project) {
        self.project = project
        _tree = State(initialValue: FileTree(root: URL(filePath: project.folder, directoryHint: .isDirectory)))
    }

    var body: some View {
        Group {
            if metrics.isWebInterface { webTree } else {
        List(selection: $selection) {
            ForEach(tree.visibleRows()) { row in
                rowView(row)
                    .tag(row.node.url)
                    .contextMenu { menu(for: row.node) }
            }
        }
        .listStyle(.sidebar)
        .contextMenu { createMenu(in: tree.root) }
        .onKeyPress(.space) {
            guard renaming == nil, let selection else { return .ignored }
            preview(selection)
            return .handled
        }
        .overlay {
            if tree.rootNodes.isEmpty { ContentUnavailableView("files.empty", systemImage: "folder") }
        }
            }
        }
        .gitWebSheet(isPresented: Binding(get: { previewURL != nil }, set: { if !$0 { previewURL = nil } }), width: 760) {
            if let url = previewURL {
                SidebarFilePreview(url: url, close: { previewURL = nil }, add: {
                    if let node = tree.visibleRows().first(where: { $0.node.url == url })?.node { open(node) }
                    previewURL = nil
                }, markdown: { openMarkdown(url); previewURL = nil })
            }
        }
        .task { await follow() }
        .confirmationDialog("files.deletePermanently.title", isPresented: deleteBinding, presenting: pendingDelete) { url in
            Button("files.deletePermanently", role: .destructive) { deletePermanently(url) }
        } message: { url in
            Text(verbatim: String(format: String(localized: "files.deletePermanently.message"), url.lastPathComponent))
        }
        .alert("files.error", isPresented: errorBinding) {
            Button("files.ok") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func rowView(_ row: FileTreeRow) -> some View {
        let node = row.node
        HStack(spacing: 4) {
            Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(theme[.textTertiary])
                .opacity(node.isDirectory ? 1 : 0)
                .frame(width: 10)
            Image(systemName: node.isDirectory && row.isExpanded ? FileIcons.openFolderSymbol : node.iconName)
                .foregroundStyle(node.isDirectory ? theme[.accent] : theme[.textSecondary])
                .frame(width: 16)
            if renaming == node.url {
                TextField("files.name", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($renameFocused)
                    .onSubmit { commitRename(node.url) }
                    .onExitCommand { renaming = nil }
                    .onAppear { renameFocused = true }
            } else {
                Text(node.name)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(badgeColor(tree.badge(for: node)) ?? theme[.textPrimary])
            }
            Spacer(minLength: 4)
            if let badge = tree.badge(for: node) {
                Text(badge.letter)
                    .font(.caption.monospaced().weight(.semibold))
                    .foregroundStyle(badgeColor(badge) ?? theme[.textSecondary])
            }
        }
        .padding(.leading, CGFloat(row.depth) * 12)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = node.url
            activate(node)
        }
        .help(node.url.path)
    }

    private func badgeColor(_ badge: GitBadge?) -> Color? {
        if ({ if case .conflict? = badge { return true }; return false }()) ||
            ({ if case .deleted? = badge { return true }; return false }()) {
            theme[.statusStopped]
        } else if ({ if case .modified? = badge { return true }; return false }()) ||
            ({ if case .stagedModified? = badge { return true }; return false }()) ||
            ({ if case .renamed? = badge { return true }; return false }()) {
            theme[.statusWaiting]
        } else if ({ if case .added? = badge { return true }; return false }()) ||
            ({ if case .untracked? = badge { return true }; return false }()) {
            theme[.statusActive]
        } else {
            nil
        }
    }

    @ViewBuilder
    private func menu(for node: FileNode) -> some View {
        if !node.isDirectory {
            Button("files.open") { open(node) }
            Button("files.openWithDefaultApp") { NSWorkspace.shared.open(node.url) }
        }
        Button("files.quickLook") { preview(node.url) }
        Button("files.revealInFinder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
        Divider()
        Button("files.rename") {
            draftName = node.name
            renaming = node.url
        }
        createMenu(in: node.isDirectory ? node.url : node.url.deletingLastPathComponent())
        Divider()
        Button("files.moveToTrash", role: .destructive) { trash(node.url) }
    }

    @ViewBuilder
    private func createMenu(in directory: URL) -> some View {
        Button("files.newFile") { create(in: directory, folder: false) }
        Button("files.newFolder") { create(in: directory, folder: true) }
    }

    func activate(_ node: FileNode) {
        if node.isDirectory {
            attempt { try tree.toggle(node.url) }
        } else {
            open(node)
        }
    }

    func open(_ node: FileNode) {
        let path = node.url.path
        let content: PaneContent? = if case .markdown? = node.paneKind {
            .markdown(path: path)
        } else if case .image? = node.paneKind {
            .image(path: path)
        } else if case .video? = node.paneKind {
            .video(path: path)
        } else if case .web? = node.paneKind {
            environment.features.isOn(.browser) ? .web(url: node.url.absoluteString, options: WebPaneOptions()) : nil
        } else {
            nil
        }
        if let content {
            environment.open(content, in: project.id)
        } else {
            NSWorkspace.shared.open(node.url)
        }
    }

    func commitRename(_ url: URL) {
        renaming = nil
        attempt {
            try FileOperations.rename(url, to: draftName)
            try tree.reload()
        }
    }

    private func create(in directory: URL, folder: Bool) {
        let base = String(localized: folder ? "files.untitledFolder" : "files.untitledFile")
        var name = base
        var index = 2
        while FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path) {
            name = "\(base) \(index)"
            index += 1
        }
        attempt {
            let created = folder
                ? try FileOperations.createFolder(named: name, in: directory)
                : try FileOperations.createFile(named: name, in: directory)
            if directory.standardizedFileURL != tree.root { try tree.expand(directory) }
            try tree.reload()
            draftName = name
            renaming = created.standardizedFileURL
        }
    }

    func trash(_ url: URL) {
        attempt {
            if try FileOperations.moveToTrash(url) == .trashUnavailable {
                pendingDelete = url
            }
            try tree.reload()
        }
    }

    private func deletePermanently(_ url: URL) {
        pendingDelete = nil
        attempt {
            try FileOperations.deletePermanently(url)
            try tree.reload()
        }
    }

    func attempt(_ work: () throws -> Void) {
        do {
            try work()
        } catch let error as FileOperationError {
            errorMessage = if case .invalidName = error {
                String(localized: "files.error.invalidName")
            } else if case .alreadyExists = error {
                String(localized: "files.error.alreadyExists")
            } else if case .notFound = error {
                String(localized: "files.error.notFound")
            } else if case .rootNotModifiable = error {
                String(localized: "files.error.root")
            } else if case .failed(let message) = error {
                message
            } else {
                preconditionFailure("Unexpected value")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func follow() async {
        try? tree.reload()
        let repository: GitRepository? = if let root = try? await GitRepository.discover(tree.root) {
            GitRepositories.shared.repository(at: root)
        } else {
            nil
        }
        await refreshBadges(repository)
        let gitWatcher = repository.flatMap { Self.gitDirectoryWatcher(repoRoot: $0.root, tree: tree.root) }
        gitWatcher?.start()
        let gitRefresh = gitWatcher.map { watcher in
            Task { @MainActor in
                for await _ in watcher.events { await refreshBadges(repository) }
            }
        }
        let watcher = FileTreeWatcher(root: tree.root)
        watcher.start()
        defer {
            watcher.stop()
            gitWatcher?.stop()
            gitRefresh?.cancel()
        }
        for await _ in watcher.events {
            try? tree.reload()
            await refreshBadges(repository)
        }
    }

    private static func gitDirectoryWatcher(repoRoot: URL, tree: URL) -> GitWatcher? {
        let root = repoRoot.standardizedFileURL.resolvingSymlinksInPath()
        let folder = tree.standardizedFileURL.resolvingSymlinksInPath()
        guard root.path != folder.path else { return nil }
        var gitDirectory = root.appending(path: ".git", directoryHint: .isDirectory)
        if let text = try? String(contentsOf: root.appending(path: ".git"), encoding: .utf8), text.hasPrefix("gitdir:") {
            let path = text.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
            gitDirectory = URL(filePath: path, directoryHint: .isDirectory, relativeTo: root).standardizedFileURL
        }
        return GitWatcher(root: gitDirectory)
    }

    private func refreshBadges(_ repository: GitRepository?) async {
        guard let repository, let status = try? await repository.status() else {
            tree.gitBadges = nil
            return
        }
        tree.gitBadges = GitBadgeIndex(status: status, repoRoot: repository.root)
    }

    private var deleteBinding: Binding<Bool> {
        Binding { pendingDelete != nil } set: { if !$0 { pendingDelete = nil } }
    }

    private var errorBinding: Binding<Bool> {
        Binding { errorMessage != nil } set: { if !$0 { errorMessage = nil } }
    }
}
