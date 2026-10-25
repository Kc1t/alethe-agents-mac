import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct ContainerHeader: View {
    let project: Project
    let isSelected: Bool
    let isFullscreen: Bool
    let onLayout: (PaneLayoutMode) -> Void
    let onDesignLayout: () -> Void
    let onGrid: (GridAction) -> Void
    let onCollapse: () -> Void
    let onFullscreen: () -> Void
    let onClose: () -> Void
    let onDrag: (CGSize?) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    @State private var webHovered = false
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        if metrics.isWebInterface { webContainerHeader } else { nativeContainerHeader }
    }

    private var webContainerHeader: some View {
        HStack(spacing: metrics.size(6)) {
            if !isFullscreen {
                Image(systemName: "circle.grid.2x3.fill")
                    .font(metrics.font(size: 11))
                    .foregroundStyle(theme[.fgFaint])
                    .frame(width: metrics.size(22), height: metrics.size(22))
            }
            Circle().fill(theme[project.color.token])
                .frame(width: metrics.size(7), height: metrics.size(7))
            Text(verbatim: project.name)
                .font(metrics.font(size: 11, weight: .semibold))
                .foregroundStyle(theme[.fg])
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: String(project.visiblePanes.count))
                .font(metrics.font(size: 10, weight: .bold))
                .foregroundStyle(theme[.fgFaint])
                .padding(.horizontal, metrics.size(3))
            HStack(spacing: 0) {
                headerButton("plus", label: "menu.file.newTerminal", id: "container.newTerminal.\(project.name)") {
                    environment.editorRequest = .newTerminal(project.id)
                }
                if !isFullscreen {
                    headerButton("chevron.right", label: "workspace.container.collapse", id: "container.collapse.\(project.name)", action: onCollapse)
                }
                headerButton(isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                             label: isFullscreen ? "workspace.container.showAll" : "workspace.container.showAlone",
                             id: "container.fullscreen.\(project.name)", action: onFullscreen)
                headerButton("minus", label: "workspace.container.close", id: "container.close.\(project.name)", action: onClose)
                layoutMenu
                if !project.namedGrids.isEmpty { gridMenu }
            }
            .opacity(webHovered ? 1 : 0)
            .allowsHitTesting(webHovered)
        }
        .padding(.horizontal, metrics.size(8))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme[.bgElevated])
        .overlay(alignment: .bottom) { theme[.border].frame(height: metrics.size(1)) }
        .contentShape(Rectangle())
        .onHover { webHovered = $0 }
        .animation(Motion.WorkspaceEffect.close.animation(reduceMotion: metrics.reducesMotion), value: webHovered)
        .gesture(DragGesture(minimumDistance: metrics.size(4), coordinateSpace: .global)
            .onChanged { onDrag($0.translation) }.onEnded { _ in onDrag(nil) })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("container.\(project.name)")
    }

    private var nativeContainerHeader: some View {
        HStack(spacing: metrics.space(.s)) {
            Circle()
                .fill(theme[project.color.token])
                .frame(width: metrics.size(7), height: metrics.size(7))
            Text(verbatim: project.name)
                .font(metrics.font(size: 11, weight: .semibold))
                .foregroundStyle(theme[metrics.isWebInterface || isSelected ? .fg : .fgMuted])
                .lineLimit(1)
            Spacer(minLength: 0)
            if !project.namedGrids.isEmpty { gridMenu }
            layoutMenu
            if !isFullscreen {
                headerButton("sidebar.left", label: "workspace.container.collapse", id: "container.collapse.\(project.name)",
                             action: onCollapse)
            }
            headerButton(isFullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                         label: isFullscreen ? "workspace.container.showAll" : "workspace.container.showAlone",
                         id: "container.fullscreen.\(project.name)", action: onFullscreen)
            headerButton("xmark", label: "workspace.container.close", id: "container.close.\(project.name)", action: onClose)
        }
        .padding(.horizontal, metrics.space(.m))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme[.bgElevated])
        .overlay(alignment: .bottom) { theme[.border].frame(height: metrics.size(1)) }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { onDrag($0.translation) }
                .onEnded { _ in onDrag(nil) }
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("container.\(project.name)")
    }

    private var layoutMenu: some View {
        WebMenu {
            if metrics.isWebInterface {
                ForEach(PaneLayoutMode.allCases, id: \.self) { mode in
                    Button { onLayout(mode) } label: { WebMenuCheckRow(title: Text(mode.title),
                        symbol: mode.symbol, selected: mode == project.layout) }
                }
            } else {
                Picker(selection: Binding(get: { project.layout }, set: onLayout)) {
                    ForEach(PaneLayoutMode.allCases, id: \.self) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            }
            WebMenuDivider()
            Button("workspace.layout.design", action: onDesignLayout)
            if project.namedGrids.isEmpty {
                Button("projectGrid.newEllipsis") { onGrid(.new) }
            }
        } label: {
            Image(systemName: project.layout.symbol)
                .font(metrics.font(.caption).weight(.semibold))
                .frame(width: metrics.size(18), height: metrics.size(18))
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(theme[.textTertiary])
        .help(Text("workspace.layout"))
        .accessibilityLabel(Text("workspace.layout"))
        .accessibilityIdentifier("container.layout.\(project.name)")
    }

    private var gridMenu: some View {
        WebMenu {
            if metrics.isWebInterface {
                Button { onGrid(.activate(nil)) } label: {
                    WebMenuCheckRow(title: Text("projectGrid.main"), symbol: "square.grid.2x2", selected: project.shownGridID == nil)
                }
                ForEach(project.namedGrids) { grid in
                    Button { onGrid(.activate(grid.id)) } label: {
                        WebMenuCheckRow(title: Text(verbatim: grid.name), symbol: "square.grid.2x2",
                            selected: project.shownGridID == grid.id)
                    }
                }
            } else {
                Picker(selection: Binding(get: { project.shownGridID }, set: { onGrid(.activate($0)) })) {
                    Text("projectGrid.main").tag(ProjectGridID?.none)
                    ForEach(project.namedGrids) { grid in
                        Text(verbatim: grid.name).tag(Optional(grid.id))
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            }
            WebMenuDivider()
            Button("projectGrid.newEllipsis") { onGrid(.new) }
            if let shown = project.shownGridID {
                Button("projectGrid.renameEllipsis") { onGrid(.rename(shown)) }
                Button("projectGrid.deleteEllipsis") { onGrid(.delete(shown)) }
            }
        } label: {
            HStack(spacing: metrics.space(.xs)) {
                Image(systemName: "rectangle.3.group")
                Text(verbatim: project.gridName(project.shownGridID) ?? String(localized: "projectGrid.main"))
                    .lineLimit(1)
            }
            .font(metrics.font(.footnote).weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(theme[.textSecondary])
        .help(Text("projectGrid.switch"))
        .accessibilityLabel(Text("projectGrid.switch"))
        .accessibilityIdentifier("container.grids.\(project.name)")
    }

    private func headerButton(_ symbol: String, label: LocalizedStringKey, id: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(label, systemImage: symbol)
        }
        .buttonStyle(AletheIconButtonStyle(side: metrics.isWebInterface ? 16 : 20))
        .help(Text(label))
        .accessibilityLabel(Text(label))
        .accessibilityIdentifier(id)
    }
}

struct CollapsedContainerStrip: View {
    let project: Project
    let isSelected: Bool
    let onExpand: () -> Void
    let onDrag: (CGSize?) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        VStack(spacing: metrics.space(.m)) {
            Circle()
                .fill(theme[project.color.token])
                .frame(width: metrics.size(8), height: metrics.size(8))
            Text(verbatim: project.name)
                .font(metrics.font(.footnote).weight(.medium))
                .foregroundStyle(theme[isSelected ? .textPrimary : .textSecondary])
                .lineLimit(1)
                .fixedSize()
                .rotationEffect(.degrees(90))
                .frame(width: metrics.size(18))
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .padding(.vertical, metrics.space(.l))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme[.bgElevated], in: RoundedRectangle(cornerRadius: metrics.isWebInterface ? 0 : metrics.radius(.md)))
        .overlay(RoundedRectangle(cornerRadius: metrics.isWebInterface ? 0 : metrics.radius(.md)).strokeBorder(theme[.border]))
        .contentShape(Rectangle())
        .onTapGesture(perform: onExpand)
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { onDrag($0.translation) }
                .onEnded { _ in onDrag(nil) }
        )
        .help(Text("workspace.container.expand"))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: project.name))
        .accessibilityHint(Text("workspace.container.expand"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onExpand() }
        .accessibilityIdentifier("container.collapsed.\(project.name)")
    }
}
