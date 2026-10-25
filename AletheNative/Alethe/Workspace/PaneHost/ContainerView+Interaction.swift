import AletheDesign
import AletheModel
import AppKit
import SwiftUI

extension ContainerView {
    func layoutDividers(_ geometry: PaneGridGeometry) {
        for (kind, view) in dividers where geometry.dividers[kind] == nil {
            view.removeFromSuperview()
            dividers.removeValue(forKey: kind)
        }
        for (kind, rect) in geometry.dividers {
            let view = dividers[kind] ?? makeDivider(kind)
            view.configure(context: context, gridHandle: lastProject?.layout == .grid)
            view.frame = rect
        }
    }

    private func makeDivider(_ kind: PaneGridGeometry.Divider) -> DividerView {
        let axis: DividerView.Axis
        if case .column = kind {
            axis = .vertical
        } else if case .gridColumn = kind {
            axis = .vertical
        } else {
            axis = .horizontal
        }
        let view = DividerView(axis: axis)
        if case .column(let row) = kind {
            view.setAccessibilityIdentifier("pane.divider.column.\(row)")
        } else if case .row(let index) = kind {
            view.setAccessibilityIdentifier("pane.divider.row.\(index)")
        } else if case .gridColumn(let boundary, let segment) = kind {
            view.setAccessibilityIdentifier("pane.divider.gridColumn.\(boundary).\(segment)")
        } else if case .gridRow(let boundary, let segment) = kind {
            view.setAccessibilityIdentifier("pane.divider.gridRow.\(boundary).\(segment)")
        }
        view.onDrag = { [weak self] delta in self?.resize(kind, delta: delta) }
        view.onEnd = { [weak self] in self?.endResize(kind) }
        view.onDoubleClick = { [weak self, weak view] point in
            guard let self, let view, self.lastProject?.layout == .grid,
                  self.context?.metrics.isWebInterface == true else { return }
            let point = self.convert(point, from: view)
            let geometry = self.geometry()
            if let index = geometry.paneFrames.firstIndex(where: { $0.contains(point) }), self.order.indices.contains(index) {
                self.context?.fillFreeSpace(self.order[index])
            }
        }
        addSubview(view)
        dividers[kind] = view
        return view
    }

    private func draggedSizes(_ kind: PaneGridGeometry.Divider, delta: CGFloat) -> [CGFloat] {
        let column: Bool
        let index: Int
        if case .column(let boundary) = kind.track {
            column = true; index = boundary
        } else {
            guard case .row(let boundary) = kind.track else { return [] }
            column = false; index = boundary
        }
        if context?.metrics.isWebInterface == true, lastProject?.layout != .grid,
           resizeBase.indices.contains(index + 1) {
            let total = column ? paneArea.width : paneArea.height
            let mode = lastProject?.layout ?? .auto
            let fractions: (CGFloat, CGFloat)
            if column && mode == .spotlight {
                fractions = (0.25, 0.15)
            } else if column && mode == .sidebar {
                fractions = (0.15, 0.40)
            } else if column && order.count == 2 {
                fractions = (0.15, 0.15)
            } else {
                fractions = (0.10, 0.10)
            }
            let pair = resizeBase[index] + resizeBase[index + 1]
            let leading = min(total * fractions.0, pair / 2)
            let trailing = min(total * fractions.1, pair / 2)
            var result = resizeBase
            result[index] = min(max(resizeBase[index] + delta, leading), pair - trailing)
            result[index + 1] = pair - result[index]
            return result
        }
        if context?.metrics.isWebInterface == true, let grid = lastProject?.effectiveGrid {
            let stored = column ? grid.colSizes : grid.rowSizes
            let count = column ? grid.cols : grid.rows
            let totalFractions = stored?.reduce(0, +) ?? Double(count)
            let extent = column ? paneArea.width : paneArea.height
            return TrackMath.drag(resizeBase, divider: index, delta: delta,
                                  minimum: extent * CGFloat(0.1 / max(0.1, totalFractions)))
        }
        return TrackMath.drag(resizeBase, divider: index, delta: delta,
                              minimum: column ? minimumPane.width : minimumPane.height,
                              rubberBand: { Motion.rubberBand(overshoot: $0, dimension: $1) })
    }

