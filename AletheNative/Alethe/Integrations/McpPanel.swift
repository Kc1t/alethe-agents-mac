import AletheDesign
import AletheIntegrations
import AletheModel
import AlethePluginKit
import SwiftUI

struct McpManagerRoute: Hashable {
    enum Tab: String, Hashable { case servers, skills }

    var tab = Tab.servers
    var server: String?
    var add = false
}

struct McpPanel: View {
    @Environment(AppEnvironment.self) private var environment

    static let tabID = "mcp"
    static let tab = SidebarTabContribution(id: tabID, title: "MCP", symbol: "powerplug", side: .right, viewID: tabID)

    var body: some View {
        if let model = environment.mcp {
            McpPanelContent(model: model, skillStore: environment.skillStore, folder: selectedFolder)
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedFolder: String? {
        environment.workspace.flatMap { model in
            model.document.workspace.selectedProjectID.flatMap(model.document.project)?.folder
        }
    }
}

struct McpPanelContent: View {
    enum Section: String, Hashable { case servers, skills }

    let model: McpManagerModel
    let skillStore: SkillStore
    let folder: String?
    @Environment(AppEnvironment.self) var environment
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics
    @State var section = Section.servers
    @State var query = ""
    @State var picked: Set<McpAgent> = []
    @State var skills: [SkillGroup]?
    @FocusState var searchFocused: Bool

    var visibleServers: [McpServerGroup] {
        model.groups.filter { $0.matches(query) && $0.isOn(anyOf: picked) }
    }

    var visibleSkills: [SkillGroup] {
        (skills ?? []).filter { group in
            group.matches(query)
                && (picked.isEmpty
                    || group.agents.contains { agent in
                        picked.contains { $0.rawValue == agent.rawValue }
                    })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: metrics.isWebInterface ? 0 : metrics.space(.m)) {
            header
            Group {
                if metrics.isWebInterface {
                    HStack(spacing: metrics.size(7)) {
                        Image(systemName: "magnifyingglass").resizable().scaledToFit()
                            .frame(width: metrics.size(13), height: metrics.size(13)).foregroundStyle(theme[.fgFaint])
                        TextField(
                            text: $query, prompt: Text((section == .servers ? "mcp.search" : "mcp.searchSkills") as LocalizedStringKey)
                        ) {
                            Text("mcp.search")
                        }.textFieldStyle(.plain).focused($searchFocused)
                    }
                    .font(metrics.font(size: 12.5)).foregroundStyle(theme[.fg])
                    .padding(.vertical, metrics.size(6)).padding(.horizontal, metrics.size(10))
                    .modifier(AletheSidebarFieldBorder(focused: searchFocused))
                    .accessibilityIdentifier("mcp.panel.search")
                } else {
                    TextField(text: $query, prompt: Text((section == .servers ? "mcp.search" : "mcp.searchSkills") as LocalizedStringKey)) {
                        Text("mcp.search")
                    }.textFieldStyle(.roundedBorder).accessibilityIdentifier("mcp.panel.search")
                }
            }
            .padding(.horizontal, metrics.isWebInterface ? metrics.size(10) : 0)
            .padding(.top, metrics.isWebInterface ? metrics.size(8) : 0)
            filters
                .padding(.horizontal, metrics.isWebInterface ? metrics.size(10) : 0)
                .padding(.top, metrics.isWebInterface ? metrics.size(8) : 0)
            stats
                .padding(.horizontal, metrics.isWebInterface ? metrics.size(12) : 0)
                .padding(.top, metrics.isWebInterface ? metrics.size(8) : 0)
                .padding(.bottom, metrics.isWebInterface ? metrics.size(6) : 0)
            if section == .servers, let error = model.error {
                if metrics.isWebInterface {
                    Text(verbatim: error).font(metrics.font(size: 12)).foregroundStyle(theme[.statusWaiting])
                        .padding(metrics.size(10)).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md))
                            .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                        .padding(metrics.size(10)).accessibilityIdentifier("mcp.panel.error")
                } else {
                    banner(error, symbol: "exclamationmark.triangle.fill", token: .statusStopped, id: "mcp.panel.error")
                }
            }
            list
            addButton
                .padding(.horizontal, metrics.isWebInterface ? metrics.size(10) : 0)
                .padding(.bottom, metrics.isWebInterface ? metrics.size(10) : 0)
            if section == .servers, !model.issues.isEmpty { diagnostics }
        }
        .padding(metrics.isWebInterface ? 0 : metrics.space(.l))
        .task(id: folder) { model.setRepository(folder) }
        .task(id: section) {
            if section == .skills, skills == nil { await loadSkills() }
        }
        .onChange(of: model.groups) { model.checkHealthOnce() }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcp.panel")
    }
}
