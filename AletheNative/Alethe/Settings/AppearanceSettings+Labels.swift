import AletheDesign
import AletheFoundation
import AletheModel
import AlethePluginKit
import SwiftUI

extension AppIconTheme {
    var localizedName: Text {
        if case .eliteOriginal = self {
            return Text("theme.eliteOriginal")
        } else if case .elitePureBlack = self {
            return Text("theme.elitePureBlack")
        } else if case .eliteIndigo = self {
            return Text("theme.eliteIndigo")
        } else {
            return Text("theme.eliteBlush")
        }
    }
}

extension VisualStyle {
    var title: LocalizedStringKey {
        if case .normal = self {
            return "settings.appearance.style.normal"
        } else {
            return "settings.appearance.style.clean"
        }
    }

    var detail: LocalizedStringKey {
        if case .normal = self {
            return "settings.appearance.style.normal.detail"
        } else {
            return "settings.appearance.style.clean.detail"
        }
    }
}

extension InterfaceStyle {
    var title: LocalizedStringKey {
        if case .web = self {
            return "settings.appearance.interface.web"
        } else {
            return "settings.appearance.interface.mac"
        }
    }

    var detail: LocalizedStringKey {
        if case .web = self {
            return "settings.appearance.interface.web.detail"
        } else {
            return "settings.appearance.interface.mac.detail"
        }
    }
}
