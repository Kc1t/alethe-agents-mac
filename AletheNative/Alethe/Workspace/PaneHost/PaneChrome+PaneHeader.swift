import AletheDesign
import AletheModel
import AppKit
import SwiftUI

struct PaneHeader: View {
    let tab: PaneTab
    let isFocused: Bool
    let isLaneVisible: Bool
    let canHideLane: Bool
    let isIsolated: Bool
    let onClose: () -> Void
    let onNewSubTab: () -> Void
    let onToggleLane: () -> Void
    let onToggleIsolation: () -> Void
    let onFillFreeSpace: (() -> Void)?
    let gridTargets: [GridTarget]
    let onMoveToGrid: (ProjectGridID?) -> Void
    let isInFocusMode: Bool
    let onToggleFocus: () -> Void
    let onDisable: () -> Void
    let isRemoteShared: Bool
    let onToggleRemoteShared: () -> Void
    let onSessionCost: (() -> Void)?
    let onHandoff: (() -> Void)?
    let onDrag: (CGSize?) -> Void
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var topbarPinned: Bool = true
    var canDragPane: Bool = true
    var onToggleTopbar: () -> Void = {}
    private var location: (project: Project, pane: Pane)? {
        environment.workspace?.document.paneHolding(tab.id)
    }
    private var isShell: Bool { ["shell", "wsl"].contains(tab.agent) }
    private var hasProcess: Bool { environment.terminals.states[tab.id] != nil }

    @State private var renaming = false
    @State private var renameDraft = ""
    @FocusState private var renameFocused: Bool

    private func commitWebRename() {
        let name = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        environment.workspace?.update { $0.updateTab(tab.id) { $0.title = name.isEmpty ? nil : name } }
        renaming = false
    }

    var body: some View {
        Group {
            if metrics.isWebInterface { webHeader } else { nativeHeader }
        }
    }

