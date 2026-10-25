public struct GitGraphEdge: Hashable, Sendable {
    public var from: Int
    public var to: Int
    public var colorIndex: Int

    public init(from: Int, to: Int, colorIndex: Int) {
        self.from = from
        self.to = to
        self.colorIndex = colorIndex
    }
}

public struct GitGraphRow: Hashable, Sendable, Identifiable {
    public var commit: GitCommit
    public var lane: Int
    public var colorIndex: Int
    public var lanesBefore: [String?]
    public var lanesAfter: [String?]
    public var topEdges: [GitGraphEdge]
    public var bottomEdges: [GitGraphEdge]
    public var isLastRow: Bool

    public var id: String { commit.hash }
    public var refs: [GitRef] { commit.refs }
    public var laneCount: Int { max(lanesBefore.count, lanesAfter.count, lane + 1) }
    public var passThroughLanes: [Int] {
        topEdges.filter { $0.from == $0.to && $0.from != lane }.map(\.from)
    }
}

public struct GitGraphLayout: Sendable {
    private var lanes: [String?] = []
    private var laneColors: [Int?] = []
    private var seen: Set<String> = []
    private var colorByIdentity: [String: Int] = [:]
    private var nextColor = 0
    private var branchByHash: [String: String] = [:]

    public init() {}

    public static func layout(_ commits: [GitCommit]) -> [GitGraphRow] {
        var layout = GitGraphLayout()
        return layout.append(commits, hasMore: false)
    }

    public var openLanes: [String?] { lanes }

    public mutating func append(_ commits: [GitCommit], hasMore: Bool) -> [GitGraphRow] {
        for commit in commits where branchByHash[commit.hash] == nil {
            if let name = Self.branchName(commit.refs) { branchByHash[commit.hash] = name }
        }
        var remaining = Set(commits.map(\.hash))
        var rows: [GitGraphRow] = []
        rows.reserveCapacity(commits.count)

        for (index, commit) in commits.enumerated() {
            remaining.remove(commit.hash)
            let context = RowContext(remaining: remaining, hasMore: hasMore,
                                     isLastRow: !hasMore && index == commits.count - 1)
            rows.append(row(commit, context: context))
        }
        if !hasMore {
            lanes = lanes.map { _ in nil }
        }
        return rows
    }

    private struct RowContext {
        let remaining: Set<String>
        let hasMore: Bool
        let isLastRow: Bool
    }

    private mutating func row(_ commit: GitCommit, context: RowContext) -> GitGraphRow {
        seen.insert(commit.hash)
        let lanesBefore = lanes
        let colorsBefore = laneColors
        var lane = lanes.firstIndex(of: commit.hash) ?? -1
        if lane == -1 {
            lane = freeLane()
            laneColors[lane] = color(for: commit.hash)
        }
        let colorIndex = laneColors[lane] ?? color(for: commit.hash)
        let joins = placeParents(of: commit, lane: lane, context: context)
        let lanesAfter: [String?] = context.isLastRow ? lanes.map { _ in nil } : lanes
        let top = topEdges(commit: commit, lane: lane, lanesBefore: lanesBefore, colorsBefore: colorsBefore)
        let bottom = bottomEdges(lane: lane, lanesBefore: lanesBefore, lanesAfter: lanesAfter,
                                 joins: context.isLastRow ? [] : joins)
        return GitGraphRow(
            commit: commit, lane: lane, colorIndex: colorIndex,
            lanesBefore: lanesBefore, lanesAfter: lanesAfter,
            topEdges: top, bottomEdges: bottom, isLastRow: context.isLastRow
        )
    }

    private mutating func placeParents(of commit: GitCommit, lane: Int, context: RowContext) -> [Int] {
        for l in lanes.indices where lanes[l] == commit.hash { lanes[l] = nil }
        var joins: [Int] = []
        if let first = commit.parents.first {
            lanes[lane] = keeps(first, context.remaining, context.hasMore) ? first : nil
            for parent in commit.parents.dropFirst() where keeps(parent, context.remaining, context.hasMore) {
                if let existing = lanes.firstIndex(of: parent) {
                    if existing != lane { joins.append(existing) }
                } else {
                    let l = freeLane()
                    lanes[l] = parent
                    laneColors[l] = color(for: parent)
                }
            }
        } else {
            lanes[lane] = nil
        }
        return joins
    }

    private func topEdges(commit: GitCommit, lane: Int, lanesBefore: [String?],
                          colorsBefore: [Int?]) -> [GitGraphEdge] {
        var top: [GitGraphEdge] = []
        for (l, hash) in lanesBefore.enumerated() {
            guard let hash else { continue }
            let c = colorsBefore[l] ?? 0
            if l == lane || hash == commit.hash {
                top.append(GitGraphEdge(from: l, to: lane, colorIndex: c))
            } else {
                top.append(GitGraphEdge(from: l, to: l, colorIndex: c))
            }
        }
        return top
    }

    private func bottomEdges(lane: Int, lanesBefore: [String?], lanesAfter: [String?], joins: [Int]) -> [GitGraphEdge] {
        var bottom: [GitGraphEdge] = []
        for (l, parent) in lanesAfter.enumerated() {
            guard let parent else { continue }
            let c = laneColors[l] ?? 0
            if l == lane {
                bottom.append(GitGraphEdge(from: lane, to: lane, colorIndex: c))
            } else if l < lanesBefore.count, lanesBefore[l] == parent {
                bottom.append(GitGraphEdge(from: l, to: l, colorIndex: c))
            } else {
                bottom.append(GitGraphEdge(from: lane, to: l, colorIndex: c))
            }
        }
        for l in joins where !bottom.contains(where: { $0.from == lane && $0.to == l }) {
            bottom.append(GitGraphEdge(from: lane, to: l, colorIndex: laneColors[l] ?? 0))
        }
        return bottom
    }

    private func keeps(_ parent: String, _ remaining: Set<String>, _ hasMore: Bool) -> Bool {
        remaining.contains(parent) || (hasMore && !seen.contains(parent))
    }

    private mutating func freeLane() -> Int {
        if let free = lanes.firstIndex(where: { $0 == nil }) { return free }
        lanes.append(nil)
        laneColors.append(nil)
        return lanes.count - 1
    }

    private mutating func color(for hash: String) -> Int {
        let identity = branchByHash[hash] ?? hash
        if let cached = colorByIdentity[identity] { return cached }
        let assigned = nextColor
        nextColor += 1
        colorByIdentity[identity] = assigned
        return assigned
    }

    static func branchName(_ refs: [GitRef]) -> String? {
        var best: String?
        var bestIsLocal = false
        for ref in refs where ref.kind != .tag {
            let raw = ref.name
            guard !raw.isEmpty else { continue }
            let isLocal = !raw.hasPrefix("origin/")
            let name = isLocal ? raw : String(raw.dropFirst("origin/".count))
            if best == nil || (isLocal && !bestIsLocal) {
                best = name
                bestIsLocal = isLocal
            }
        }
        return best
    }
}
