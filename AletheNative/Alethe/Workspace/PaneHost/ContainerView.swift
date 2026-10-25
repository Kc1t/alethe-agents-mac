import AletheDesign
import AletheModel
import AppKit
import SwiftUI

@MainActor
final class ContainerView: NSView {
    let projectID: ProjectID
    let accentLine = CALayer()
    let header = NSHostingView(rootView: AnyView(EmptyView()))
    var emptyState: NSHostingView<AnyView>?
    var panes: [PaneID: PaneView] = [:]
    var order: [PaneID] = []
    var stacks: [PaneGroup] = []
    var stackFrames: [String: NSView] = [:]
    var stackHeaders: [String: NSHostingView<AnyView>] = [:]
    var dividers: [PaneGridGeometry.Divider: DividerView] = [:]
    var weights = GridWeights()
    var context: PaneHostContext?
    lazy var animator = FrameAnimator(host: self)
    var animateNextLayout = false

    var liveColumns: [CGFloat]?
    var liveRows: [CGFloat]?
    var resizeBase: [CGFloat] = []
    var resizeDelta: CGFloat = 0

    struct Reorder {
        let pane: PaneID
        let base: CGRect
        var target: PaneID?
        var slot: (col: Int, row: Int)?
    }
    var slotViews: [NSView] = []
    var reorder: Reorder?
    var lastProject: Project?
    var lastFocused: PaneID?
    var lastSelected = false
    var isCollapsed = false
    var isFullscreen = false
    var isolatedPane: PaneID?
    var onHeaderDrag: (CGSize?) -> Void = { _ in }
    var strip: NSHostingView<AnyView>?
    var owners: [PaneID: Project] = [:]
    var showsHeader = true
    private var focus: (pane: PaneID, frame: CGRect)?

    init(projectID: ProjectID) {
        self.projectID = projectID
        super.init(frame: .zero)
        addSubview(header)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    var paneViews: [PaneView] {
        context?.metrics.isWebInterface == true ? (lastProject?.visiblePanes.compactMap { panes[$0.id] } ?? [])
            : order.compactMap { panes[$0] }
    }

    private var headerHeight: CGFloat { showsHeader ? context?.metrics.size(context?.metrics.isWebInterface == true ? 32 : 30) ?? 30 : 0 }
    var gap: CGFloat {
        guard let context else { return 6 }
        guard context.metrics.isWebInterface else { return context.metrics.space(.s) }
        return context.metrics.size(lastProject?.layout == .grid || context.metrics.style == .clean ? 0 : 10)
    }
    var minimumPane: CGSize {
        CGSize(width: context?.metrics.size(160) ?? 160, height: context?.metrics.size(100) ?? 100)
    }

    var paneArea: CGRect {
        let edge = context?.metrics.isWebInterface == true && showsHeader ? context?.metrics.size(1) ?? 1 : 0
        let top = showsHeader ? headerHeight + (context?.metrics.isWebInterface == true ? edge : gap) : 0
        return CGRect(x: edge, y: top, width: max(0, bounds.width - edge * 2), height: max(0, bounds.height - top - edge))
    }

    func setFocus(_ pane: PaneID?, frame: CGRect) {
        let next = pane.flatMap { panes[$0] != nil ? ($0, frame) : nil }
        guard next?.0 != focus?.pane || next?.1 != focus?.frame else { return }
        animateNextLayout = true
        focus = next
        needsLayout = true
    }

    func geometry() -> PaneGridGeometry {
        var current = weights
        if let liveColumns { current.columns = TrackMath.weights(liveColumns) }
        if let liveRows { current.rows = TrackMath.weights(liveRows) }
        let mode = lastProject?.layout ?? .auto
        return PaneGridGeometry(count: order.count, in: paneArea, weights: current, gap: gap,
                                handle: max(gap, context?.metrics.size(8) ?? 8), mode: mode,
                                grid: mode == .grid ? lastProject?.effectiveGrid : nil, ids: order.map(\.rawValue),
                                handlesInsideLeadingCell: context?.metrics.isWebInterface == true)
    }

    override func layout() {
        super.layout()
        accentLine.frame = CGRect(x: 0, y: 0, width: bounds.width, height: context?.metrics.size(1) ?? 1)
        strip?.frame = bounds
        header.isHidden = isCollapsed || !showsHeader || focus != nil
        emptyState?.isHidden = isCollapsed
        header.frame = CGRect(x: 0, y: 0, width: bounds.width, height: headerHeight)
        emptyState?.frame = paneArea
        let animated = animateNextLayout
        animateNextLayout = false
        stackHeaders.values.forEach { $0.isHidden = isCollapsed || focus != nil || isolatedPane != nil }
        stackFrames.values.forEach { $0.isHidden = isCollapsed || focus != nil || isolatedPane != nil }
        if isCollapsed {
            panes.values.forEach { $0.isHidden = true }
            dividers.values.forEach { $0.isHidden = true }
            layoutSlots([])
            return
        }
        if let focus {
            for (id, view) in panes {
                view.isHidden = id != focus.pane
                if id == focus.pane, view.superview === self {
                    animator.set(view, frame: focus.frame.integral, animated: animated)
                }
            }
            dividers.values.forEach { $0.isHidden = true }
            layoutSlots([])
            return
        }
        if let isolatedPane {
            for (id, view) in panes {
                view.isHidden = id != isolatedPane
                if id == isolatedPane { animator.set(view, frame: paneArea.integral, animated: animated) }
            }
            dividers.values.forEach { $0.isHidden = true }
            layoutSlots([])
            return
        }
        panes.values.forEach { $0.isHidden = false }
        dividers.values.forEach { $0.isHidden = false }
        let geometry = geometry()
        layoutPanes(geometry, animated: animated)
        layoutDividers(geometry)
        layoutSlots(geometry.freeSlots)
    }


}

struct ProjectEmptyState: View {
    let project: Project
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) var theme
    @Environment(\.metrics) var metrics

