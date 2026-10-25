#if DEBUG
import AletheModel
import AppKit
import Foundation

enum TestSeeds {
    static func apply(_ name: String, to doc: inout WorkspaceDocument) {
        if let seed = workspaceFixtures[name] { seed(name, &doc); return }
        seedRemote(name, into: &doc)
        seedDiscord(name, into: &doc)
        seedSpotify(name, into: &doc)
        seedGistSync(name, into: &doc)
        seedRouter9(name, into: &doc)
    }

    static func apply(_ name: String, to preferences: inout PreferencesDocument) {
        if let style = UserDefaults.standard.string(forKey: "AletheUITestVisualStyle") { preferences.visualStyle = style }
        if let theme = UserDefaults.standard.string(forKey: "AletheUITestTheme") { preferences.themeID = theme }
        if case "gsdSync" = name {
            preferences.features.set(.gsdSync, on: true)
        } else if case orchestratorWorker = name {
            seedOrchestratorWorker(into: &preferences)
        } else if ["orchestrator", "orchestratorBoard", "orchestratorLarge", "orchestratorApply",
                   "multiagent", "multiagentLive"].contains(name) {
            preferences.features.set(.orchestrator, on: true)
        } else {
            seedRemote(name, into: &preferences)
            seedDiscord(name, into: &preferences)
            seedSpotify(name, into: &preferences)
            seedGistSync(name, into: &preferences)
            seedRouter9(name, into: &preferences)
        }
    }

    @MainActor
    static func apply(_ name: String, to environment: AppEnvironment) {
        seedRemote(name, environment: environment)
        seedDiscord(name, environment: environment)
        seedSpotify(name, environment: environment)
        seedGistSync(name, environment: environment)
        seedRouter9(name, environment: environment)
    }