    private func resize(_ kind: PaneGridGeometry.Divider, delta: CGFloat) {
        let geometry = geometry()
        if case .column = kind.track {
            if liveColumns == nil { resizeBase = geometry.columnSizes }
            liveColumns = draggedSizes(kind, delta: delta)
        } else if case .row = kind.track {
            if liveRows == nil { resizeBase = geometry.rowSizes }
            liveRows = draggedSizes(kind, delta: delta)
        }
        resizeDelta = delta
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    private func endResize(_ kind: PaneGridGeometry.Divider) {
        if case .column(let index) = kind.track {
            let settled = context?.metrics.isWebInterface == true ? draggedSizes(kind, delta: resizeDelta)
                : TrackMath.drag(resizeBase, divider: index, delta: resizeDelta, minimum: minimumPane.width)
            weights.columns = TrackMath.weights(settled)
        } else if case .row(let index) = kind.track {
            let settled = context?.metrics.isWebInterface == true ? draggedSizes(kind, delta: resizeDelta)
                : TrackMath.drag(resizeBase, divider: index, delta: resizeDelta, minimum: minimumPane.height)
            weights.rows = TrackMath.weights(settled)
        }
        liveColumns = nil
        liveRows = nil
        resizeDelta = 0
        animateNextLayout = true
        needsLayout = true
        context?.setGridWeights(weights, for: projectID)
    }

    func reorderDrag(_ pane: PaneID, translation: CGSize?) {
        guard let view = panes[pane] else { return }
        guard let translation else {
            endReorder()
            return
        }
        if reorder == nil {
            reorder = Reorder(pane: pane, base: animator.target(of: view))
            addSubview(view, positioned: .above, relativeTo: nil)
            lift(view, true)
        }
        guard var current = reorder else { return }
        view.frame = current.base.offsetBy(dx: translation.width, dy: translation.height)
        let center = CGPoint(x: view.frame.midX, y: view.frame.midY)
        let candidates = context?.metrics.isWebInterface == true ? (lastProject?.visiblePanes.map(\.id) ?? []) : order
        let target = candidates.first { $0 != pane && (panes[$0].map { animator.target(of: $0).contains(center) } ?? false) }
        let slot = target == nil ? geometry().freeSlots.first { $0.frame.contains(center) }.map { ($0.col, $0.row) } : nil
        if target != current.target || slot?.0 != current.slot?.col || slot?.1 != current.slot?.row {
            current.target = target
            current.slot = slot.map { (col: $0.0, row: $0.1) }
            reorder = current
            refreshPanes()
        }
    }

    private func endReorder() {
        guard let finished = reorder, let view = panes[finished.pane] else { return }
        reorder = nil
        lift(view, false)
        addSubview(view, positioned: .below, relativeTo: header)
        let grid = lastProject?.layout == .grid ? lastProject?.effectiveGrid : nil
        if let grid, let destination = finished.target.flatMap({ grid.cells[$0.rawValue] }).map({ ($0.col, $0.row) })
            ?? finished.slot.map({ ($0.col, $0.row) }) {
            animateNextLayout = true
            context?.moveGridCell(finished.pane, toCol: destination.0, row: destination.1)
        } else if let target = finished.target {
            animateNextLayout = true
            context?.swapPanes(finished.pane, target)
        } else {
            animator.set(view, frame: finished.base, animated: true)
        }
        refreshPanes()
    }

    private func refreshPanes() {
        guard let project = lastProject, let context else { return }
        configure(project: project, configuration: Configuration(isSelected: lastSelected, focusedPane: lastFocused, weights: weights,
                  isCollapsed: isCollapsed, isFullscreen: isFullscreen, isolatedPane: isolatedPane,
                  owners: context.metrics.isWebInterface ? owners : [:],
                  showsHeader: context.metrics.isWebInterface ? showsHeader : true),
                  context: context, onHeaderDrag: onHeaderDrag)
    }

    private func lift(_ view: NSView, _ lifted: Bool) {
        guard let layer = view.layer else { return }
        let shadow = context?.theme.shadow(.lg)
        layer.masksToBounds = !lifted
        layer.shadowColor = shadow?.color.nsColor.cgColor
        layer.shadowOpacity = lifted && !(context?.metrics.isWebInterface == true && context?.metrics.style == .clean) ? 1 : 0
        layer.shadowRadius = lifted ? CGFloat(shadow?.blur ?? 0) / 2 : 0
        layer.shadowOffset = CGSize(width: shadow?.x ?? 0, height: -(shadow?.y ?? 0))
        view.alphaValue = lifted ? (context?.metrics.isWebInterface == true ? 0.55 : 0.94) : 1
    }
}
