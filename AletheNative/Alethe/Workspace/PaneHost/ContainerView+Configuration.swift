import AletheDesign
import AletheModel
import AppKit
import SwiftUI

extension ContainerView {
    struct Configuration {
        let isSelected: Bool
        let focusedPane: PaneID?
        let weights: GridWeights
        let isCollapsed: Bool
        let isFullscreen: Bool
        let isolatedPane: PaneID?
        var owners: [PaneID: Project] = [:]
        var showsHeader = true
    }

    func configure(project: Project, configuration: Configuration,
                   context: PaneHostContext, onHeaderDrag: @escaping (CGSize?) -> Void) {
        let isSelected = configuration.isSelected
        let focusedPane = configuration.focusedPane
        let weights = configuration.weights
        let isCollapsed = configuration.isCollapsed
        let isFullscreen = configuration.isFullscreen
        let isolatedPane = configuration.isolatedPane
        let owners = configuration.owners
        let showsHeader = configuration.showsHeader
        self.context = context
        let grouped = showsHeader && project.visiblePanes.count > 1 && isolatedPane == nil
        configureBorder(project: project, grouped: grouped, context: context)
        self.owners = owners
        self.showsHeader = context.metrics.isWebInterface ? grouped : showsHeader
        if let lastProject, lastProject.layout != project.layout { animateNextLayout = true }
        lastProject = project
        lastFocused = focusedPane
        lastSelected = isSelected
        self.isCollapsed = isCollapsed
        self.isFullscreen = isFullscreen
        self.isolatedPane = project.visiblePanes.contains { $0.id == isolatedPane } ? isolatedPane : nil
        self.onHeaderDrag = onHeaderDrag
        if liveColumns == nil, liveRows == nil { self.weights = weights }
        setAccessibilityIdentifier("container.\(project.name)")
        configureHeader(project: project, isSelected: isSelected, isFullscreen: isFullscreen, context: context,
                        onHeaderDrag: onHeaderDrag)

        configurePanes(project: project, focusedPane: focusedPane, owners: owners, context: context)

        if project.visiblePanes.isEmpty {
            let root = context.hosted(ProjectEmptyState(project: project))
            if let emptyState {
                emptyState.rootView = root
            } else {
                let view = NSHostingView(rootView: root)
                addSubview(view)
                emptyState = view
            }
        } else {
            emptyState?.removeFromSuperview()
            emptyState = nil
        }
        needsLayout = true
    }

    private func configureStrip(project: Project, context: PaneHostContext) {
        guard isCollapsed else {
            strip?.removeFromSuperview()
            strip = nil
            return
        }
        let root = context.hosted(CollapsedContainerStrip(project: project, isSelected: lastSelected,
                                                          onExpand: { context.setCollapsed(project.id, false) },
                                                          onDrag: onHeaderDrag))
        if let strip {
            strip.rootView = root
        } else {
            let view = NSHostingView(rootView: root)
            addSubview(view, positioned: .above, relativeTo: nil)
            strip = view
        }
    }

    private func configureBorder(project: Project, grouped: Bool, context: PaneHostContext) {
        if context.metrics.isWebInterface {
            wantsLayer = true
            layer?.cornerRadius = 0
            layer?.borderWidth = grouped ? context.metrics.size(1) : 0
            layer?.borderColor = context.theme.nsColor(.border).cgColor
            layer?.backgroundColor = context.theme.nsColor(.bg).cgColor
            if accentLine.superlayer == nil { layer?.addSublayer(accentLine) }
            accentLine.backgroundColor = context.theme.nsColor(project.color.token).cgColor
            accentLine.opacity = grouped ? 0.65 : 0
            accentLine.zPosition = 10
        } else {
            layer?.borderWidth = 0
            layer?.backgroundColor = nil
            accentLine.removeFromSuperlayer()
        }
    }