    var body: some View {
        Group {
            if metrics.isWebInterface {
                GeometryReader { geometry in
                    VStack(spacing: metrics.size(geometry.size.width <= metrics.size(520) ? 16 : 24)) {
                        Image("AletheMark")
                            .resizable()
                            .renderingMode(.template)
                            .scaledToFit()
                            .foregroundStyle(theme[.fg])
                            .opacity(0.045)
                            .frame(width: metrics.size(geometry.size.width <= metrics.size(520) ? 104 : 190),
                                   height: min(metrics.size(geometry.size.width <= metrics.size(520) ? 104 : 190),
                                               max(0, geometry.size.height - metrics.size(110))))
                            .accessibilityHidden(true)
                        VStack(spacing: metrics.size(2)) {
                            emptyAction("terminal.new", shortcut: "⌘T", id: "terminal.new") {
                                environment.editorRequest = .newTerminal(project.id)
                            }
                            emptyAction("menu.file.addContent", shortcut: "⇧⌘A", id: "workspace.project.addContent") {
                                environment.editorRequest = .addContent(project.id)
                            }
                        }
                        .frame(maxWidth: metrics.size(280))
                    }
                    .frame(maxWidth: min(metrics.size(360), max(0, geometry.size.width - metrics.size(32))))
                    .padding(.horizontal, metrics.size(16))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
            } else {
                VStack(spacing: metrics.space(.l)) {
                    Text("workspace.project.noTerminals")
                        .font(metrics.font(.body))
                        .foregroundStyle(theme[.textSecondary])
                    NewTerminalButton(project: project)
                        .fixedSize()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("workspace.project.empty")
    }

    private func emptyAction(_ title: LocalizedStringKey, shortcut: String, id: String,
                             action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: metrics.size(18)) {
                Text(title).font(metrics.font(size: 12)).lineLimit(1)
                Spacer(minLength: 0)
                Text(verbatim: shortcut)
                    .font(metrics.monoFont(size: 10))
                    .padding(.horizontal, metrics.size(5))
                    .frame(minWidth: metrics.size(18), minHeight: metrics.size(18))
                    .background(theme[.bgElevated], in: RoundedRectangle(cornerRadius: metrics.size(3)))
                    .overlay(RoundedRectangle(cornerRadius: metrics.size(3))
                        .strokeBorder(theme[.border], lineWidth: metrics.size(1)))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, metrics.size(4))
            .padding(.vertical, metrics.size(2))
            .frame(minHeight: metrics.size(26))
            .contentShape(Rectangle())
        }
        .buttonStyle(AletheWorkspaceActionStyle())
        .accessibilityIdentifier(id)
    }
}

extension PaneGridGeometry.Divider {
    enum Track { case column(Int), row(Int) }

    var track: Track {
        if case .column = self { return .column(0) }
        if case .row(let index) = self { return .row(index) }
        if case .gridColumn(let boundary, _) = self { return .column(boundary) }
        guard case .gridRow(let boundary, _) = self else { preconditionFailure("Invalid divider") }
        return .row(boundary)
    }

}
