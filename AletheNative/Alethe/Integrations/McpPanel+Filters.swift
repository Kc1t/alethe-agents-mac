import AletheDesign
import AletheIntegrations
import AletheModel
import AlethePluginKit
import SwiftUI

extension McpPanelContent {
    var header: some View {
        HStack(spacing: metrics.isWebInterface ? metrics.size(8) : metrics.space(.s)) {
            if metrics.isWebInterface {
                HStack(spacing: metrics.size(2)) {
                    ForEach([Section.servers, .skills], id: \.self) { option in
                        Button {
                            section = option
                        } label: {
                            Text((option == .servers ? "mcp.tab.servers" : "mcp.tab.skills") as LocalizedStringKey)
                        }
                        .buttonStyle(AletheSidebarFilterStyle(selected: section == option, kind: .segment))
                        .accessibilityAddTraits(section == option ? .isSelected : [])
                    }
                }
                .padding(metrics.size(3))
                .background(theme[.bgSunken], in: RoundedRectangle(cornerRadius: metrics.radius(.md)))
                .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md)).strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                .animation(Motion.sidebarColor(reduceMotion: metrics.reducesMotion), value: section)
                .accessibilityIdentifier("mcp.panel.section")
            } else {
                Picker("mcp.view", selection: $section) {
                    Text("mcp.tab.servers").tag(Section.servers)
                    Text("mcp.tab.skills").tag(Section.skills)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("mcp.panel.section")
            }
            if !metrics.isWebInterface { Spacer(minLength: 0) }
            if !metrics.isWebInterface, section == .servers, model.healthAvailable {
                Button {
                    model.checkAllHealth()
                } label: {
                    Image(systemName: model.checking.isEmpty ? "waveform.path.ecg" : "hourglass")
                }
                .buttonStyle(.borderless)
                .disabled(!model.checking.isEmpty || model.groups.isEmpty)
                .help(Text("mcp.health.checkAll"))
                .accessibilityLabel(Text("mcp.health.checkAll"))
                .accessibilityIdentifier("mcp.panel.health")
            }
            Button {
                if section == .servers { Task { await model.refresh() } } else { Task { await loadSkills() } }
            } label: {
                if metrics.isWebInterface {
                    Image(systemName: "arrow.clockwise").font(metrics.font(size: 13))
                        .modifier(AletheSidebarSpinner(active: model.loading, kind: .mcp))
                } else { Image(systemName: "arrow.clockwise") }
            }
            .modifier(McpRefreshPresentation())
            .disabled(model.loading)
            .help(Text("mcp.refresh"))
            .accessibilityLabel(Text("mcp.refresh"))
            .accessibilityIdentifier("mcp.panel.refresh")
        }
        .padding(.horizontal, metrics.isWebInterface ? metrics.size(10) : 0)
        .padding(.top, metrics.isWebInterface ? metrics.size(10) : 0)
        .padding(.bottom, metrics.isWebInterface ? metrics.size(8) : 0)
        .overlay(alignment: .bottom) {
            if metrics.isWebInterface { Rectangle().fill(theme[.borderSubtle]).frame(height: metrics.size(1)) }
        }
    }

    var filters: some View {
        HStack(spacing: metrics.isWebInterface ? metrics.size(8) : metrics.space(.xs)) {
            Group {
                if metrics.isWebInterface {
                    ScrollView(.horizontal) {
                        HStack(spacing: metrics.size(3)) { agentFilters }
                    }.scrollIndicators(.hidden)
                } else { agentFilters }
            }
            if !metrics.isWebInterface { Spacer(minLength: metrics.space(.s)) }
            if section == .servers {
                if metrics.isWebInterface {
                    HStack(spacing: metrics.size(6)) {
                        Button("mcp.scope.project") { scope.wrappedValue = .project }
                            .disabled(folder == nil)
                            .buttonStyle(AletheSidebarFilterStyle(selected: scope.wrappedValue == .project, kind: .scope))
                            .help(Text((folder == nil ? "mcp.scope.projectUnavailable" : "mcp.scope.help") as LocalizedStringKey))
                        Rectangle().fill(theme[.borderStrong]).frame(width: metrics.size(1), height: metrics.size(10))
                        Button("mcp.scope.global") { scope.wrappedValue = .global }
                            .buttonStyle(AletheSidebarFilterStyle(selected: scope.wrappedValue == .global, kind: .scope))
                            .help(Text("mcp.scope.help"))
                    }.font(metrics.font(size: 11)).fixedSize()
                        .accessibilityIdentifier("mcp.panel.scope")
                } else {
                    Picker("mcp.scope", selection: scope) {
                        Text("mcp.scope.project").tag(McpScope.project)
                        Text("mcp.scope.global").tag(McpScope.global)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    .disabled(folder == nil)
                    .help(Text((folder == nil ? "mcp.scope.projectUnavailable" : "mcp.scope.help") as LocalizedStringKey))
                    .accessibilityIdentifier("mcp.panel.scope")
                }
            }
        }
    }

    var agentFilters: some View {
            ForEach(McpAgent.allCases, id: \.self) { agent in
                let on = picked.contains(agent)
                Button {
                    if on { picked.remove(agent) } else { picked.insert(agent) }
                } label: {
                    Group {
                        if metrics.isWebInterface {
                            AgentLogo(agent: agent.rawValue, size: 13)
                        } else {
                            Circle()
                                .fill(theme[agent.colorToken].opacity(on || picked.isEmpty ? 1 : 0.3))
                                .frame(width: metrics.size(10), height: metrics.size(10))
                                .padding(metrics.space(.xs))
                                .background(on ? theme[.accentBgSoft] : .clear, in: Capsule())
                                .contentShape(Rectangle())
                        }
                    }
                }
                .modifier(McpFilterPresentation(selected: on))
                .help(Text(verbatim: agent.label))
                .accessibilityLabel(Text(verbatim: agent.label))
                .accessibilityValue(Text((on ? "mcp.filter.on" : "mcp.filter.off") as LocalizedStringKey))
                .accessibilityIdentifier("mcp.panel.agent.\(agent.rawValue)")
            }
    }

    var scope: Binding<McpScope> {
        Binding {
            model.effectiveScope
        } set: {
            model.setScope($0)
        }
    }

    var stats: some View {
        let shown = section == .servers ? visibleServers.count : visibleSkills.count
        let total = section == .servers ? model.groups.count : (skills?.count ?? 0)
        let filtered = !picked.isEmpty || !query.trimmingCharacters(in: .whitespaces).isEmpty
        let text =
            section == .servers
            ? (filtered ? format("mcp.stats.serversOf", shown, total) : format("mcp.stats.servers", shown))
            : (filtered ? format("mcp.stats.skillsOf", shown, total) : format("mcp.stats.skills", shown))
        return Text(verbatim: text)
            .font(metrics.isWebInterface ? metrics.font(size: 11.5) : metrics.font(.caption))
            .foregroundStyle(theme[metrics.isWebInterface ? .fgFaint : .textSecondary])
            .accessibilityIdentifier("mcp.panel.stats")
    }

    @ViewBuilder var list: some View {
        let loaded = section == .servers ? model.snapshots != nil : skills != nil
        let empty = section == .servers ? visibleServers.isEmpty : visibleSkills.isEmpty
        let none = section == .servers ? model.groups.isEmpty : (skills ?? []).isEmpty
        if !loaded && !metrics.isWebInterface {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if empty {
            Group {
                if metrics.isWebInterface {
                    WebMcpEmpty(title: emptyTitle(none: none), detail: none && section == .servers ? "mcp.empty.detail" : nil)
                } else {
                    ContentUnavailableView {
                        Label(emptyTitle(none: none), systemImage: "powerplug")
                    } description: {
                        if none && section == .servers { Text("mcp.empty.detail") }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("mcp.panel.empty")
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: metrics.isWebInterface ? 0 : metrics.space(.xs)) {
                    if section == .servers {
                        ForEach(visibleServers, id: \.name) { group in serverRow(group) }
                    } else {
                        ForEach(visibleSkills) { group in skillRow(group) }
                    }
                }
                .padding(.horizontal, metrics.isWebInterface ? metrics.size(6) : 0)
                .padding(.bottom, metrics.isWebInterface ? metrics.size(10) : 0)
            }
            .frame(maxHeight: .infinity)
        }
    }

    func emptyTitle(none: Bool) -> LocalizedStringKey {
        guard none else { return "mcp.noMatch" }
        return section == .servers ? "mcp.empty.title" : "skills.empty.title"
    }
}
