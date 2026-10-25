import AletheDesign
import AletheFoundation
import AletheModel
import AlethePluginKit
import SwiftUI

struct PaneFocusBorderSection: View {
    @AppStorage(PaneFocusBorder.enabledKey) private var enabled = true
    @AppStorage(PaneFocusBorder.opacityKey) private var opacity = 1.0
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        Section {
            Toggle("settings.paneFocus.show", isOn: $enabled)
                .accessibilityIdentifier("settings.paneFocus.show")
            HStack(spacing: metrics.size(10)) {
                Slider(value: $opacity, in: 0.1...1, step: 0.05)
                    .tint(theme[.accent])
                    .disabled(!enabled)
                    .accessibilityLabel(Text("settings.paneFocus.opacity"))
                    .accessibilityIdentifier("settings.paneFocus.opacity")
                Text(verbatim: opacity.formatted(.percent.precision(.fractionLength(0))))
                    .font(metrics.monoFont(size: 12, weight: .bold))
                    .frame(width: metrics.size(56), height: metrics.size(40))
                    .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                Button { opacity = 1 } label: {
                    Image(systemName: "arrow.counterclockwise").webProfileSized(15)
                }
                .buttonStyle(SettingsZoomButtonStyle())
                .disabled(!enabled || opacity == 1)
                .accessibilityLabel(Text("settings.web.reference.prefs.opacityReset"))
            }
            .frame(maxWidth: metrics.size(420))
        } header: { Text("settings.paneFocus.title") }
          footer: { Text("settings.paneFocus.desc") }
    }
}