    private func configureHeader(project: Project, isSelected: Bool, isFullscreen: Bool,
                                 context: PaneHostContext, onHeaderDrag: @escaping (CGSize?) -> Void) {
        header.rootView = context.hosted(ContainerHeader(
            project: project, isSelected: isSelected, isFullscreen: isFullscreen,
            onLayout: { context.setLayoutMode($0, for: project.id) },
            onDesignLayout: { context.designLayout(for: project.id) },
            onGrid: { action in
                if case .activate(let grid) = action {
                    context.activateGrid(grid, in: project.id)
                } else if case .new = action {
                    context.newGrid(in: project.id)
                } else if case .rename(let grid) = action {
                    context.renameGrid(grid, in: project.id)
                } else if case .delete(let grid) = action {
                    context.deleteGrid(grid, in: project.id)
                }
            },
            onCollapse: { context.setCollapsed(project.id, true) },
            onFullscreen: { context.setFullscreen(isFullscreen ? nil : project.id) },
            onClose: { context.closeContainer(project.id) },
            onDrag: onHeaderDrag))
        configureStrip(project: project, context: context)
    }

    private func configurePanes(project: Project, focusedPane: PaneID?, owners: [PaneID: Project],
                                context: PaneHostContext) {
        let ids = project.visiblePanes.map(\.id)
        for (id, view) in panes where !ids.contains(id) {
            view.removeFromSuperview()
            panes.removeValue(forKey: id)
        }
        stacks = context.metrics.isWebInterface ? (project.paneGroups ?? []).compactMap { group in
            var next = group
            next.paneIds = group.paneIds.filter { ids.contains($0) }
            return next.paneIds.count >= 2 ? next : nil
        } : []
        let nested = Set(stacks.flatMap { $0.paneIds.dropFirst() })
        let nextOrder = ids.filter { !nested.contains($0) }
        if nextOrder != order { animateNextLayout = !order.isEmpty }
        order = nextOrder
        for (id, view) in stackHeaders where !stacks.contains(where: { $0.id == id }) {
            view.removeFromSuperview()
            stackHeaders.removeValue(forKey: id)
            stackFrames.removeValue(forKey: id)?.removeFromSuperview()
        }
        configureStacks(project: project, owners: owners, context: context)
        for pane in project.visiblePanes {
            let view = panes[pane.id] ?? {
                let view = PaneView(paneID: pane.id)
                addSubview(view, positioned: .below, relativeTo: header)
                panes[pane.id] = view
                return view
            }()
            view.configure(pane: pane, project: owners[pane.id] ?? project, focused: pane.id == focusedPane,
                           dropTarget: reorder?.target == pane.id, context: context) { [weak self] translation in
                self?.reorderDrag(pane.id, translation: translation)
            }
        }
    }

    private func configureStacks(project: Project, owners: [PaneID: Project], context: PaneHostContext) {
        for stack in stacks {
            let view = stackHeaders[stack.id] ?? NSHostingView(rootView: AnyView(EmptyView()))
            let border = stackFrames[stack.id] ?? NSView()
            border.wantsLayer = true
            border.layer?.borderWidth = context.metrics.size(1)
            border.layer?.borderColor = context.theme.nsColor(.borderStrong).cgColor
            border.layer?.cornerRadius = context.metrics.style == .clean ? 0 : context.metrics.size(8)
            border.layer?.backgroundColor = context.theme.nsColor(.panel).blended(withFraction: 0.08,
                                                                                 of: context.theme.nsColor(.accent))?.cgColor
            if border.superview == nil { addSubview(border, positioned: .below, relativeTo: nil) }
            stackFrames[stack.id] = border
            view.rootView = context.hosted(PaneStackHeader(orchestration: stack.kind == "orchestration") {
                let owner = stack.paneIds.first.flatMap { owners[$0]?.id } ?? project.id
                context.workspace?.update { $0.updateProject(owner) { $0.ungroupPanes(stack.id) } }
            })
            if view.superview == nil { addSubview(view) }
            stackHeaders[stack.id] = view
        }
    }
}
