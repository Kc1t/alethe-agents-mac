import Darwin
import Foundation

public enum BrowserLaunch {
    public static let bundleNames = [
        "Google Chrome.app/Contents/MacOS/Google Chrome",
        "Chromium.app/Contents/MacOS/Chromium",
        "Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
        "Brave Browser.app/Contents/MacOS/Brave Browser",
    ]

    public static func candidates(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        let roots = [URL(filePath: "/Applications", directoryHint: .isDirectory),
                     home.appending(path: "Applications", directoryHint: .isDirectory)]
        return roots.flatMap { root in bundleNames.map { root.appending(path: $0) } }
    }

    public static func resolve(explicit: String?, candidates: [URL] = candidates(),
                               isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) })
        throws(BrowserSessionError) -> URL {
        if let explicit = explicit?.trimmingCharacters(in: .whitespacesAndNewlines), !explicit.isEmpty {
            let expanded = URL(filePath: (explicit as NSString).expandingTildeInPath)
            let executable = expanded.pathExtension == "app" ? Bundle(url: expanded)?.executableURL : expanded
            guard let executable, isExecutable(executable.path) else { throw .browserNotFound }
            return executable
        }
        guard let found = candidates.first(where: { isExecutable($0.path) }) else { throw .browserNotFound }
        return found
    }

    public static func endpoint(port: UInt16) -> String {
        "http://127.0.0.1:\(port)"
    }

    public static func arguments(port: UInt16, profileDirectory: URL, headless: Bool) -> [String] {
        var arguments = [
            "--remote-debugging-port=\(port)",
            "--remote-debugging-address=127.0.0.1",
            profileArgument(profileDirectory),
            "--no-first-run",
            "--no-default-browser-check",
            "--use-mock-keychain",
            "--disable-features=Translate",
        ]
        if headless { arguments.append("--headless=new") }
        arguments.append("about:blank")
        return arguments
    }

    static func profileArgument(_ directory: URL) -> String {
        "--user-data-dir=\(directory.standardizedFileURL.path)"
    }

    public static func freePort() throws(BrowserSessionError) -> UInt16 {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { throw .noFreePort }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { raw in
                Darwin.bind(socket, raw, length) == 0 && getsockname(socket, raw, &length) == 0
            }
        }
        let port = UInt16(bigEndian: address.sin_port)
        guard bound, port != 0 else { throw .noFreePort }
        return port
    }

    public static func isBrowserExecutable(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent.lowercased()
        return ["chrome", "chromium", "edge", "brave"].contains { name.contains($0) }
    }

    public static func isStale(executable: String, arguments: [String], profileDirectory: URL) -> Bool {
        guard isBrowserExecutable(executable) else { return false }
        let expected = profileArgument(profileDirectory)
        return arguments.dropFirst().contains(expected)
    }
}

public enum BrowserSessionError: Error, Hashable, Sendable {
    case browserNotFound
    case profileDirectory(String)
    case noFreePort
    case spawnFailed(String)
    case notReady
}