    private var webHeader: some View {
        HStack(spacing: metrics.size(8)) {
            if !isShell || topbarPinned {
                HStack(spacing: metrics.size(6)) {
                    AgentLogo(agent: tab.agent, size: 16,
                              templateColor: theme[AgentTokens.accent(for: tab.agent)])
                        .frame(width: metrics.size(18), height: metrics.size(18))
                    Group {
                        if renaming {
                            TextField("", text: $renameDraft)
                                .textFieldStyle(.plain)
                                .focused($renameFocused)
                                .onSubmit { commitWebRename() }
                                .onExitCommand { renaming = false }
                                .onChange(of: renameFocused) { _, focused in
                                    if !focused && renaming { commitWebRename() }
                                }
                                .padding(.horizontal, metrics.size(4))
                                .padding(.vertical, metrics.size(1))
                                .background(theme[.bgElevated], in: RoundedRectangle(cornerRadius: metrics.size(4)))
                                .overlay(RoundedRectangle(cornerRadius: metrics.size(4))
                                    .strokeBorder(theme[.accent], lineWidth: metrics.size(1)))
                                .frame(width: metrics.size(160))
                        } else {
                            Text(verbatim: environment.terminals.displayName(of: tab))
                                .lineLimit(1)
                                .help(Text(verbatim: environment.terminals.displayName(of: tab)))
                                .onTapGesture(count: 2) {
                                    renameDraft = environment.terminals.displayName(of: tab)
                                    renaming = true
                                    renameFocused = true
                                }
                        }
                    }
                    .font(metrics.font(size: 12, weight: .medium))
                    .foregroundStyle(theme[.fg])
                }
                .frame(minWidth: 0, maxWidth: topbarPinned ? .infinity : metrics.size(320), alignment: .leading)
                .clipped()
                .padding(.horizontal, metrics.size(topbarPinned ? 0 : 6))
                .frame(height: metrics.size(26))
                .background(theme[.bgElevated].opacity(topbarPinned ? 0 : 0.92), in: RoundedRectangle(cornerRadius: metrics.size(4)))
                .overlay { if !topbarPinned {
                    RoundedRectangle(cornerRadius: metrics.size(4)).strokeBorder(theme[.border], lineWidth: metrics.size(1)) }
                }
                .onTapGesture(count: 2, perform: onToggleFocus)
                if !topbarPinned { Spacer(minLength: 0) }
            } else { Spacer(minLength: 0) }
            HStack(spacing: metrics.size(2)) {
                webAction(topbarPinned ? "pin.slash" : "pin", topbarPinned ? "pane.web.unpinTopbar"
                    : "pane.web.pinTopbar", active: topbarPinned, action: onToggleTopbar)
                webAction(isLaneVisible ? "sidebar.left" : "sidebar.leading", isLaneVisible
                    ? "pane.web.hideTabsLane" : "pane.web.showTabsLane", action: onToggleLane)
                    .disabled(!canHideLane)
                    .accessibilityAddTraits(isLaneVisible ? .isSelected : [])
                if !isShell {
                    webAction("clock", "pane.web.recentChats") {
                        environment.editorRequest = .conversations(location?.project.id)
                    }
                }
                if let onHandoff {
                    webAction("arrow.left.arrow.right", "pane.web.handoff", action: onHandoff)
                }
                webAction("chevron.left.forwardslash.chevron.right", "pane.web.openInVscode") {
                    if let project = location?.project {
                        OpenInActions.vsCode(tab.workingDirectory ?? project.folder, launchers: environment.launchers)
                    }
                }
                webAction(isInFocusMode ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                          isInFocusMode ? "pane.web.exitFocusModeEsc" : "pane.web.focusModeFullscreen", action: onToggleFocus)
                if hasProcess {
                    webAction("arrow.clockwise", "pane.web.restart") {
                        if let project = location?.project { environment.terminals.restart(tab, in: project, environment: environment) }
                    }
                    .disabled(location?.pane.isDisabled == true)
                }
                webAction("trash", "pane.web.deleteTerminal") {
                    Task {
                        if await WebDialogCenter.shared.confirm(
                            format("pane.web.confirmDeleteTerminal", environment.terminals.displayName(of: tab)),
                            confirmTitle: String(localized: "pane.web.deleteTerminal"), destructive: true) { onClose() }
                    }
                }
                    .accessibilityIdentifier("pane.close")
            }
            .fixedSize()
            .padding(.horizontal, metrics.size(topbarPinned ? 0 : 3))
            .frame(height: metrics.size(26))
            .background(theme[.bgElevated].opacity(topbarPinned ? 0 : 0.92), in: RoundedRectangle(cornerRadius: metrics.size(4)))
        }
        .padding(.horizontal, metrics.size(topbarPinned ? 8 : 4))
        .frame(height: metrics.size(topbarPinned ? 32 : 26))
        .background(theme[.shapeTabsLaneBg].opacity(topbarPinned ? 1 : 0))
        .overlay(alignment: .bottom) {
            if topbarPinned { theme[.shapeTabsLaneBorder].frame(height: metrics.size(1)) }
        }
        .background {
            if canDragPane && !isLaneVisible {
                Color.clear.contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: metrics.size(4), coordinateSpace: .global)
                        .onChanged { onDrag($0.translation) }.onEnded { _ in onDrag(nil) })
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.header.\(tab.title ?? tab.agent)")
    }

