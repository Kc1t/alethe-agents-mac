import AletheAgents
import AletheDesign
import AletheModel
import AletheTerminal
import AppKit
import Observation
import SwiftUI

extension PaneView {
    func configureHeader(pane: Pane, project: Project, focused: Bool, dropTarget: Bool,
                                 context: PaneHostContext, onDrag: @escaping (CGSize?) -> Void) {
        let environment = context.environment
        guard let tab = pane.activeTab else { return }
        let isIsolated = context.workspace?.document.workspace.isolatedPaneID == pane.id
        header.rootView = context.hosted(PaneHeader(
            tab: tab, isFocused: focused, isLaneVisible: pane.isLaneVisible, canHideLane: pane.tabs.count == 1,
            isIsolated: isIsolated,
            onClose: { context.closePane(pane.id) },
            onNewSubTab: { context.newSubTab(in: pane.id) },
            onToggleLane: { context.setLaneVisible(!pane.isLaneVisible, for: pane.id) },
            onToggleIsolation: { context.isolate(isIsolated ? nil : pane.id) },
            onFillFreeSpace: canFill(pane: pane, project: project) ? { context.fillFreeSpace(pane.id) } : nil,
            gridTargets: GridTarget.all(for: pane, in: project),
            onMoveToGrid: { context.movePane(pane.id, toGrid: $0) },
            isInFocusMode: context.environment.focusModePaneID == pane.id,
            onToggleFocus: { context.setFocusMode(context.environment.focusModePaneID == pane.id ? nil : pane.id) },
            onDisable: { context.setDisabled(pane.id, true) },
            isRemoteShared: pane.isRemoteShared,
            onToggleRemoteShared: { environment.remoteControl.setShared(pane.id, !pane.isRemoteShared) },
            onSessionCost: tab.sessionID == nil ? nil : { context.environment.editorRequest = .sessionCost(tab.id) },
            onHandoff: Handoff.supports(AgentKind(rawValue: tab.agent)) ? { context.environment.editorRequest = .handoff(tab.id) } : nil,
            onDrag: onDrag,
            topbarPinned: webTopbarPinned,
            canDragPane: project.visiblePanes.count > 1 && environment.focusModePaneID != pane.id,
            onToggleTopbar: { [weak self] in
                guard let self else { return }
                UserDefaults.standard.set(self.webTopbarPinned, forKey: "pane.web.unpinned." + pane.id.rawValue)
                self.configure(pane: pane, project: project, focused: focused, dropTarget: dropTarget, context: context, onDrag: onDrag)
            }))
    }
}
