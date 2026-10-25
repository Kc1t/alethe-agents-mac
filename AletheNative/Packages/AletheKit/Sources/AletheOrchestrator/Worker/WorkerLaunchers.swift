import Foundation
import AletheAgents

extension Launcher {
    public static func codexAppServer(program: URL) -> Launcher {
        Launcher(kind: WorkerAgent.codex, program: program, arguments: ["app-server", "--stdio"])
    }

    public static func claudeHeadless(program: URL) -> Launcher {
        Launcher(kind: WorkerAgent.claude, program: program, arguments: [
            "-p",
            "--input-format", "stream-json",
            "--output-format", "stream-json",
            "--verbose",
            "--permission-mode", "bypassPermissions",
        ])
    }

    public func arguments(resuming session: String?) -> [String] {
        guard kind == WorkerAgent.claude, let session, !session.isEmpty else { return arguments }
        return arguments + ["--resume", session]
    }
}

public enum WorkerLaunchError: Error, Hashable, Sendable, CustomStringConvertible {
    case unconfigured(agent: String)
    case cliNotFound(agent: String, command: String)

    public var description: String {
        if case .unconfigured(let agent) = self {
            return "no worker launcher configured for agent \(agent)"
        } else {
            guard case .cliNotFound(let agent, _) = self else {
                preconditionFailure("Invalid enum case")
            }
            return "no worker launcher configured for agent \(agent)"
        }
    }
}

public struct WorkerLaunchers: Sendable {
    public private(set) var launchers: [String: Launcher]
    public private(set) var missing: [String: String]

    public init(launchers: [String: Launcher] = [:], missing: [String: String] = [:]) {
        self.launchers = launchers
        self.missing = missing
    }

    public static func resolve(_ resolve: (_ command: String) -> String?) -> WorkerLaunchers {
        var result = WorkerLaunchers()
        let known: [(agent: String, make: (URL) -> Launcher)] = [
            (WorkerAgent.codex, Launcher.codexAppServer),
            (WorkerAgent.claude, Launcher.claudeHeadless),
        ]
        for (agent, make) in known {
            if let path = resolve(agent) {
                result.launchers[agent] = make(URL(filePath: path))
            } else {
                result.missing[agent] = agent
            }
        }
        return result
    }

    public func launcher(for agent: String) throws(WorkerLaunchError) -> Launcher {
        if let launcher = launchers[agent] { return launcher }
        if let command = missing[agent] { throw .cliNotFound(agent: agent, command: command) }
        throw .unconfigured(agent: agent)
    }

    public mutating func set(_ launcher: Launcher) {
        launchers[launcher.kind] = launcher
        missing[launcher.kind] = nil
    }
}

public enum WorkerEnvironment {
    public static func make(
        for launcher: Launcher,
        base: [String: String] = ProcessInfo.processInfo.environment,
        searchDirectories: [String]
    ) -> [String: String] {
        var environment = base
        for key in AgentLauncher.scrubbedVariables { environment[key] = nil }
        let own = launcher.program.deletingLastPathComponent().path(percentEncoded: false)
        var path: [String] = []
        for directory in [own] + searchDirectories where !directory.isEmpty {
            let normalized = directory.count > 1 && directory.hasSuffix("/") ? String(directory.dropLast()) : directory
            if !path.contains(normalized) { path.append(normalized) }
        }
        environment["PATH"] = path.joined(separator: ":")
        environment.merge(launcher.environment) { _, added in added }
        return environment
    }
}
