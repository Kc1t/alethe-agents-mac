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

        let k = max(options.spacing, 1)
        let side = k * Double(max(count, 1)).squareRoot()
        var random = SplitMix64(seed: options.seed)
        var xs = [Double](repeating: 0, count: count)
        var ys = [Double](repeating: 0, count: count)
        for node in 0..<count {
            xs[node] = (random.nextUnit() - 0.5) * side
            ys[node] = (random.nextUnit() - 0.5) * side
        }
        guard count > 1 else {
            return GraphLayout(positions: zip(xs, ys).map { GraphPoint(x: $0, y: $1) }, edges: links, degrees: degrees)
        }

        let cellSize = 2 * k
        let k2 = k * k
        let gravity = 0.9 * k / side
        var temperature = side / 10
        let cooling = temperature / Double(max(options.iterations, 1) + 1)
        var dxs = [Double](repeating: 0, count: count)
        var dys = [Double](repeating: 0, count: count)

        for _ in 0..<max(options.iterations, 0) {
            try Task.checkCancellation()
            for node in 0..<count {
                dxs[node] = 0
                dys[node] = 0
            }

            var cells: [Cell: [Int]] = [:]
            for node in 0..<count { cells[Cell(xs[node], ys[node], cellSize), default: []].append(node) }
            for node in 0..<count {
                let cell = Cell(xs[node], ys[node], cellSize)
                for dx in -1...1 {
                    for dy in -1...1 {
                        guard let others = cells[Cell(x: cell.x + dx, y: cell.y + dy)] else { continue }
                        for other in others where other != node {
                            var ddx = xs[node] - xs[other], ddy = ys[node] - ys[other]
                            var distance2 = ddx * ddx + ddy * ddy
                            if distance2 < 1e-6 {
                                let angle = Double((node &* 31 &+ other) % 360) * .pi / 180
                                ddx = cos(angle) * 0.01
                                ddy = sin(angle) * 0.01
                                distance2 = 1e-4
                            }
                            guard distance2 < cellSize * cellSize else { continue }
                            let factor = k2 / distance2
                            dxs[node] += ddx * factor
                            dys[node] += ddy * factor
                        }
                    }
                }
            }

            for link in links where link.source != link.target {
                let ddx = xs[link.source] - xs[link.target], ddy = ys[link.source] - ys[link.target]
                let distance = (ddx * ddx + ddy * ddy).squareRoot()
                guard distance > 1e-9 else { continue }
                let factor = distance / k
                dxs[link.source] -= ddx * factor
                dys[link.source] -= ddy * factor
                dxs[link.target] += ddx * factor
                dys[link.target] += ddy * factor
            }

            for node in 0..<count {
                let dx = dxs[node] - xs[node] * gravity * k
                let dy = dys[node] - ys[node] * gravity * k
                let length = (dx * dx + dy * dy).squareRoot()
                guard length > 1e-9 else { continue }
                let step = min(length, temperature) / length
                xs[node] += dx * step
                ys[node] += dy * step
            }
            temperature = max(temperature - cooling, k * 0.01)
        }
        return GraphLayout(positions: zip(xs, ys).map { GraphPoint(x: $0, y: $1) }, edges: links, degrees: degrees)
    }

    private struct Cell: Hashable {
        var x: Int
        var y: Int

        init(x: Int, y: Int) {
            self.x = x
            self.y = y
        }

        init(_ px: Double, _ py: Double, _ size: Double) {
            x = Int((px / size).rounded(.down))
            y = Int((py / size).rounded(.down))
        }
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
