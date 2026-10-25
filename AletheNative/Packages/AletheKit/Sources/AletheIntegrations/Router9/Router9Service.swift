import AletheAgents
import Foundation
import Synchronization

public enum Router9Error: Error, Equatable, Sendable {
    case notInstalled
    case nodeNotFound
    case portInUse
    case fileSystem(String)
    case spawnFailed(String)
    case cancelled
}

public struct Router9Paths: Hashable, Sendable {
    public var profileDirectory: URL

    public init(profileDirectory: URL) {
        self.profileDirectory = profileDirectory
    }

    public var installDirectory: URL {
        profileDirectory.appending(path: "tools", directoryHint: .isDirectory)
            .appending(path: Router9.package, directoryHint: .isDirectory)
    }

    public var dataDirectory: URL {
        profileDirectory.appending(path: "tools", directoryHint: .isDirectory)
            .appending(path: "9router-data", directoryHint: .isDirectory)
    }

    public var logFile: URL { profileDirectory.appending(path: "9router.log", directoryHint: .notDirectory) }

    var packageDirectory: URL {
        installDirectory.appending(path: "node_modules", directoryHint: .isDirectory)
            .appending(path: Router9.package, directoryHint: .isDirectory)
    }

    public var entryScript: URL { packageDirectory.appending(path: "cli.js", directoryHint: .notDirectory) }

    public func installedVersion() -> String? {
        let manifest = packageDirectory.appending(path: "package.json", directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: manifest),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = object["version"] as? String, !version.isEmpty else { return nil }
        return version
    }
}

public enum Router9Commands {
    public static func install(_ paths: Router9Paths) -> String {
        "npm install --prefix \(shellQuoted(paths.installDirectory.plainPath)) "
            + "\(Router9.package)@\(Router9.pinnedVersion)"
    }

    public static func uninstall(_ paths: Router9Paths) -> String {
        "npm uninstall --prefix \(shellQuoted(paths.installDirectory.plainPath)) \(Router9.package)"
    }

    public static func shellQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

public struct Router9Launch: Hashable, Sendable {
    public var executable: String
    public var arguments: [String]
    public var directory: String?
    public var environment: [String: String]

    static func make(source: Router9Source, port: Int, paths: Router9Paths, entryScriptExists: Bool,
                     node: String?, external: String?) throws(Router9Error) -> Router9Launch {
        var launch: Router9Launch
        if case .managed = source {
            guard entryScriptExists else { throw .notInstalled }
            guard let node else { throw .nodeNotFound }
            launch = Router9Launch(executable: node, arguments: [paths.entryScript.plainPath],
                                   directory: paths.installDirectory.plainPath,
                                   environment: ["DATA_DIR": paths.dataDirectory.plainPath])
        } else {
            guard let external else { throw .notInstalled }
            launch = Router9Launch(executable: external, arguments: [], directory: nil, environment: [:])
        }
        let port = Router9.normalizePort(port)
        launch.environment["PORT"] = String(port)
        launch.environment["NEXT_PUBLIC_BASE_URL"] = Router9.baseURL(port: port)
        launch.environment["HOSTNAME"] = "127.0.0.1"
        return launch
    }
}

public struct Router9Dependencies: Sendable {
    public var resolveExternal: @Sendable () -> String?
    public var resolveNode: @Sendable () -> String?
    public var probeVersion: @Sendable (String) async -> String?
    public var isPortInUse: @Sendable (Int) async -> Bool
    public var searchDirectories: @Sendable () -> [String]

    public init(resolveExternal: @escaping @Sendable () -> String?,
                resolveNode: @escaping @Sendable () -> String?,
                probeVersion: @escaping @Sendable (String) async -> String?,
                isPortInUse: @escaping @Sendable (Int) async -> Bool,
                searchDirectories: @escaping @Sendable () -> [String]) {
        self.resolveExternal = resolveExternal
        self.resolveNode = resolveNode
        self.probeVersion = probeVersion
        self.isPortInUse = isPortInUse
        self.searchDirectories = searchDirectories
    }

