import AletheDesign
import CoreGraphics
import GhosttyTerminal

public enum TerminalAppearance {
    public static let defaultFontSize: Float = 13

    public nonisolated(unsafe) static var fontFamilyOverride: String?

    public static func configuration(for theme: Theme, fontSize: Float = defaultFontSize,
                                     metrics: Metrics? = nil) -> TerminalConfiguration {
        let palette = theme.terminal
        let web = metrics?.isWebInterface == true
        let size = metrics.map { $0.isWebInterface ? Float($0.size(14)) : fontSize } ?? fontSize
        var configuration = TerminalConfiguration()
            .fontFamily(fontFamilyOverride ?? AletheFonts.terminalFamily)
            .fontSize(size)
            .fontThicken(false)
            .background(opaqueHex(palette.background, over: palette.background))
            .foreground(opaqueHex(palette.foreground, over: palette.background))
            .cursorColor(opaqueHex(palette.cursor, over: palette.background))
            .selectionBackground(opaqueHex(palette.selection, over: palette.background, maxAlpha: 0.3))
            .windowPaddingX(web ? 0 : 8)
            .windowPaddingY(web ? 0 : 6)
            .custom("keybind", "clear")
        if web {
            configuration = configuration.custom("link-url", "false").custom("link-osc8", "false")
        }
        for (index, color) in palette.ansi.enumerated() {
            configuration = configuration.palette(index, color: opaqueHex(color, over: palette.background))
        }
        return configuration
    }

    public static func terminalTheme(for theme: Theme, fontSize: Float = defaultFontSize,
                                     metrics: Metrics? = nil) -> TerminalTheme {
        let configuration = configuration(for: theme, fontSize: fontSize, metrics: metrics)
        return TerminalTheme(light: configuration, dark: configuration)
    }

    public static func surfaceFrame(in bounds: CGRect, metrics: Metrics?) -> CGRect { bounds }

    static func opaqueHex(_ color: ThemeColor, over background: ThemeColor, maxAlpha: Double = 1) -> String {
        let alpha = min(color.alpha, maxAlpha)
        func channel(_ top: Double, _ bottom: Double) -> Int {
            Int(((top * alpha + bottom * (1 - alpha)) * 255).rounded())
        }
        let rgb = [
            channel(color.red, background.red),
            channel(color.green, background.green),
            channel(color.blue, background.blue),
        ]
        return "#" + rgb.map { String(format: "%02x", $0) }.joined()
    }
}
