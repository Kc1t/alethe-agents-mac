import Foundation

public enum VisualStyle: String, Codable, CaseIterable, Sendable {
    case normal, clean
}

public enum InterfaceStyle: String, Codable, CaseIterable, Sendable {
    case web, mac
}

extension Theme {
    public func styled(_ style: VisualStyle) -> Theme {
        guard style == .clean else { return self }
        var colors = self.colors
        let neutral: [ThemeToken: ThemeToken] = [
            .accentSoft: .panelHover, .accentFaint: .panelHover, .accentBorder: .borderStrong,
            .accentBorderSoft: .border, .borderAccent: .border,
        ]
        for (token, source) in neutral { colors[token] = self.colors[source] }
        colors[.accentRing] = ThemeColor(hex: "#00000000")
        let flat = ThemeShadow(x: 0, y: 0, blur: 0, color: Self.missingTokenColor)
        return Theme(id: id, isLight: isLight, swatch: swatch, colors: colors,
                     shadows: Dictionary(uniqueKeysWithValues: ShadowLevel.allCases.map { ($0, flat) }), terminal: terminal)
    }
}
