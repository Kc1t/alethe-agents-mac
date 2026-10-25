import Foundation

public enum TerminalLink: Equatable, Sendable {
    case web(URL)
    case file(path: String, line: Int?)
    case directory(path: String)
    case other(URL)
    case none

    public static func resolveWeb(_ raw: String, cwd: String?, home: String = NSHomeDirectory(),
                                  fileKind: (String) -> Bool? = TerminalLink.fileKind) -> TerminalLink {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = text.first, "([{'\"`".contains(first) { text.removeFirst() }
        while let last = text.last, ".,;:)]}'\"`".contains(last) { text.removeLast() }
        let bare = #"^(?:localhost(?::\d{1,5})?|(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+(?:app|ai|biz|br|ca|cloud|co|com|de|dev|edu|fr|gg|gov|info|io|jp|live|me|net|online|org|page|sh|site|tech|tools|tv|uk|xyz))(?::\d{1,5})?(?:/[^\s<>\"'`|]*)?$"#
        if text.range(of: bare, options: [.regularExpression, .caseInsensitive]) != nil {
            let local = text.range(of: #"^localhost(?::|/|$)"#, options: [.regularExpression, .caseInsensitive]) != nil
            let scheme = local ? "http" : "https"
            return resolve("\(scheme)://\(text)", cwd: cwd, home: home, fileKind: fileKind)
        }
        if text.lowercased().hasPrefix("http://") || text.lowercased().hasPrefix("https://"),
           let colon = text.firstIndex(of: ":") {
            text = text[..<colon].lowercased() + text[colon...]
        } else {
            text = text.replacingOccurrences(of: "\\ ", with: " ")
        }
        return resolve(text, cwd: cwd, home: home, fileKind: fileKind)
    }

    public static func resolve(_ raw: String, cwd: String?, home: String = NSHomeDirectory(),
                               fileKind: (String) -> Bool? = TerminalLink.fileKind) -> TerminalLink {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = text.last, ".,;:)]}'\"`".contains(last) { text.removeLast() }
        while let first = text.first, "([{'\"`".contains(first) { text.removeFirst() }
        guard !text.isEmpty else { return .none }

        if text.firstMatch(of: /^[A-Za-z][A-Za-z0-9+\-]*:(?!\d+(:\d+)?$)/) != nil,
           let url = URL(string: text), let scheme = url.scheme?.lowercased(), scheme.count > 1 {
            switch scheme {
            case "http", "https": return .web(url)
            case "file": return resolvePath(url.path, line: nil, cwd: cwd, home: home, fileKind: fileKind)
            default: return .other(url)
            }
        }
        var path = text
        var line: Int?
        if let match = text.firstMatch(of: /^(.+?):(\d+)(?::\d+)?$/) {
            path = String(match.1)
            line = Int(match.2)
        }
        return resolvePath(path, line: line, cwd: cwd, home: home, fileKind: fileKind)
    }

    private static func resolvePath(_ raw: String, line: Int?, cwd: String?, home: String,
                                    fileKind: (String) -> Bool?) -> TerminalLink {
        let decoded = raw.removingPercentEncoding ?? raw
        var path: String
        if decoded == "~" {
            path = home
        } else if decoded.hasPrefix("~/") {
            path = home + decoded.dropFirst(1)
        } else if decoded.hasPrefix("/") {
            path = decoded
        } else if let cwd {
            path = URL(filePath: cwd, directoryHint: .isDirectory).appending(path: decoded).path
        } else {
            return .none
        }
        path = URL(filePath: path).standardizedFileURL.path
        switch fileKind(path) {
        case true?: return .directory(path: path)
        case false?: return .file(path: path, line: line)
        case nil: return .none
        }
    }

    public static func fileKind(_ path: String) -> Bool? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return nil }
        return isDirectory.boolValue
    }

    public static func workingDirectory(fromReported value: String) -> String? {
        if value.hasPrefix("file://"), let url = URL(string: value) { return url.path }
        return value.hasPrefix("/") ? value : nil
    }
}
