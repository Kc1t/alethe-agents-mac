import AletheDesign
import AletheModel
import AppKit
import SwiftUI

extension ContainerView {
    func layoutSlots(_ slots: [PaneGridGeometry.Slot]) {
        while slotViews.count > slots.count { slotViews.removeLast().removeFromSuperview() }
        while slotViews.count < slots.count {
            let view = NSView()
            view.wantsLayer = true
            let border = CAShapeLayer()
            border.fillColor = nil
            border.lineDashPattern = [4, 4]
            view.layer?.addSublayer(border)
            addSubview(view, positioned: .below, relativeTo: nil)
            slotViews.append(view)
        }
        for (view, slot) in zip(slotViews, slots) {
            let inset = context?.metrics.isWebInterface == true ? context?.metrics.size(4) ?? 4 : 0
            view.frame = slot.frame.insetBy(dx: inset, dy: inset).integral
            let active = reorder?.slot.map { $0.col == slot.col && $0.row == slot.row } == true
            let radius = context.map { $0.metrics.isWebInterface ? $0.metrics.size(4) : $0.metrics.radius(.md) } ?? 8
            view.layer?.cornerRadius = radius
            view.layer?.backgroundColor = active ? context?.theme.nsColor(.accentFaint).cgColor : nil
            if let border = view.layer?.sublayers?.first as? CAShapeLayer {
                border.frame = view.bounds
                border.path = CGPath(roundedRect: view.bounds.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius,
                                     cornerHeight: radius, transform: nil)
                border.strokeColor = context?.theme.nsColor(active ? .accent : .borderSubtle).cgColor
                border.lineWidth = context?.metrics.isWebInterface == true ? context?.metrics.size(1) ?? 1 : (active ? 2 : 1)
            }
            view.setAccessibilityElement(true)
            view.setAccessibilityRole(.group)
            view.setAccessibilityIdentifier("grid.slot.\(slot.col).\(slot.row)")
        }
    }
    func layoutPanes(_ geometry: PaneGridGeometry, animated: Bool) {
        for (index, id) in order.enumerated() {
            guard let view = panes[id], geometry.paneFrames.indices.contains(index) else { continue }
            if reorder?.pane == id { continue }
            let frame = geometry.paneFrames[index]
            if let stack = stacks.first(where: { $0.paneIds.first == id }), let context {
                let m = context.metrics
                stackFrames[stack.id]?.frame = frame
                let head = min(frame.height, m.size(28))
                stackHeaders[stack.id]?.frame = CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: head)
                let body = CGRect(x: frame.minX + m.size(6), y: frame.minY + head + m.size(6),
                                  width: max(0, frame.width - m.size(12)),
                                  height: max(0, frame.height - head - m.size(12)))
                let vertical = stack.kind == "orchestration"
                let columns = vertical ? 1 : 2
                let rows = vertical ? stack.paneIds.count : (stack.paneIds.count + 1) / 2
                let gap = m.size(6)
                let width = max(0, (body.width - CGFloat(columns - 1) * gap) / CGFloat(columns))
                let height = max(0, (body.height - CGFloat(rows - 1) * gap) / CGFloat(rows))
                for (position, member) in stack.paneIds.enumerated() {
                    guard reorder?.pane != member, let child = panes[member], child.superview === self else { continue }
                    let target = CGRect(x: body.minX + CGFloat(position % columns) * (width + gap),
                                        y: body.minY + CGFloat(position / columns) * (height + gap),
                                        width: width, height: height)
                    animator.set(child, frame: target.integral, animated: animated)
                }
            } else {
                animator.set(view, frame: context?.metrics.isWebInterface == true ? frame : frame.integral, animated: animated)
            }
        }
    }
}
