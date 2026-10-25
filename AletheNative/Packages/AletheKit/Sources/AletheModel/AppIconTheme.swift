import Foundation

public enum AppIconTheme: String, CaseIterable, Codable, Hashable, Sendable {
    case eliteOriginal = "elite-original"
    case elitePureBlack = "elite-pure-black"
    case eliteIndigo = "elite-indigo"
    case eliteBlush = "elite-blush"

    public static let `default` = AppIconTheme.eliteIndigo

    public init(normalizing value: String?) {
        self = value.flatMap(AppIconTheme.init(rawValue:)) ?? .default
    }

    public var assetName: String { "AppIcon-\(rawValue)" }
}

extension PreferencesDocument {
    public var iconTheme: AppIconTheme {
        get { AppIconTheme(normalizing: appIconTheme) }
        set { appIconTheme = newValue == .default ? nil : newValue.rawValue }
    }
}
