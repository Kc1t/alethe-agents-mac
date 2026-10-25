import SwiftUI

struct SyncToolbarItem: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        Button { environment.editorRequest = .gistSync } label: {
            Label { Text("gistSync.title") } icon: { Image(systemName: "arrow.triangle.2.circlepath") }
        }
        .help(Text("gistSync.title"))
        .accessibilityIdentifier("gistSync.button")
    }
}
