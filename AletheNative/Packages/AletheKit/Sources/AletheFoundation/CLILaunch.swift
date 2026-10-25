import Foundation

public enum CLILaunch {
    public static let openPathFlag = "--open-path"

    public static func pathArgument(in arguments: [String]) -> String? {
        var index = 1
        while index < arguments.count {
            let argument = arguments[index]
            index += 1
            if argument == openPathFlag {
                return index < arguments.count ? arguments[index] : nil
            }
            if argument.hasPrefix(openPathFlag + "=") {
                return String(argument.dropFirst(openPathFlag.count + 1))
            }
            if argument.hasPrefix("--") || argument.hasPrefix("-psn_") { continue }
            if argument.hasPrefix("-"), argument.count > 1 {
                index += 1
                continue
            }
            return argument
        }
        return nil
    }

    public static func resolveTarget(arguments: [String], cwd: URL) -> URL? {
        guard let raw = pathArgument(in: arguments) else { return nil }
        return resolve(raw, cwd: cwd)
    }

    public static func resolve(_ raw: String, cwd: URL) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = (trimmed as NSString).expandingTildeInPath
        let candidate = expanded.hasPrefix("/")
            ? URL(filePath: expanded)
            : cwd.appending(path: expanded)
        return directory(for: candidate)
    }

    public static func directory(for url: URL) -> URL? {
        let resolved = canonical(url)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resolved.path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue ? resolved : resolved.deletingLastPathComponent()
    }

    public static func canonical(_ url: URL) -> URL {
        URL(filePath: url.standardizedFileURL.resolvingSymlinksInPath().path, directoryHint: .inferFromPath)
    }

    public static func samePath(_ a: String, _ b: String) -> Bool {
        let expand = { (path: String) in URL(filePath: (path as NSString).expandingTildeInPath) }
        return canonical(expand(a)).path == canonical(expand(b)).path
    }

    public static func match<ID: Equatable>(folder: String, in candidates: [(id: ID, folder: String)],
                                            preferred: ID? = nil) -> ID? {
        let matches = candidates.filter { samePath($0.folder, folder) }.map(\.id)
        if let preferred, matches.contains(preferred) { return preferred }
        return matches.first
    }
}
