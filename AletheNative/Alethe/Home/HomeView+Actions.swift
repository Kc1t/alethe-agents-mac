import AletheAgents
import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct HomeActions: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        if metrics.isWebInterface { webBody } else { nativeBody }
    }

    private var nativeBody: some View {
        VStack(alignment: .leading, spacing: metrics.space(.m)) {
            HomeSectionHeader(title: "home.start")
            VStack(spacing: metrics.space(.xs)) {
                row("home.action.newTerminal", icon: "terminal", keys: "⌘T", id: "home.action.newTerminal") {
                    environment.editorRequest = .newTerminal(nil)
                }
                row("home.action.newProject", icon: "folder.badge.plus", keys: "⌘N", id: "home.action.newProject") {
                    environment.editorRequest = .newProject(.ungrouped)
                }
                row("home.action.newGroup", icon: "square.stack.3d.up", keys: "⇧⌘N", id: "home.action.newGroup") {
                    environment.editorRequest = .newGroup(parent: nil)
                }
                row("home.action.findJump", icon: "magnifyingglass", keys: "⌘K", id: "home.action.findJump") {
                    environment.editorRequest = .findJump
                }
            }
        }
    }

    private var webBody: some View {
        VStack(alignment: .leading, spacing: metrics.size(12)) {
            HomeSectionHeader(title: "home.start")
            LazyVGrid(columns: metrics.isWebInterface
                      ? [GridItem(.adaptive(minimum: metrics.size(150)), spacing: metrics.size(8))]
                      : [GridItem(.flexible())], spacing: metrics.isWebInterface ? metrics.size(8) : metrics.space(.xs)) {
                row("home.action.newTerminal", icon: "terminal", keys: "⌘T", id: "home.action.newTerminal") {
                    environment.editorRequest = .newTerminal(nil)
                }
                row("home.action.newProject", icon: "folder.badge.plus", keys: "⌘N", id: "home.action.newProject") {
                    environment.editorRequest = .newProject(.ungrouped)
                }
                row("home.action.newGroup", icon: "square.stack.3d.up", keys: "⇧⌘N", id: "home.action.newGroup") {
                    environment.editorRequest = .newGroup(parent: nil)
                }
            }
        }
    }

    private func webTitle(_ id: String) -> LocalizedStringKey {
        if case "home.action.newTerminal" = id {
            "home.web.newTerminal"
        } else if case "home.action.newProject" = id {
            "home.web.newProject"
        } else {
            "home.web.newGroup"
        }
    }

    private func row(_ title: LocalizedStringKey, icon: String, keys: String?, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: metrics.space(.m)) {
                Image(systemName: icon).webProfileSized(14).frame(width: metrics.size(18)).foregroundStyle(theme[.textSecondary])
                if metrics.isWebInterface { Text(webTitle(id)).font(metrics.font(size: 12)) } else { Text(title) }
                Spacer()
                if let keys, !metrics.isWebInterface { Text(verbatim: keys).font(metrics.font(.footnote))
                    .foregroundStyle(theme[.textTertiary]) }
            }
            .padding(.horizontal, metrics.size(metrics.isWebInterface ? 14 : 12))
            .padding(.vertical, metrics.size(metrics.isWebInterface ? 12 : 8))
            .contentShape(Rectangle())
            .frame(minHeight: metrics.isWebInterface ? metrics.size(44) : nil)
            .background(theme[metrics.isWebInterface ? .bgSunken : .surfaceCardDefault]
                .opacity(metrics.isWebInterface ? 0.86 : 1), in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
            .overlay {
                if metrics.isWebInterface {
                    RoundedRectangle(cornerRadius: metrics.radius(.md))
                        .strokeBorder(theme[.border], lineWidth: metrics.size(1))
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }
}
