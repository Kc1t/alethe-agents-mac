#if DEBUG
import AletheModel
import AppKit
import Foundation

extension TestSeeds {
    static let workspaceFixtures: [String: @Sendable (String, inout WorkspaceDocument) -> Void] = [
        "sidebar": seedSidebarFixture,
        "cliOpen": seedCliOpenFixture,
        "terminals": seedTerminalsFixture,
        "panes": seedPanesFixture,
        "grid": seedGridFixture,
        "subtabs": seedSubtabsFixture,
        "markdown": seedMarkdownFixture,
        "media": seedMediaFixture,
        "diff": seedDiffFixture,
        "git": seedGitFixture,
        "worktrees": seedWorktreesFixture,
        "clone": seedCloneFixture,
        "agentLibrary": seedAgentLibraryFixture,
        "web": seedWebFixture,
        "graphify": seedGraphifyFixture,
        "orchestrator": seedOrchestratorFixture,
        "orchestratorBoard": seedOrchestratorBoardFixture,
        "orchestratorLarge": seedOrchestratorBoardFixture,
        orchestratorWorker: seedOrchestratorWorkerFixture,
        "orchestratorApply": seedOrchestratorApplyFixture,
        "skills": seedSkillsFixture,
        "gsdSync": seedGsdSyncFixture,
        "mcp": seedMcpFixture,
        "multiagent": seedMultiagentFixture,
        "multiagentLive": seedMultiagentFixture,
        "prompt": seedPromptFixture
    ]

