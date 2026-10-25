import AletheDesign
import AletheIntegrations
import AletheModel
import AppKit
import SwiftUI

struct GraphCanvas: View {
    let model: GraphifyPaneModel
    let graph: GraphData
    let layout: GraphLayout
    let onOpenFile: (String) -> Void
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var dragStart: CGSize?
    @State private var magnifyStart: CGFloat?
    @FocusState private var searchFocused: Bool

    private static let palette: [ThemeToken] = [.projectBlue, .projectGreen, .projectOrange, .projectPurple,
                                                .projectPink, .projectTeal, .projectYellow, .projectRed]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                canvas(size: proxy.size)
                    .contentShape(Rectangle())
                    .gesture(panGesture)
                    .simultaneousGesture(magnifyGesture)
                    .simultaneousGesture(SpatialTapGesture().onEnded { select(at: $0.location, size: proxy.size) })
                    .accessibilityElement()
                    .accessibilityLabel(Text(verbatim: format("graphify.stats", graph.nodeCount, graph.edgeCount)))
                    .accessibilityIdentifier("graphify.canvas")
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top) {
                        search(size: proxy.size)
                        Spacer(minLength: 0)
                    }
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        if let node = model.selectedNodeInfo { detail(node, size: proxy.size) }
                        Spacer(minLength: 0)
                        zoomControls(size: proxy.size)
                    }
                }
                .padding(metrics.space(.m))
            }
            .onAppear { fit(proxy.size) }
            .onChange(of: layout) { fit(proxy.size) }
        }
        .clipped()
    }

    private func canvas(size: CGSize) -> some View {
        let query = model.query.trimmingCharacters(in: .whitespaces)
        let matches = query.isEmpty ? nil : Set(model.searchResults)
        let selected = model.selectedNode
        let added = model.addedNodes, addedLinks = model.addedLinks
        let comparing = model.diff != nil
        return Canvas { context, _ in
            let point = { (index: Int) in screen(layout.positions[index], size: size) }
            var edges = Path(), highlighted = Path(), selectedEdges = Path()
            for (index, link) in layout.edges.enumerated() {
                let from = point(link.source), to = point(link.target)
                if selected != nil, link.source == selected || link.target == selected {
                    selectedEdges.move(to: from)
                    selectedEdges.addLine(to: to)
                } else if addedLinks.contains(index) {
                    highlighted.move(to: from)
                    highlighted.addLine(to: to)
                } else {
                    edges.move(to: from)
                    edges.addLine(to: to)
                }
            }
            let dimEdges = matches != nil || comparing
            context.stroke(edges, with: .color(theme[.border].opacity(dimEdges ? 0.4 : 1)), lineWidth: 1)
            context.stroke(highlighted, with: .color(theme[.statusActive]), lineWidth: 1.5)
            context.stroke(selectedEdges, with: .color(theme[.accent]), lineWidth: 1.5)

            let bounds = CGRect(origin: .zero, size: size).insetBy(dx: -20, dy: -20)
            var byColor: [ThemeToken: Path] = [:], dimmed = Path(), rings = Path()
            var labels: [(Int, CGPoint)] = []
            let showAllLabels = scale >= 1.4 && layout.positions.count <= 400
            for index in layout.positions.indices {
                let center = point(index)
                guard bounds.contains(center) else { continue }
                let radius = nodeRadius(index)
                let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                let isMatch = matches?.contains(index) ?? true
                let isAdded = added.contains(index)
                if !isMatch || (comparing && !isAdded && index != selected) {
                    dimmed.addEllipse(in: rect)
                } else {
                    byColor[isAdded ? .statusActive : color(index), default: Path()].addEllipse(in: rect)
                }
                if index == selected || (matches?.contains(index) ?? false) || isAdded {
                    rings.addEllipse(in: rect.insetBy(dx: -2, dy: -2))
                }
                if index == selected || showAllLabels || (matches?.contains(index) ?? false) { labels.append((index, center)) }
            }
            context.fill(dimmed, with: .color(theme[.textQuaternary].opacity(0.5)))
            for token in byColor.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
                if let path = byColor[token] { context.fill(path, with: .color(theme[token])) }
            }
            context.stroke(rings, with: .color(theme[.accentRing]), lineWidth: 1.5)
            for (index, center) in labels.prefix(300) {
                let text = Text(verbatim: graph.nodes[index].label)
                    .font(metrics.font(.caption))
                    .foregroundStyle(theme[index == selected ? .textPrimary : .textSecondary])
                context.draw(text, at: CGPoint(x: center.x, y: center.y + nodeRadius(index) + 7), anchor: .center)
            }
        }
    }

    private func nodeRadius(_ index: Int) -> CGFloat {
        let base = 3.5 + min(CGFloat(layout.degrees[index]), 24) * 0.25
        return base * min(max(scale, 0.6), 2)
    }

    private func color(_ index: Int) -> ThemeToken {
        guard index < model.communities.count, let community = model.communities[index] else { return .accent }
        return Self.palette[community % Self.palette.count]
    }

    private func screen(_ point: GraphPoint, size: CGSize) -> CGPoint {
        let center = layout.bounds.center
        return CGPoint(x: (point.x - center.x) * scale + size.width / 2 + offset.width,
                       y: (point.y - center.y) * scale + size.height / 2 + offset.height)
    }

    private func world(_ point: CGPoint, size: CGSize) -> GraphPoint {
        let center = layout.bounds.center
        return GraphPoint(x: (point.x - size.width / 2 - offset.width) / scale + center.x,
                          y: (point.y - size.height / 2 - offset.height) / scale + center.y)
    }

    private func fit(_ size: CGSize) {
        let bounds = layout.bounds
        guard size.width > 0, size.height > 0 else { return }
        let width = max(bounds.width, 1), height = max(bounds.height, 1)
        scale = min(max(min((size.width - 80) / width, (size.height - 80) / height), 0.05), 4)
        offset = .zero
    }

    private func zoom(by factor: CGFloat) {
        let newScale = min(max(scale * factor, 0.05), 8)
        offset = CGSize(width: offset.width * newScale / scale, height: offset.height * newScale / scale)
        scale = newScale
    }

    private func focus(_ index: Int) {
        model.selectedNode = index
        let center = layout.bounds.center, point = layout.positions[index]
        scale = max(scale, 1.2)
        offset = CGSize(width: -(point.x - center.x) * scale, height: -(point.y - center.y) * scale)
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let start = dragStart ?? offset
                dragStart = start
                offset = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
            }
            .onEnded { _ in dragStart = nil }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let start = magnifyStart ?? scale
                magnifyStart = start
                let target = min(max(start * value.magnification, 0.05), 8)
                zoom(by: target / scale)
            }
            .onEnded { _ in magnifyStart = nil }
    }

    private func select(at location: CGPoint, size: CGSize) {
        searchFocused = false
        let radius = Double(max(nodeRadius(0), 6) + 4) / scale
        model.selectedNode = layout.node(near: world(location, size: size), radius: radius)
    }

    private func search(size: CGSize) -> some View {
        @Bindable var model = model
        let results = model.searchResults
        let query = model.query.trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: metrics.space(.xs)) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme[.textTertiary])
                TextField("graphify.search", text: $model.query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { focus(first) } }
                    .accessibilityIdentifier("graphify.search")
                if !model.query.isEmpty {
                    ContentPaneButton(symbol: "xmark.circle.fill", label: "graphify.clearSearch", id: "graphify.clearSearch") {
                        model.query = ""
                    }
                }
            }
            .font(metrics.font(.footnote))
            .padding(metrics.space(.s))
            if !query.isEmpty {
                Rectangle().fill(theme[.borderSubtle]).frame(height: metrics.size(1))
                if results.isEmpty {
                    Text("graphify.noMatches")
                        .font(metrics.font(.caption))
                        .foregroundStyle(theme[.textTertiary])
                        .padding(metrics.space(.s))
                        .accessibilityIdentifier("graphify.noMatches")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(results, id: \.self) { index in
                                resultRow(index)
                            }
                        }
                    }
                    .frame(maxHeight: min(metrics.size(220), size.height * 0.5))
                }
            }
        }
        .frame(width: min(metrics.size(260), size.width * 0.6))
        .background(RoundedRectangle(cornerRadius: metrics.radius(.md)).fill(theme[.surfaceModal]))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md)).stroke(theme[.border]))
    }

    private func resultRow(_ index: Int) -> some View {
        let node = graph.nodes[index]
        return Button { focus(index) } label: {
            HStack(spacing: metrics.space(.s)) {
                Circle().fill(theme[color(index)]).frame(width: metrics.size(7), height: metrics.size(7))
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: node.label).font(metrics.font(.footnote)).foregroundStyle(theme[.textPrimary]).lineLimit(1)
                    if let file = node.sourceFile, file != node.label {
                        Text(verbatim: file).font(metrics.font(.caption)).foregroundStyle(theme[.textTertiary]).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, metrics.space(.s))
            .padding(.vertical, metrics.space(.xs))
            .background(model.selectedNode == index ? theme[.accentFaint] : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("graphify.result.\(node.id)")
    }

    private func detail(_ node: GraphNode, size: CGSize) -> some View {
        let neighbors = model.neighbors
        return VStack(alignment: .leading, spacing: metrics.space(.xs)) {
            HStack(alignment: .firstTextBaseline) {
                Text(verbatim: node.label)
                    .font(metrics.font(.body).weight(.semibold))
                    .foregroundStyle(theme[.textPrimary])
                    .lineLimit(2)
                    .accessibilityIdentifier("graphify.detail.label")
                Spacer(minLength: 0)
                ContentPaneButton(symbol: "xmark", label: "graphify.clearSelection", id: "graphify.clearSelection") {
                    model.selectedNode = nil
                }
            }
            if let kind = node.kind { row("graphify.detail.kind", kind) }
            if let group = node.group { row("graphify.detail.community", group) }
            if let file = node.sourceFile {
                HStack(spacing: metrics.space(.xs)) {
                    row("graphify.detail.file", file)
                    Button("graphify.openFile") { onOpenFile(file) }
                        .controlSize(.small)
                        .accessibilityIdentifier("graphify.openFile")
                }
            }
            Text(verbatim: format("graphify.detail.connections", neighbors.count))
                .font(metrics.font(.caption))
                .foregroundStyle(theme[.textSecondary])
            if !neighbors.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: metrics.space(.xxs)) {
                        ForEach(neighbors.prefix(50), id: \.self) { index in
                            Button { focus(index) } label: {
                                Text(verbatim: graph.nodes[index].label)
                                    .font(metrics.font(.caption))
                                    .foregroundStyle(theme[.accent])
                                    .lineLimit(1)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: metrics.size(110))
            }
        }
        .padding(metrics.space(.m))
        .frame(width: min(metrics.size(280), size.width * 0.6), alignment: .leading)
        .background(RoundedRectangle(cornerRadius: metrics.radius(.md)).fill(theme[.surfaceModal]))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md)).stroke(theme[.border]))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("graphify.detail")
    }

    private func row(_ title: LocalizedStringKey, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: metrics.space(.xs)) {
            Text(title).foregroundStyle(theme[.textTertiary])
            Text(verbatim: value).foregroundStyle(theme[.textPrimary]).lineLimit(1).truncationMode(.middle)
                .help(Text(verbatim: value))
        }
        .font(metrics.font(.caption))
    }

    private func zoomControls(size: CGSize) -> some View {
        VStack(spacing: metrics.space(.xs)) {
            ContentPaneButton(symbol: "plus", label: "graphify.zoomIn", id: "graphify.zoomIn") { zoom(by: 1.25) }
            ContentPaneButton(symbol: "minus", label: "graphify.zoomOut", id: "graphify.zoomOut") { zoom(by: 0.8) }
            ContentPaneButton(symbol: "arrow.up.left.and.arrow.down.right", label: "graphify.fit", id: "graphify.fit") {
                fit(size)
            }
        }
        .padding(metrics.space(.xs))
        .background(RoundedRectangle(cornerRadius: metrics.radius(.md)).fill(theme[.surfaceModal]))
        .overlay(RoundedRectangle(cornerRadius: metrics.radius(.md)).stroke(theme[.border]))
    }
}
