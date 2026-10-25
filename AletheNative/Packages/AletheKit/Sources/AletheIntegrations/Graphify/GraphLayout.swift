import Foundation

public struct GraphPoint: Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct GraphRect: Hashable, Sendable {
    public var minX: Double
    public var minY: Double
    public var maxX: Double
    public var maxY: Double

    public var width: Double { maxX - minX }
    public var height: Double { maxY - minY }
    public var center: GraphPoint { GraphPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2) }
}

public struct GraphLayout: Hashable, Sendable {
    public var positions: [GraphPoint]
    public var edges: [Link]
    public var degrees: [Int]

    public struct Link: Hashable, Sendable {
        public var source: Int
        public var target: Int
        public var edge: Int
    }

    public var bounds: GraphRect {
        guard let first = positions.first else { return GraphRect(minX: 0, minY: 0, maxX: 0, maxY: 0) }
        var rect = GraphRect(minX: first.x, minY: first.y, maxX: first.x, maxY: first.y)
        for point in positions.dropFirst() {
            rect.minX = min(rect.minX, point.x)
            rect.minY = min(rect.minY, point.y)
            rect.maxX = max(rect.maxX, point.x)
            rect.maxY = max(rect.maxY, point.y)
        }
        return rect
    }

    public func node(near point: GraphPoint, radius: Double) -> Int? {
        var best: Int?
        var bestDistance = radius * radius
        for (index, position) in positions.enumerated() {
            let dx = position.x - point.x, dy = position.y - point.y
            let distance = dx * dx + dy * dy
            if distance <= bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}

public enum ForceLayout {
    public struct Options: Hashable, Sendable {
        public var seed: UInt64
        public var iterations: Int
        public var spacing: Double

        public init(seed: UInt64 = 1, iterations: Int = 250, spacing: Double = 40) {
            self.seed = seed
            self.iterations = iterations
            self.spacing = spacing
        }
    }

    public static func compute(_ graph: GraphData, options: Options = Options()) throws -> GraphLayout {
        let count = graph.nodes.count
        var index: [String: Int] = [:]
        index.reserveCapacity(count)
        for (offset, node) in graph.nodes.enumerated() where index[node.id] == nil { index[node.id] = offset }

        var links: [GraphLayout.Link] = []
        var degrees = [Int](repeating: 0, count: count)
        for (offset, edge) in graph.edges.enumerated() {
            guard let source = index[edge.source], let target = index[edge.target] else { continue }
            links.append(GraphLayout.Link(source: source, target: target, edge: offset))
            degrees[source] += 1
            if target != source { degrees[target] += 1 }
        }

        var simulation = ForceSimulation(count: count, options: options)
        return try GraphLayout(positions: simulation.positions(links: links), edges: links, degrees: degrees)
    }
}

struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnit() -> Double { Double(next() >> 11) / Double(1 << 53) }
}

extension GraphData {
    public var communityOrdinals: [Int?] {
        var ordinals: [String: Int] = [:]
        return nodes.map { node in
            guard let group = node.group else { return nil }
            if let ordinal = ordinals[group] { return ordinal }
            let ordinal = ordinals.count
            ordinals[group] = ordinal
            return ordinal
        }
    }

    public func search(_ query: String, limit: Int = 50) -> [Int] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        var prefixed: [Int] = [], contained: [Int] = []
        for (index, node) in nodes.enumerated() {
            if node.label.range(of: needle, options: options.union(.anchored)) != nil {
                prefixed.append(index)
            } else if node.label.range(of: needle, options: options) != nil
                        || node.id.range(of: needle, options: options) != nil
                        || node.sourceFile?.range(of: needle, options: options) != nil {
                contained.append(index)
            }
        }
        return Array((prefixed + contained).prefix(max(limit, 0)))
    }
}
