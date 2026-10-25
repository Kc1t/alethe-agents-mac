import Foundation

struct ForceSimulation {
    private let count: Int
    private let options: ForceLayout.Options
    private let k: Double
    private let side: Double
    private var xs: [Double]
    private var ys: [Double]
    private var dxs: [Double]
    private var dys: [Double]

    init(count: Int, options: ForceLayout.Options) {
        self.count = count
        self.options = options
        k = max(options.spacing, 1)
        side = k * Double(max(count, 1)).squareRoot()
        var random = SplitMix64(seed: options.seed)
        xs = [Double](repeating: 0, count: count)
        ys = [Double](repeating: 0, count: count)
        dxs = [Double](repeating: 0, count: count)
        dys = [Double](repeating: 0, count: count)
        for node in 0..<count {
            xs[node] = (random.nextUnit() - 0.5) * side
            ys[node] = (random.nextUnit() - 0.5) * side
        }
    }

    mutating func positions(links: [GraphLayout.Link]) throws -> [GraphPoint] {
        guard count > 1 else { return points }
        let cellSize = 2 * k
        let gravity = 0.9 * k / side
        var temperature = side / 10
        let cooling = temperature / Double(max(options.iterations, 1) + 1)
        for _ in 0..<max(options.iterations, 0) {
            try Task.checkCancellation()
            for node in 0..<count {
                dxs[node] = 0
                dys[node] = 0
            }
            repulse(cellSize: cellSize)
            attract(links)
            move(gravity: gravity, temperature: temperature)
            temperature = max(temperature - cooling, k * 0.01)
        }
        return points
    }

    private var points: [GraphPoint] {
        zip(xs, ys).map { GraphPoint(x: $0, y: $1) }
    }

    private mutating func repulse(cellSize: Double) {
        var cells: [Cell: [Int]] = [:]
        for node in 0..<count { cells[Cell(xs[node], ys[node], cellSize), default: []].append(node) }
        for node in 0..<count {
            let cell = Cell(xs[node], ys[node], cellSize)
            for dx in -1...1 {
                for dy in -1...1 {
                    guard let others = cells[Cell(x: cell.x + dx, y: cell.y + dy)] else { continue }
                    for other in others where other != node {
                        repel(node, from: other, cellSize: cellSize)
                    }
                }
            }
        }
    }

    private mutating func repel(_ node: Int, from other: Int, cellSize: Double) {
        var ddx = xs[node] - xs[other], ddy = ys[node] - ys[other]
        var distance2 = ddx * ddx + ddy * ddy
        if distance2 < 1e-6 {
            let angle = Double((node &* 31 &+ other) % 360) * .pi / 180
            ddx = cos(angle) * 0.01
            ddy = sin(angle) * 0.01
            distance2 = 1e-4
        }
        guard distance2 < cellSize * cellSize else { return }
        let factor = (k * k) / distance2
        dxs[node] += ddx * factor
        dys[node] += ddy * factor
    }

    private mutating func attract(_ links: [GraphLayout.Link]) {
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
    }

    private mutating func move(gravity: Double, temperature: Double) {
        for node in 0..<count {
            let dx = dxs[node] - xs[node] * gravity * k
            let dy = dys[node] - ys[node] * gravity * k
            let length = (dx * dx + dy * dy).squareRoot()
            guard length > 1e-9 else { continue }
            let step = min(length, temperature) / length
            xs[node] += dx * step
            ys[node] += dy * step
        }
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
