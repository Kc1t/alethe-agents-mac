import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct RemoteShareToggle: View {
    let pane: Pane
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Toggle("remote.share", isOn: Binding(get: { pane.isRemoteShared },
                                             set: { environment.remoteControl.setShared(pane.id, $0) }))
            .accessibilityIdentifier("remote.share")
    }
}

struct RemoteSharedGlyph: View {
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        Image(systemName: "iphone.radiowaves.left.and.right").webProfileSized(14)
            .font(metrics.font(.caption))
            .foregroundStyle(theme[.accent])
            .help(Text("remote.shared"))
            .accessibilityLabel(Text("remote.shared"))
            .accessibilityIdentifier("remote.sharedGlyph")
    }
}
