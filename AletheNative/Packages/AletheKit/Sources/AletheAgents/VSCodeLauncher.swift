import Foundation

public enum VSCodeLauncher {
    public static let command = "code"
    public static let bundleIdentifiers = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium"]

    public enum Resolution: Equatable, Sendable {
        case cli(String)
        case app(URL)
        case missing
    }

    public static func resolve(resolver: (String) -> String?, appURL: (String) -> URL?) -> Resolution {
        if let cli = resolver(command) { return .cli(cli) }
        for identifier in bundleIdentifiers {
            if let url = appURL(identifier) { return .app(url) }
        }
        return .missing
    }

    public static func arguments(opening path: String) -> [String]? {
        guard path.hasPrefix("/") else { return nil }
        return [path]
    }
}
