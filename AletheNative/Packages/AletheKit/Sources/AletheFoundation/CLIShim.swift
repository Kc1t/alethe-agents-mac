import Foundation

public enum CLIShim {
    public static let fileName = "alethe"
    public static let version = 1
    static let targetMarker = "ALETHE_TARGET_APP:"
    static let versionMarker = "ALETHE_SHIM_VERSION:"
    static let pathProbePrefix = "__ALETHE_PATH__="

    public enum State: Equatable, Sendable {
        case missing
        case current
        case stale
        case foreign
    }

    public static func defaultDirectory(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        home.appending(path: ".local/bin", directoryHint: .isDirectory)
    }

    public static func quote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
    }

    public static func script(appPath: String) -> String? {
        guard !appPath.isEmpty, !appPath.contains(where: \.isNewline) else { return nil }
        let app = quote(appPath)
        return """
        #!/bin/sh
        # alethe: opens a folder in Alethe from the terminal.
        #
        # Written by Alethe (Settings > General > Command Line Tool). Do not edit it by hand:
        # reinstall it from there, especially after moving or reinstalling the app.
        #
        #   alethe             opens the current folder
        #   alethe .           same
        #   alethe ~/project   opens the given folder (a file opens its folder)
        #
        # \(targetMarker) \(appPath)
        # \(versionMarker) \(version)

        set -e

        case "${1:-}" in
          -h|--help)
            echo "usage: alethe [folder]"
            exit 0
            ;;
        esac

        target=${1:-.}

        if [ -f "$target" ]; then
          target=$(dirname -- "$target")
        fi

        if [ ! -d "$target" ]; then
          echo "alethe: folder not found: $target" >&2
          exit 1
        fi

        # Absolute path: the app compares it with the saved project folders.
        target=$(cd -- "$target" && pwd -P)

        if [ ! -d \(app) ]; then
          echo "alethe: Alethe is no longer at "\(app)"; reinstall the command from its Settings" >&2
          exit 1
        fi

        exec /usr/bin/open -a \(app) "$target"

        """
    }

    static func value(of marker: String, in contents: String) -> String? {
        for line in contents.split(whereSeparator: \.isNewline) {
            guard let range = line.range(of: marker) else { continue }
            return line[range.upperBound...].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    public static func targetApp(in contents: String) -> String? {
        value(of: targetMarker, in: contents)
    }

    public static func state(of contents: String?, appPath: String) -> State {
        guard let contents else { return .missing }
        guard let target = targetApp(in: contents) else { return .foreign }
        let current = target == appPath && value(of: versionMarker, in: contents) == String(version)
        return current ? .current : .stale
    }

    public static func location(in directory: URL) -> URL {
        directory.appending(path: fileName, directoryHint: .notDirectory)
    }

    public static func read(in directory: URL) -> String? {
        try? String(contentsOf: location(in: directory), encoding: .utf8)
    }

    @discardableResult
    public static func install(appPath: String, in directory: URL) throws -> URL {
        guard let text = script(appPath: appPath) else { throw CocoaError(.fileWriteInvalidFileName) }
        let file = location(in: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        return file
    }

    public static func uninstall(in directory: URL) throws {
        let file = location(in: directory)
        guard let contents = read(in: directory) else {
            if FileManager.default.fileExists(atPath: file.path) { throw CocoaError(.fileReadNoPermission) }
            return
        }
        guard targetApp(in: contents) != nil else { throw CocoaError(.fileWriteNoPermission) }
        try FileManager.default.removeItem(at: file)
    }

    public static func pathContains(_ directory: URL, pathVariable: String) -> Bool {
        let target = directory.standardizedFileURL.path
        return pathVariable.split(separator: ":").contains { entry in
            let expanded = (String(entry) as NSString).expandingTildeInPath
            return URL(filePath: expanded).standardizedFileURL.path == target
        }
    }

    public static let pathProbeCommand = #"printf '\n__ALETHE_PATH__=%s\n' "$PATH""#

    public static func parsePathProbe(_ output: String) -> String? {
        output.split(whereSeparator: \.isNewline)
            .last { $0.hasPrefix(pathProbePrefix) }
            .map { String($0.dropFirst(pathProbePrefix.count)) }
    }

    public static let pathExportLine = #"export PATH="$HOME/.local/bin:$PATH""#
}