    private static func seedSidebarFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let work = doc.addGroup(name: "Work", color: .purple)
        let clients = doc.addGroup(name: "Clients", parent: work)
        doc.addProject(name: "alpha", folder: "/private/tmp", color: .orange, in: .group(work))
        doc.addProject(name: "beta", folder: "/private/tmp", color: .blue, in: .group(work))
        doc.addProject(name: "client-site", folder: "/private/tmp", color: .teal, in: .group(clients))
        doc.addProject(name: "scratch", folder: "/private/tmp", color: .pink)
    }

    private static func seedCliOpenFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        for name in ["api", "web"] {
            let folder = URL(filePath: root).appending(path: name)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            doc.addProject(name: name, folder: folder.path, color: .teal)
        }
    }

    private static func seedTerminalsFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let project = doc.addProject(name: "scratch", folder: "/private/tmp", color: .pink)
        doc.addPane(to: project, tab: PaneTab(agent: "claude"))
    }

    private static func seedPanesFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let api = doc.addProject(name: "api", folder: "/private/tmp", color: .orange)
        let web = doc.addProject(name: "web", folder: "/private/tmp", color: .teal)
        for title in ["one", "two", "three"] { doc.addPane(to: api, tab: PaneTab(agent: "shell", title: title)) }
        doc.addPane(to: web, tab: PaneTab(agent: "shell", title: "four"))
    }

    private static func seedGridFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let api = doc.addProject(name: "api", folder: "/private/tmp", color: .orange)
        let panes = ["one", "two", "three"].compactMap { doc.addPane(to: api, tab: PaneTab(agent: "shell", title: $0)) }
        doc.setGridLayout(.auto(panes.map(\.rawValue)), for: api)
    }

    private static func seedSubtabsFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let project = doc.addProject(name: "scratch", folder: "/private/tmp", color: .pink)
        let pane = doc.addPane(to: project, tab: PaneTab(agent: "shell", title: "one"))
        if let pane { doc.addTab(PaneTab(agent: "shell", title: "two"), to: pane) }
    }

    private static func seedMarkdownFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        let file = URL(filePath: root).appending(path: "README.md")
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        try? Data("# Seeded\n\n- [x] done\n\n| a | b |\n|---|---|\n| 1 | 2 |\n".utf8).write(to: file)
        let project = doc.addProject(name: "docs", folder: root, color: .teal)
        doc.addPane(to: project, content: .markdown(path: file.path))
    }

    private static func seedMediaFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        let file = URL(filePath: root).appending(path: "shot.png")
        try? FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
        if let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 64, pixelsHigh: 64, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                      colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) {
            try? rep.representation(using: .png, properties: [:])?.write(to: file)
        }
        let project = doc.addProject(name: "media", folder: root, color: .orange)
        doc.addPane(to: project, content: .image(path: file.path))
    }

    private static func seedDiffFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let repo = seedRepository()
        let project = doc.addProject(name: "repo", folder: repo.path, color: .green)
        doc.addPane(to: project, content: .diff(path: nil, staged: false))
    }

    private static func seedGitFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let repo = seedRepository()
        try? Data("draft\n".utf8).write(to: repo.appending(path: "draft.txt"))
        _ = doc.addProject(name: "repo", folder: repo.path, color: .green)
    }

    private static func seedWorktreesFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        let repo = URL(filePath: root).appending(path: "wtrepo")
        try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try? Data("seed\n".utf8).write(to: repo.appending(path: "README.md"))
        let worktree = repo.appending(path: ".alethe/worktrees/seed").path
        for arguments in [["init", "-q"], ["add", "."], ["commit", "-q", "-m", "seed"],
                          ["worktree", "add", "-q", "-b", "alethe/agent-seed", worktree, "HEAD"],
                          ["worktree", "lock", "--reason", "seeded", worktree]] {
            let git = Process()
            git.executableURL = URL(filePath: "/usr/bin/git")
            git.arguments = ["-C", repo.path, "-c", "user.name=seed", "-c", "user.email=seed@local",
                             "-c", "commit.gpgsign=false"] + arguments
            try? git.run()
            git.waitUntilExit()
        }
        _ = doc.addProject(name: "wtrepo", folder: repo.path, color: .green)
    }

    private static func seedCloneFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let repo = seedRepository()
        let bare = repo.deletingLastPathComponent().appending(path: "origin.git")
        let git = Process()
        git.executableURL = URL(filePath: "/usr/bin/git")
        git.arguments = ["clone", "-q", "--bare", "--", repo.path, bare.path]
        try? git.run()
        git.waitUntilExit()
        _ = doc.addProject(name: "repo", folder: repo.path, color: .green)
    }

    private static func seedAgentLibraryFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        let folder = URL(filePath: root).appending(path: "agentsproj")
        let agents = folder.appending(path: ".claude/agents")
        try? FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try? Data("---\nname: mine\ndescription: My own agent.\n---\n".utf8).write(to: agents.appending(path: "mine.md"))
        _ = doc.addProject(name: "agentsproj", folder: folder.path, color: .purple)
    }

    private static func seedWebFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let project = doc.addProject(name: "site", folder: "/private/tmp", color: .blue)
        doc.addPane(to: project, content: .web(url: "http://127.0.0.1:9/", options: WebPaneOptions()))
    }

    private static func seedGraphifyFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        let repo = URL(filePath: root).appending(path: "graphrepo")
        let graph = 
            #"{"nodes":[{"id":"alpha","label":"alpha","source_file":"README.md","community":0},{"id":"beta","label"# +
            #"":"beta","community":0},{"id":"delta","label":"delta","community":1},{"id":"epsilon","label":"epsilo"# +
            #"n","community":1}],"edges":[{"source":"alpha","target":"beta"},{"source":"beta","target":"delta"},{""# +
            #"source":"delta","target":"epsilon"}]}"#
        let older = #"{"nodes":[{"id":"alpha"},{"id":"beta"}],"edges":[{"source":"alpha","target":"beta"}]}"#
        for folder in [".git", "graphify-out", ".alethe/graph-snapshots"] {
            try? FileManager.default.createDirectory(at: repo.appending(path: folder), withIntermediateDirectories: true)
        }
        try? Data("# Graph\n".utf8).write(to: repo.appending(path: "README.md"))
        try? Data(graph.utf8).write(to: repo.appending(path: "graphify-out/graph.json"))
        try? Data(older.utf8).write(to: repo.appending(path: ".alethe/graph-snapshots/1750000000000.json"))
        _ = doc.addProject(name: "graphrepo", folder: repo.path, color: .purple)
    }

    private static func seedOrchestratorFixture(_ name: String, into doc: inout WorkspaceDocument) {
        doc.addProject(name: "scratch", folder: "/private/tmp", color: .pink)
    }

    private static func seedOrchestratorBoardFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let folder = seedOrchestratorJobs(large: name == "orchestratorLarge")
        let project = doc.addProject(name: "board", folder: folder.path, color: .purple)
        if let pane = doc.addPane(to: project, tab: PaneTab(id: TabID(rawValue: "tab-lead"), agent: "claude", title: "lead")) {
            doc.setDisabled(pane, true)
        }
        doc.addPane(to: project, content: .orchestrator)
        doc.workspace.selectedProjectID = project
    }

    private static func seedOrchestratorWorkerFixture(_ name: String, into doc: inout WorkspaceDocument) {
        seedOrchestratorWorker(into: &doc)
    }

    private static func seedOrchestratorApplyFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let folder = seedApplyRepository()
        let project = doc.addProject(name: "applyrepo", folder: folder.path, color: .purple)
        if let pane = doc.addPane(to: project, tab: PaneTab(id: TabID(rawValue: "tab-lead"), agent: "claude", title: "lead")) {
            doc.setDisabled(pane, true)
        }
        doc.addPane(to: project, content: .orchestrator)
        doc.workspace.selectedProjectID = project
    }

    private static func seedSkillsFixture(_ name: String, into doc: inout WorkspaceDocument) {
        seedSkills()
    }

    private static func seedGsdSyncFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let repo = seedPlanningRepository()
        let project = doc.addProject(name: "gsdproj", folder: repo.path, color: .purple)
        if let pane = doc.addPane(to: project, tab: PaneTab(agent: "opencode")) { doc.setDisabled(pane, true) }
        doc.workspace.selectedProjectID = project
    }

    private static func seedMcpFixture(_ name: String, into doc: inout WorkspaceDocument) {
        seedMcp()
    }

    private static func seedMultiagentFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let repo = seedSchedulerRepository()
        doc.addProject(name: "agentrepo", folder: repo.path, color: .purple)
        if name == "multiagentLive" { touchPlanningPeriodically(in: repo) }
    }

    private static func seedPromptFixture(_ name: String, into doc: inout WorkspaceDocument) {
        let folder = UserDefaults.standard.string(forKey: "AletheUITestFolder") ?? "/private/tmp"
        let project = doc.addProject(name: "prompted", folder: folder, color: .purple)
        doc.addPane(to: project, tab: PaneTab(agent: "claude", initialPrompt: "/help"))
    }
}
#endif
