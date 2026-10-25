import AletheDesign
import AletheFoundation
import AletheModel
import AlethePluginKit
import SwiftUI

struct SettingsZoomButtonStyle: ButtonStyle {
    @Environment(\.metrics) private var metrics
    @Environment(\.theme) private var theme
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(metrics.font(size: 14))
            .frame(width: metrics.size(40), height: metrics.size(40))
            .background(theme[configuration.isPressed ? .panelHover : .bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
            .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
            .opacity(enabled ? 1 : 0.38)
    }
}
