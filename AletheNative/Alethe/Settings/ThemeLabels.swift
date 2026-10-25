import AletheDesign
import SwiftUI

extension Theme {
    var localizedName: Text {
        let labels: [String: Text] = [
            "elite-original": Text("theme.eliteOriginal"),
            "elite-pure-black": Text("theme.elitePureBlack"),
            "elite-indigo": Text("theme.eliteIndigo"),
            "elite-blush": Text("theme.eliteBlush"),
            "dark": Text("theme.dark"),
            "light": Text("theme.light"),
            "dracula": Text("theme.dracula"),
            "nord": Text("theme.nord"),
            "gruvbox": Text("theme.gruvbox"),
            "solarized": Text("theme.solarized"),
            "tokyo-night": Text("theme.tokyoNight"),
            "vscode": Text("theme.vscode"),
            "min-dark": Text("theme.minDark"),
            "min-light": Text("theme.minLight"),
            "catppuccin-frappe": Text("theme.catppuccinFrappe"),
            "gruvbox-material": Text("theme.gruvboxMaterial"),
            "dark-lemon": Text("theme.darkLemon"),
            "orca": Text("theme.orca"),
            "ember": Text("theme.ember"),
            "golden-premium": Text("theme.goldenPremium"),
        ]
        return labels[id] ?? Text(verbatim: id)
    }

    var localizedSummary: Text? {
        let labels: [String: Text] = [
            "elite-original": Text("theme.eliteOriginal.summary"),
            "elite-pure-black": Text("theme.elitePureBlack.summary"),
            "elite-indigo": Text("theme.eliteIndigo.summary"),
            "elite-blush": Text("theme.eliteBlush.summary"),
            "dark": Text("theme.dark.summary"),
            "light": Text("theme.light.summary"),
            "dracula": Text("theme.dracula.summary"),
            "nord": Text("theme.nord.summary"),
            "gruvbox": Text("theme.gruvbox.summary"),
            "solarized": Text("theme.solarized.summary"),
            "tokyo-night": Text("theme.tokyoNight.summary"),
            "vscode": Text("theme.vscode.summary"),
            "min-dark": Text("theme.minDark.summary"),
            "min-light": Text("theme.minLight.summary"),
            "catppuccin-frappe": Text("theme.catppuccinFrappe.summary"),
            "gruvbox-material": Text("theme.gruvboxMaterial.summary"),
        ]
        return labels[id]
    }
}
