import AletheDesign
import SwiftUI

struct Router9ToolbarItem: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    private var controller: Router9Controller { environment.router9 }

    var body: some View {
        Group {
            if controller.preferences.enabled {
                if controller.hasInstall { pill }
                else { Color.clear.frame(width: 0, height: 0).accessibilityHidden(true) }
            }
        }
        .task(id: controller.preferences.enabled) {
            if controller.preferences.enabled { await controller.watch() }
        }
    }

    private var pill: some View {
        let running = controller.isRunning
        return Button {
            Task { await controller.toggleRunning() }
        } label: {
            Label {
                Text(running ? "router9.pill.running" : "router9.pill.stopped")
            } icon: {
                Image(systemName: "circle.fill")
                    .font(.system(size: metrics.size(7)))
                    .foregroundStyle(theme[running ? .statusActive : .statusDisabled])
            }
            .labelStyle(.titleAndIcon)
        }
        .disabled(controller.busy)
        .help(Text(running ? "router9.pill.stop" : "router9.pill.start"))
        .accessibilityValue(Text(running ? "router9.pill.on" : "router9.pill.off"))
        .accessibilityIdentifier("toolbar.router9")
    }
}
