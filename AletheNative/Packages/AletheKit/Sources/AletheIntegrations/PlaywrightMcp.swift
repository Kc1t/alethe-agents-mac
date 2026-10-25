public enum PlaywrightBrowserMode: String, CaseIterable, Codable, Sendable {
    case shared
    case dedicated
}

public enum PlaywrightMcp {
    public static let serverName = "playwright"
    public static let command = "npx"
    public static let package = "@playwright/mcp@latest"

    public static func arguments(endpoint: String?, dedicatedHeadless: Bool?) -> [String] {
        var arguments = ["-y", package]
        if let endpoint {
            arguments += ["--cdp-endpoint", endpoint]
        } else if dedicatedHeadless == true {
            arguments.append("--headless")
        }
        return arguments
    }

    public static func arguments(mode: PlaywrightBrowserMode, dedicatedHeadless: Bool,
                                 sharedEndpoint: String?) -> [String] {
        if case .shared = mode { return arguments(endpoint: sharedEndpoint, dedicatedHeadless: nil) }
        return arguments(endpoint: nil, dedicatedHeadless: dedicatedHeadless)
    }
}