    private var webGrip: some View {
        Image(systemName: "circle.grid.2x3.fill")
            .font(metrics.font(size: 12))
            .foregroundStyle(theme[.fgMuted]).opacity(0.7)
            .frame(width: metrics.size(topbarPinned ? 22 : 20), height: metrics.size(topbarPinned ? 22 : 20))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: metrics.size(4), coordinateSpace: .global)
                .onChanged { onDrag($0.translation) }.onEnded { _ in onDrag(nil) })
            .help(Text("pane.web.dragToReorder"))
            .accessibilityLabel(Text("pane.web.dragToReorder"))
    }

    private func webAction(_ symbol: String, _ label: LocalizedStringKey, active: Bool = false,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if symbol == "chevron.left.forwardslash.chevron.right" {
                Label { Text(label) } icon: {
                    Image("BrandLogo-vscode").resizable().interpolation(.high).scaledToFit()
                        .frame(width: metrics.size(13), height: metrics.size(13))
                }
            } else {
                Label(label, systemImage: symbol)
            }
        }
            .buttonStyle(AletheTerminalHeaderActionStyle(pinned: topbarPinned, active: active, danger: symbol == "trash"))
            .help(Text(label)).accessibilityLabel(Text(label))
            .accessibilityAddTraits(active ? .isSelected : [])
    }

    private var nativeHeader: some View {
        HStack(spacing: metrics.space(.s)) {
            identityChip
            AgentStatusGlyph(tab: tab.id)
            if isRemoteShared { RemoteSharedGlyph() }
            if tab.unrestricted {
                Image(systemName: "bolt.fill")
                    .font(metrics.font(.caption))
                    .foregroundStyle(theme[.statusWaiting])
                    .help(Text("pane.unrestricted"))
                    .accessibilityLabel(Text("pane.unrestricted"))
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Label("pane.close", systemImage: "xmark")
            }
            .buttonStyle(AletheIconButtonStyle(side: 20))
            .help(Text("pane.close"))
            .accessibilityLabel(Text("pane.close"))
            .accessibilityIdentifier("pane.close")
        }
        .padding(.horizontal, metrics.space(.xs))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme[.bgSunken])
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onToggleFocus)
        .help(Text(isInFocusMode ? "focusMode.exitHint" : "focusMode.enterHint"))
        .gesture(
            DragGesture(minimumDistance: 4, coordinateSpace: .global)
                .onChanged { onDrag($0.translation) }
                .onEnded { _ in onDrag(nil) }
        )
        .webContextMenu {
            Button("subtabs.newEllipsis", action: onNewSubTab)
            Button(isLaneVisible ? LocalizedStringKey("subtabs.hideLane") : "subtabs.showLane", action: onToggleLane)
                .disabled(isLaneVisible && !canHideLane)
            Button(isIsolated ? LocalizedStringKey("pane.showAll") : "pane.showAlone", action: onToggleIsolation)
            Button(isInFocusMode ? LocalizedStringKey("focusMode.exit") : "focusMode.enter", action: onToggleFocus)
            if let onFillFreeSpace {
                Button("pane.fillFreeSpace", action: onFillFreeSpace)
            }
            if !gridTargets.isEmpty {
                WebSubmenu("pane.moveToGrid") {
                    ForEach(gridTargets) { target in
                        Button { onMoveToGrid(target.grid) } label: {
                            if let name = target.name { Text(verbatim: name) } else { Text("projectGrid.main") }
                        }
                    }
                }
            }
            if let onSessionCost {
                Button("menu.terminal.sessionCost", action: onSessionCost)
            }
            if let onHandoff {
                Button("menu.terminal.handoff", action: onHandoff)
            }
            if metrics.isWebInterface {
                Button(action: onToggleRemoteShared) {
                    WebMenuCheckRow(title: Text("remote.share"), symbol: "iphone", selected: isRemoteShared)
                }
                .accessibilityIdentifier("remote.share")
            } else {
                Toggle("remote.share", isOn: Binding(get: { isRemoteShared }, set: { _ in onToggleRemoteShared() }))
                    .accessibilityIdentifier("remote.share")
            }
            Button("pane.disable", action: onDisable)
            WebMenuDivider()
            Button("pane.close", action: onClose)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pane.header.\(tab.title ?? tab.agent)")
    }

    private var identityChip: some View {
        HStack(spacing: metrics.space(.s)) {
            Image(systemName: tab.agent == "shell" ? "terminal" : "sparkles")
                .font(metrics.font(size: 11, weight: .medium))
                .foregroundStyle(theme[AgentTokens.accent(for: tab.agent)])
            Text(verbatim: environment.terminals.displayName(of: tab))
                .font(metrics.font(size: 12, weight: .medium))
                .foregroundStyle(theme[isFocused ? .fg : .fgMuted])
                .lineLimit(1)
            if let folder = tab.workingDirectory, !folder.isEmpty {
                Text(verbatim: URL(filePath: folder).lastPathComponent)
                    .font(metrics.monoFont(size: 10, weight: .regular))
                    .foregroundStyle(theme[.fgFaint])
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, metrics.space(.s))
                    .padding(.vertical, metrics.size(1))
                    .background(theme[.panel], in: Capsule())
                    .frame(maxWidth: metrics.size(240), alignment: .leading)
                    .help(Text(verbatim: folder))
            }
        }
        .padding(.horizontal, metrics.space(.s))
        .padding(.vertical, metrics.space(.xxs))
        .background(theme[.bgElevated].opacity(0.92), in: RoundedRectangle(cornerRadius: metrics.radius(.sm)))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.sm)).strokeBorder(theme[.border]))
    }
}
