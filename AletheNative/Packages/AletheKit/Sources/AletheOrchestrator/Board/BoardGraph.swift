import Foundation
import AletheIntegrations

public enum BoardLayout {
    public static let nodeWidth: Double = 252
    public static let siblingGap: Double = 24
    public static let treeGap: Double = 120
    public static let levelGap: Double = 56
    public static let canvasPadding: Double = 40
    public static let defaultNodeHeight: Double = 76
    public static let elbowRadius: Double = 8
    public static let dotSpacing: Double = 22
    public static let minScale: Double = 0.35
    public static let maxScale: Double = 1.6

    public static func rootNodeID(_ runID: String) -> String { "run:" + runID }
    public static func plannerNodeID(_ plannerID: String) -> String { "planner:" + plannerID }
    public static func mediaNodeID(_ jobID: String) -> String { jobID + ":media" }

    public static func layout(
        runs: [BoardRun],
        heights: [String: Double] = [:],
        plannerID: String? = nil,
        mediaByJobID: [String: MediaItem] = [:]
    ) -> BoardGraph {
        guard !runs.isEmpty else { return .empty }
        var assembly = BoardLayoutAssembly(runs: runs, heights: heights, plannerID: plannerID, mediaByJobID: mediaByJobID)
        return assembly.makeGraph()
    }

    public static func connectorLabelPoint(from start: BoardPoint, to end: BoardPoint) -> BoardPoint {
        BoardPoint(x: (start.x + end.x) / 2, y: start.y + (end.y - start.y) / 2)
    }

    public static func connectorSteps(from start: BoardPoint, to end: BoardPoint) -> [ConnectorStep] {
        let dx = end.x - start.x
        if abs(dx) < 1 { return [.move(start), .vertical(end.y)] }
        let midY = start.y + (end.y - start.y) / 2
        let radius = min(elbowRadius, abs(dx) / 2, abs(end.y - start.y) / 2)
        let step = dx > 0 ? radius : -radius
        return [
            .move(start),
            .vertical(midY - radius),
            .quad(control: BoardPoint(x: start.x, y: midY), to: BoardPoint(x: start.x + step, y: midY)),
            .horizontal(end.x - step),
            .quad(control: BoardPoint(x: end.x, y: midY), to: BoardPoint(x: end.x, y: midY + radius)),
            .vertical(end.y),
        ]
    }

    public static func connectorPath(from start: BoardPoint, to end: BoardPoint) -> String {
        connectorSteps(from: start, to: end).map(\.svg).joined(separator: " ")
    }

    public static func clampScale(_ scale: Double) -> Double {
        min(maxScale, max(minScale, scale))
    }

    public static func fitView(_ graph: BoardSize, in viewport: BoardSize) -> ViewTransform {
        guard graph.width > 0, graph.height > 0, viewport.width > 0, viewport.height > 0 else { return .identity }
        let scale = clampScale(min(1, viewport.width / graph.width, viewport.height / graph.height))
        return ViewTransform(
            scale: scale,
            x: jsRound((viewport.width - graph.width * scale) / 2),
            y: jsRound((viewport.height - graph.height * scale) / 2)
        )
    }

    public static func zoom(_ view: ViewTransform, by factor: Double, at point: BoardPoint) -> ViewTransform {
        let scale = clampScale(view.scale * factor)
        if scale == view.scale { return view }
        let ratio = scale / view.scale
        return ViewTransform(
            scale: scale,
            x: jsRound(point.x - (point.x - view.x) * ratio),
            y: jsRound(point.y - (point.y - view.y) * ratio)
        )
    }

    public static func focusView(_ box: BoardBox, view: ViewTransform, in viewport: BoardSize) -> ViewTransform {
        ViewTransform(
            scale: view.scale,
            x: jsRound(viewport.width / 2 - (box.x + box.width / 2) * view.scale),
            y: jsRound(viewport.height / 2 - (box.y + box.height / 2) * view.scale)
        )
    }
}

public struct BoardPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct BoardSize: Hashable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct BoardBox: Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}

public struct ViewTransform: Hashable, Sendable {
    public var scale: Double
    public var x: Double
    public var y: Double

    public static let identity = ViewTransform(scale: 1, x: 0, y: 0)

