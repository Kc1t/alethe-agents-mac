import AletheAgents
import AletheTerminal
import Foundation
import Observation

@Observable
@MainActor
final class AgentInstaller {
    enum Status: Equatable { case idle, running, succeeded, failed }

    private(set) var agent: AgentKind?
    private(set) var tool: String?
    private(set) var method: InstallMethod?
    private(set) var status: Status = .idle
    private(set) var log = ""

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var raw = ""

    var isBusy: Bool { status == .running }

    func toolchain(launchers: LauncherCache) async -> InstallToolchain {
        launchers.invalidate()
        let node = launchers.resolve("node")
        return InstallToolchain(node: node == nil ? nil : await CLIVersion.probe(node!),
                                npm: launchers.resolve("npm") != nil, brew: launchers.resolve("brew") != nil)
    }

    func run(_ method: InstallMethod, for agent: AgentKind, cli: String, launchers: LauncherCache) async {
        guard !isBusy else { return }
        self.agent = agent
        self.method = method
        tool = nil
        status = .running
        raw = ""
        log = ""
        let command = method.verifyCommand ?? cli
        var before: String?
        if !method.verifyAbsent, let found = launchers.resolve(command) { before = await CLIVersion.probe(found) }

        let exit = await execute(AgentInstallCatalog.shellArguments(for: method), command: method.command)

        launchers.invalidate()
        let found = launchers.resolve(command)
        let worked: Bool
        if method.verifyAbsent {
            worked = found == nil
        } else if let found {
            let after = await CLIVersion.probe(found)
            worked = before == nil || (after != nil && after != before)
        } else {
            worked = false
        }
        if exit != 0, !worked { append("\n[exit \(exit)]\n") }
        status = worked ? .succeeded : .failed
    }

    func run(command: String, tool: String, verify: @MainActor () async -> Bool) async {
        guard !isBusy else { return }
        agent = nil
        method = nil
        self.tool = tool
        status = .running
        raw = ""
        log = ""
        let exit = await execute(["-l", "-c", command], command: command)
        let worked = await verify()
        if exit != 0, !worked { append("\n[exit \(exit)]\n") }
        status = worked ? .succeeded : .failed
    }

    private func execute(_ arguments: [String], command: String) async -> Int32 {
        let process = Process()
        process.executableURL = URL(filePath: ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh")
        process.arguments = arguments
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "AletheInstallDryRun") {
            process.arguments = ["-c", "echo \"dry run: $0\"", command]
        }
        #endif
        process.currentDirectoryURL = URL(filePath: NSHomeDirectory())
        var environment = ProcessInfo.processInfo.environment
        for key in AgentLauncher.scrubbedVariables { environment.removeValue(forKey: key) }
        environment["NONINTERACTIVE"] = "1"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.append(text) }
        }
        self.process = process
        let exit: Int32 = await withCheckedContinuation { continuation in
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch {
                process.terminationHandler = nil
                continuation.resume(returning: -1)
            }
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        self.process = nil
        return exit
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        ProcessTree.kill(process.processIdentifier)
    }

    func reset() {
        guard !isBusy else { return }
        status = .idle
        agent = nil
        method = nil
        tool = nil
        log = ""
    }

    private func append(_ text: String) {
        raw += text
        if raw.count > InstallLog.maxCharacters * 2 { raw = String(raw.suffix(InstallLog.maxCharacters)) }
        log = InstallLog.clean(raw)
    }
}
