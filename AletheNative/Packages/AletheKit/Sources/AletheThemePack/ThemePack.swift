import AletheDesign
import AlethePluginKit
import Foundation

public enum ThemePackError: Error, Equatable {
    case missingResource(String)
    case invalidResource(String)
}

public enum ThemePack {
    public static let themeIDs = ["dark-lemon", "orca", "ember", "golden-premium"]

    public static func contributions() throws -> [ThemeContribution] {
        try contributions(bundle: .module)
    }

    static func contributions(bundle: Bundle) throws -> [ThemeContribution] {
        try themeIDs.map { id in
            guard let url = bundle.url(forResource: id, withExtension: "json", subdirectory: "Themes") else {
                throw ThemePackError.missingResource(id)
            }
            let data = try Data(contentsOf: url)
            guard let header = try? JSONDecoder().decode(Header.self, from: data), header.id == id else {
                throw ThemePackError.invalidResource(id)
            }
            return ThemeContribution(id: id, name: header.name, data: data)
        }
    }

    private struct Header: Decodable {
        let id: String
        let name: String
    }
}

public final class ThemePackPlugin: AlethePlugin {
    public static let manifest = PluginManifest(id: "alethe.theme-pack", version: "1.0.0", name: "Theme Pack")

    public init() {}

    public func activate(context: PluginContext) throws {
        for theme in try ThemePack.contributions() {
            try context.addTheme(theme)
        }
    }
}

extension ThemeCatalog {
    public func merging(contributions: [ThemeContribution]) -> ThemeCatalog {
        let decoder = JSONDecoder()
        let themes = contributions.compactMap { contribution -> Theme? in
            guard let theme = try? decoder.decode(Theme.self, from: contribution.data),
                  theme.id == contribution.id else { return nil }
            return theme
        }
        return merging(themes)
    }
}