    public init(scale: Double, x: Double, y: Double) {
        self.scale = scale
        self.x = x
        self.y = y
    }
}

public enum ConnectorStep: Hashable, Sendable {
    case move(BoardPoint)
    case vertical(Double)
    case horizontal(Double)
    case quad(control: BoardPoint, to: BoardPoint)

    public var svg: String {
        if case .move(let point) = self {
            return "M\(jsNumber(point.x)) \(jsNumber(point.y))"
        } else if case .vertical(let y) = self {
            return "V\(jsNumber(y))"
        } else if case .horizontal(let x) = self {
            return "H\(jsNumber(x))"
        } else {
            guard case .quad(let control, let to) = self else {
                preconditionFailure("Invalid enum case")
            }
            return "Q\(jsNumber(control.x)) \(jsNumber(control.y)) \(jsNumber(to.x)) \(jsNumber(to.y))"
        }
    }
}

public struct GraphNode: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case planner
        case run
        case worker
        case media
    }

    public var id: String
    public var kind: Kind
    public var depth: Int
    public var index: Int
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(id: String, kind: Kind, depth: Int, index: Int, x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.kind = kind
        self.depth = depth
        self.index = index
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var centerX: Double { x + width / 2 }
    public var box: BoardBox { BoardBox(x: x, y: y, width: width, height: height) }
}

public struct GraphEdgeNote: Hashable, Sendable {
    public var verdict: String
    public var agent: String
    public var window: String
    public var used: Double
    public var x: Double
    public var y: Double

    public init(verdict: String, agent: String, window: String, used: Double, x: Double, y: Double) {
        self.verdict = verdict
        self.agent = agent
        self.window = window
        self.used = used
        self.x = x
        self.y = y
    }

    init?(routing: OrderedJSON, at point: BoardPoint) {
        guard let object = routing.objectValue else { return nil }
        self.init(
            verdict: object["verdict"]?.stringValue ?? "",
            agent: object["agent"]?.stringValue ?? "",
            window: object["window"]?.stringValue ?? "",
            used: object["used"]?.doubleValue ?? 0,
            x: point.x,
            y: point.y
        )
    }
}

public struct GraphEdge: Hashable, Sendable, Identifiable {
    public var id: String
    public var from: String
    public var to: String
    public var lane: RunLane
    public var start: BoardPoint
    public var end: BoardPoint
    public var note: GraphEdgeNote?

    public init(id: String, from: String, to: String, lane: RunLane, start: BoardPoint, end: BoardPoint, note: GraphEdgeNote?) {
        self.id = id
        self.from = from
        self.to = to
        self.lane = lane
        self.start = start
        self.end = end
        self.note = note
    }

    public var steps: [ConnectorStep] { BoardLayout.connectorSteps(from: start, to: end) }
    public var path: String { BoardLayout.connectorPath(from: start, to: end) }
}

public struct GraphTree: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var lane: RunLane
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(id: String, label: String, lane: RunLane, x: Double, y: Double, width: Double, height: Double) {
        self.id = id
        self.label = label
        self.lane = lane
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var box: BoardBox { BoardBox(x: x, y: y, width: width, height: height) }
}

public struct BoardGraph: Hashable, Sendable {
    public var planner: GraphNode?
    public var trees: [GraphTree]
    public var roots: [GraphNode]
    public var workers: [GraphNode]
    public var media: [GraphNode]
    public var edges: [GraphEdge]
    public var width: Double
    public var height: Double

    public static let empty = BoardGraph(planner: nil, trees: [], roots: [], workers: [], media: [], edges: [], width: 0, height: 0)

    public init(
        planner: GraphNode?,
        trees: [GraphTree],
        roots: [GraphNode],
        workers: [GraphNode],
        media: [GraphNode],
        edges: [GraphEdge],
        width: Double,
        height: Double
    ) {
        self.planner = planner
        self.trees = trees
        self.roots = roots
        self.workers = workers
        self.media = media
        self.edges = edges
        self.width = width
        self.height = height
    }

    public var size: BoardSize { BoardSize(width: width, height: height) }

    public var nodes: [GraphNode] { (planner.map { [$0] } ?? []) + roots + workers + media }
}
