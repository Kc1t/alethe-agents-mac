import Foundation

public extension RemoteAppearance {
    static let defaultTheme = "elite-indigo"

    static let knownThemes: Set<String> = [
        "elite-original", "elite-pure-black", "elite-indigo", "elite-blush", "dark", "light",
        "dracula", "nord", "gruvbox", "solarized", "tokyo-night", "vscode", "min-dark", "min-light",
        "dark-lemon", "orca", "ember", "golden-premium",
    ]

    static let lightThemes: Set<String> = ["elite-original", "elite-blush", "light", "min-light"]

    static let knownAppIcons: Set<String> = ["elite-original", "elite-pure-black", "elite-indigo", "elite-blush"]

    static func resolved(
        uiTheme: String?,
        appIconTheme: String?,
        language: String?,
        motionPreference: String?
    ) -> RemoteAppearance {
        let theme = uiTheme.flatMap { knownThemes.contains($0) ? $0 : nil } ?? defaultTheme
        return RemoteAppearance(
            uiTheme: theme,
            appIconTheme: appIconTheme.flatMap { knownAppIcons.contains($0) ? $0 : nil } ?? defaultTheme,
            language: language == "pt-BR" ? "pt-BR" : "en",
            motionPreference: motionPreference == "reduced" ? "reduced" : "animated",
            colorScheme: lightThemes.contains(theme) ? "light" : "dark"
        )
    }

    static let fallback = resolved(uiTheme: nil, appIconTheme: nil, language: nil, motionPreference: nil)

    var normalized: RemoteAppearance {
        Self.resolved(uiTheme: uiTheme, appIconTheme: appIconTheme, language: language, motionPreference: motionPreference)
    }
}