    static func seedOrchestratorJobs(large: Bool) -> URL {
        let root = URL(filePath: UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp")
        let folder = root.appending(path: "boardrepo")
        let profile = root.appending(path: "profiles/default")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        let start: UInt64 = 1_750_000_000_000
        func job(_ id: Int, run: Int, label: String, planner: String?, agent: String = "codex", status: String,
                 summary: String = "", extra: [String: Any] = [:]) -> [String: Any] {
            var record: [String: Any] = [
                "id": String(format: "job-%02d", id), "agent": agent, "runId": String(format: "run-%02d", run),
                "runLabel": label, "spec": "Task \(id)", "cwd": folder.path, "status": status,
                "plan": [String](), "summary": summary, "approvalPolicy": "\"never\"", "sandbox": "workspace-write",
                "webSearch": false, "startedAt": start, "endedAt": start + UInt64(40_000 + id * 1000),
            ]
            if let planner { record["plannerId"] = planner }
            return record.merging(extra) { _, new in new }
        }
        var jobs: [[String: Any]] = []
        if large {
            for id in 1...100 {
                let run = (id - 1) / 20 + 1
                jobs.append(job(id, run: run, label: "Batch \(run)", planner: "tab-lead",
                                status: id % 7 == 0 ? "failed" : "done", summary: "Worker \(id) finished.\nAll good."))
            }
        } else {
            jobs = [
                job(1, run: 1, label: "Refactor parser", planner: "tab-lead", status: "done",
                    summary: "Split the parser into modules.\nAll tests pass.",
                    extra: ["plan": ["Read the parser", "Split it"],
                            "tokens": ["total": ["totalTokens": 12_345], "modelContextWindow": 200_000]]),
                job(2, run: 1, label: "Refactor parser", planner: "tab-lead", agent: "claude", status: "failed",
                    extra: ["outcome": "the worker exited with status 1"]),
                job(3, run: 1, label: "Refactor parser", planner: "tab-lead", status: "running",
                    extra: ["threadId": "thread-3"]),
                job(4, run: 2, label: "Docs", planner: "tab-lead", agent: "claude", status: "done",
                    summary: "Docs updated.", extra: ["worktree": folder.appending(path: ".alethe/worktrees/job-04").path]),
                job(5, run: 3, label: "Outside", planner: nil, status: "done", summary: "Done from outside."),
            ]
        }
        let file: [String: Any] = [
            "version": 2,
            "jobs": jobs,
            "planners": [["id": "tab-lead", "label": "lead", "agent": "claude"]],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: file) {
            try? data.write(to: profile.appending(path: "orchestrator-jobs.json"))
        }
        return folder
    }

    static func seedApplyRepository() -> URL {
        let root = URL(filePath: UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp")
        let repo = root.appending(path: "applyrepo")
        let profile = root.appending(path: "profiles/default")
        let worktree = repo.appending(path: ".alethe/worktrees/job-01")
        try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: profile, withIntermediateDirectories: true)
        try? Data("seed\n".utf8).write(to: repo.appending(path: "README.md"))
        for arguments in [["init", "-q", "-b", "main"], ["config", "user.name", "seed"],
                          ["config", "user.email", "seed@local"], ["config", "commit.gpgsign", "false"],
                          ["add", "."], ["commit", "-q", "-m", "seed"],
                          ["worktree", "add", "-q", "-b", "alethe/agent-job-01", worktree.path, "HEAD"]] {
            let git = Process()
            git.executableURL = URL(filePath: "/usr/bin/git")
            git.arguments = ["-C", repo.path] + arguments
            try? git.run()
            git.waitUntilExit()
        }
        try? Data("from the worker\n".utf8).write(to: worktree.appending(path: "feature.txt"))
        let start: UInt64 = 1_750_000_000_000
        let job: [String: Any] = [
            "id": "job-01", "agent": "codex", "runId": "run-01", "runLabel": "Feature", "spec": "Add the feature",
            "cwd": repo.path, "status": "done", "plan": [String](), "summary": "Added feature.txt.",
            "approvalPolicy": "\"never\"", "sandbox": "workspace-write", "webSearch": false,
            "startedAt": start, "endedAt": start + 30_000, "plannerId": "tab-lead", "worktree": worktree.path,
        ]
        let file: [String: Any] = [
            "version": 2, "jobs": [job], "planners": [["id": "tab-lead", "label": "lead", "agent": "claude"]],
        ]
        if let data = try? JSONSerialization.data(withJSONObject: file) {
            try? data.write(to: profile.appending(path: "orchestrator-jobs.json"))
        }
        return repo
    }

    static func seedPlanningRepository() -> URL {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        let repo = URL(filePath: root).appending(path: "gsdrepo")
        let planning = repo.appending(path: ".planning")
        try? FileManager.default.createDirectory(at: planning, withIntermediateDirectories: true)
        let git = Process()
        git.executableURL = URL(filePath: "/usr/bin/git")
        git.arguments = ["-C", repo.path, "init", "-q"]
        try? git.run()
        git.waitUntilExit()
        let files = [
            ".gsd-child-session": "ses_seededchild\n",
            ".gsd-child-busy": "",
            "status.md": "Status: In Progress\nProgress: 40%\n",
            "task.md": "- [x] Map the API\n- [ ] Write the client\n- [ ] Ship it\n",
            "plan.md": "# Plan\n\n1. Map the API\n",
        ]
        for (name, text) in files { try? Data(text.utf8).write(to: planning.appending(path: name)) }
        return repo
    }

    static func seedSchedulerRepository() -> URL {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        let repo = URL(filePath: root).appending(path: "agentrepo")
        let planning = repo.appending(path: ".planning")
        try? FileManager.default.createDirectory(at: planning, withIntermediateDirectories: true)
        try? Data("- [x] Map the API\n- [ ] Write the client\n- [ ] Ship it\n".utf8)
            .write(to: planning.appending(path: "task.md"))
        try? Data("# Plan\n".utf8).write(to: planning.appending(path: "plan.md"))
        for arguments in [["init", "-q", "-b", "main"], ["config", "user.name", "seed"], ["config", "user.email", "seed@local"],
                          ["config", "commit.gpgsign", "false"], ["add", "."],
                          ["commit", "-q", "-m", "gsd(alethe): seed", "-m", "Alethe-Agent: seed"]] {
            let git = Process()
            git.executableURL = URL(filePath: "/usr/bin/git")
            git.arguments = ["-C", repo.path] + arguments
            try? git.run()
            git.waitUntilExit()
        }
        return repo
    }

    static func touchPlanningPeriodically(in repo: URL) {
        let notes = repo.appending(path: ".planning/notes.md")
        Task.detached(priority: .utility) {
            for tick in 0..<100 {
                try? await Task.sleep(for: .seconds(3))
                let line = "tick \(tick)\n"
                if let handle = try? FileHandle(forWritingTo: notes) {
                    handle.seekToEndOfFile()
                    handle.write(Data(line.utf8))
                    try? handle.close()
                } else {
                    try? Data(line.utf8).write(to: notes)
                }
            }
        }
    }

    static func seedSkills() {
        guard let home = UserDefaults.standard.string(forKey: "AletheIntegrationsHome") else { return }
        let root = URL(filePath: home, directoryHint: .isDirectory)
        func skill(_ path: String, _ text: String) -> URL {
            let dir = root.appending(path: path, directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: dir.appending(path: "SKILL.md"))
            return dir
        }
        let brand = skill(".agents/skills/brand", "---\nname: brand\ndescription: Brand system\n---\n\n# Brand\n\nUse the palette.\n")
        try? FileManager.default.createDirectory(at: root.appending(path: ".claude/skills"), withIntermediateDirectories: true)
        try? FileManager.default.createSymbolicLink(at: root.appending(path: ".claude/skills/brand"), withDestinationURL: brand)
        let motion = skill(".claude/skills/motion", "---\nname: motion\ndescription: >\n"
            + "  Creates motion\n  graphics\n---\n\n# Motion guide\n")
        try? FileManager.default.createDirectory(at: motion.appending(path: "references"), withIntermediateDirectories: true)
        try? Data("notes".utf8).write(to: motion.appending(path: "references/timing.md"))
        _ = skill(".codex/skills/.system/imagegen", "---\ndescription: Generates images\n---\n\n# Images\n")
    }

    static func seedMcp() {
        guard let home = UserDefaults.standard.string(forKey: "AletheIntegrationsHome") else { return }
        let root = URL(filePath: home, directoryHint: .isDirectory)
        func write(_ path: String, _ text: String) {
            let file = root.appending(path: path)
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(text.utf8).write(to: file)
        }
        write(".claude.json", """
            {"mcpServers": {"alpha": {"type": "stdio", "command": "npx", "args": ["-y", "alpha-mcp"],
              "env": {"API_KEY": "sk-test-0123456789abcd"}}}}
            """)
        write(".codex/config.toml", "[mcp_servers.beta]\ncommand = \"uvx\"\nargs = [\"beta-mcp\"]\n")
        write(".cursor/mcp.json", "{\"mcpServers\": {}}\n")
        for folder in [".config/opencode", ".gemini/config"] {
            try? FileManager.default.createDirectory(at: root.appending(path: folder), withIntermediateDirectories: true)
        }
    }

    static func seedRepository() -> URL {
        let root = UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp"
        let repo = URL(filePath: root).appending(path: "repo")
        try? FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let file = repo.appending(path: "notes.txt")
        try? Data("alpha\nbeta\n".utf8).write(to: file)
        for arguments in [["init", "-q", "-b", "main"], ["add", "."], ["commit", "-q", "-m", "seed"]] {
            let git = Process()
            git.executableURL = URL(filePath: "/usr/bin/git")
            git.arguments = ["-C", repo.path, "-c", "user.name=seed", "-c", "user.email=seed@local",
                             "-c", "commit.gpgsign=false"] + arguments
            try? git.run()
            git.waitUntilExit()
        }
        try? Data("alpha\nbeta two\ngamma\n".utf8).write(to: file)
        return repo
    }
}
#endif