    public static func live(launchers: LauncherCache = LauncherCache()) -> Router9Dependencies {
        Router9Dependencies(
            resolveExternal: { launchers.resolve(Router9.package) },
            resolveNode: { launchers.resolve("node") },
            probeVersion: { await CLIVersion.probe($0) },
            isPortInUse: { port in
                await Task.detached { Router9PortProbe.isInUse(port) }.value
            },
            searchDirectories: { launchers.searchDirectories }
        )
    }
}

public actor Router9Service {
    public nonisolated let paths: Router9Paths
    private let dependencies: Router9Dependencies
    private let slot = Mutex<Router9Process?>(nil)

    public init(profileDirectory: URL, dependencies: Router9Dependencies = .live()) {
        self.paths = Router9Paths(profileDirectory: profileDirectory)
        self.dependencies = dependencies
    }

    public nonisolated var isRunning: Bool { runningProcess() != nil }

    public nonisolated var processID: Int32? { runningProcess()?.pid }

    private nonisolated func runningProcess() -> Router9Process? {
        slot.withLock { current in
            guard let process = current else { return nil }
            if process.isRunning { return process }
            current = nil
            return nil
        }
    }

    public func status(port: Int = Router9.defaultPort) async -> Router9Status {
        let port = Router9.normalizePort(port)
        let paths = paths, dependencies = dependencies
        async let managedVersion = Task.detached { paths.installedVersion() }.value
        async let portInUse = dependencies.isPortInUse(port)
        async let external = Self.externalInstall(dependencies)
        return Router9Status(
            managed: await managedVersion.map { Router9Install(installed: true, version: $0) } ?? .none,
            external: await external,
            running: isRunning,
            portInUse: await portInUse,
            port: port,
            installDirectory: paths.installDirectory.plainPath,
            dataDirectory: paths.dataDirectory.plainPath,
            logPath: paths.logFile.plainPath,
            dashboardURL: Router9.dashboardURL(port: port)
        )
    }

    private static func externalInstall(_ dependencies: Router9Dependencies) async -> Router9Install {
        guard let path = dependencies.resolveExternal() else { return .none }
        return Router9Install(installed: true, version: await dependencies.probeVersion(path), path: path)
    }

    public func installCommand() throws(Router9Error) -> String {
        do {
            try FileManager.default.createDirectory(at: paths.installDirectory, withIntermediateDirectories: true)
        } catch {
            throw .fileSystem(error.localizedDescription)
        }
        return Router9Commands.install(paths)
    }

    public nonisolated func uninstallCommand() -> String { Router9Commands.uninstall(paths) }

    public func start(port: Int = Router9.defaultPort, source: Router9Source = .managed) async throws(Router9Error) {
        if isRunning { return }
        let port = Router9.normalizePort(port)
        if await dependencies.isPortInUse(port) { throw .portInUse }
        if Task.isCancelled { throw .cancelled }
        if isRunning { return }

        let paths = paths
        let entryExists = FileManager.default.isReadableFile(atPath: paths.entryScript.plainPath)
        let launch = try Router9Launch.make(
            source: source, port: port, paths: paths, entryScriptExists: entryExists,
            node: source == .managed ? dependencies.resolveNode() : nil,
            external: source == .external ? dependencies.resolveExternal() : nil)
        do {
            try FileManager.default.createDirectory(at: paths.logFile.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            if source == .managed {
                try FileManager.default.createDirectory(at: paths.dataDirectory, withIntermediateDirectories: true)
            }
        } catch {
            throw .fileSystem(error.localizedDescription)
        }

        var environment = ProcessInfo.processInfo.environment
        environment.merge(launch.environment) { _, added in added }
        if let directory = launch.directory { environment["PWD"] = directory }
        let executableDirectory = (launch.executable as NSString).deletingLastPathComponent
        environment["PATH"] = ([executableDirectory] + dependencies.searchDirectories()
            + (environment["PATH"] ?? "/usr/bin:/bin").split(separator: ":").map(String.init))
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            .joined(separator: ":")

        let process = try Router9Process.spawn(launch.executable, arguments: launch.arguments,
                                               directory: launch.directory, environment: environment,
                                               logFile: paths.logFile.plainPath)
        slot.withLock { $0 = process }
    }

    public func stop() async {
        guard let process = slot.withLock({ current -> Router9Process? in
            defer { current = nil }
            return current
        }) else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.terminate()
                continuation.resume()
            }
        }
    }

    public nonisolated func stopNow() {
        slot.withLock { current -> Router9Process? in
            defer { current = nil }
            return current
        }?.terminate()
    }
}

extension URL {
    fileprivate var plainPath: String {
        let path = path(percentEncoded: false)
        return path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
