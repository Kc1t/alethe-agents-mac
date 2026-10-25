import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

struct SidebarProjectsHeader: View {
    let actions: SidebarActions
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.metrics) private var metrics

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: metrics.isWebInterface ? metrics.size(4) : metrics.space(.xxs)) {
            AletheSectionLabel(Text("sidebar.projects.header"))
                .lineLimit(1)
            Spacer(minLength: metrics.space(.s))
            Button { environment.editorRequest = .newGroup(parent: nil) } label: {
                Label { Text("menu.file.newGroup") } icon: {
                    Image(systemName: metrics.isWebInterface ? "folder.badge.plus" : "rectangle.stack.badge.plus").webProfileSized(14) }
                    .modifier(SidebarSymbolAppearance(size: 14))
            }
            .buttonStyle(AletheIconButtonStyle(side: 20))
            .help(Text("menu.file.newGroup"))
            .accessibilityIdentifier("sidebar.newGroup")
            if !metrics.isWebInterface {
                Button { actions.chooseFolders() } label: {
                    Label { Text("sidebar.addProject") } icon: { Image(systemName: "folder.badge.plus").webProfileSized(14) }
                }
                .buttonStyle(AletheIconButtonStyle(side: 20))
                .help(Text("sidebar.addProject"))
                .accessibilityIdentifier("sidebar.addProject")
            }
            if metrics.isWebInterface {
                Menu {
                    SidebarMenuButton("menu.file.newProject", symbol: "plus") { environment.editorRequest = .newProject(.ungrouped) }
                    SidebarMenuButton("sidebar.addProject", symbol: "folder.badge.plus") { actions.chooseFolders() }
                        .accessibilityIdentifier("sidebar.addProject")
                } label: {
                    Label { Text("menu.file.newProject") } icon: { Image(systemName: "plus").webProfileSized(14) }.labelStyle(.iconOnly)
                } primaryAction: {
                    environment.editorRequest = .newProject(.ungrouped)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .modifier(SidebarMenuAppearance())
                .buttonStyle(AletheIconButtonStyle(side: 20))
                .frame(width: metrics.size(20), height: metrics.size(20))
                .help(Text("menu.file.newProject"))
                .accessibilityIdentifier("sidebar.newProject")
            } else {
                Button { environment.editorRequest = .newProject(.ungrouped) } label: {
                    Label { Text("menu.file.newProject") } icon: { Image(systemName: "plus").webProfileSized(14) }
                }
                .buttonStyle(AletheIconButtonStyle(side: 20))
                .help(Text("menu.file.newProject"))
                .accessibilityIdentifier("sidebar.newProject")
            }
        }
        .padding(.horizontal, metrics.isWebInterface ? metrics.size(12) : 0)
        .frame(height: metrics.isWebInterface ? metrics.size(34) : nil)
        .overlay(alignment: .bottom) {
            if metrics.isWebInterface {
                Rectangle().fill(theme[.border]).frame(height: metrics.size(1))
            }
        }
    }
}
