import Foundation

struct BoardLayoutAssembly {
    let runs: [BoardRun]
    let heights: [String: Double]
    let plannerID: String?
    let mediaByJobID: [String: MediaItem]
    var spans: [Double] = []
    var lefts: [Double] = []
    var cursor = BoardLayout.canvasPadding
    var plannerHeight: Double = 0
    var workerTop: Double = 0
    var roots: [GraphNode] = []
    var workers: [GraphNode] = []
    var media: [GraphNode] = []
    var trees: [GraphTree] = []
    var runEdges: [GraphEdge] = []

    func height(_ id: String) -> Double {
        if let measured = heights[id], measured > 0 { return jsRound(measured) }
        return BoardLayout.defaultNodeHeight
    }

    mutating func makeGraph() -> BoardGraph {
        prepareRoots()
        for (index, run) in runs.enumerated() { addRun(run, index: index) }
        return assembledGraph()
    }

    private mutating func prepareRoots() {
        spans = runs.map { run -> Double in
            let count = Double(run.jobs.count)
            return run.jobs.isEmpty ? BoardLayout.nodeWidth : count * BoardLayout.nodeWidth + (count - 1) * BoardLayout.siblingGap
        }
        for span in spans {
            lefts.append(cursor)
            cursor += span + BoardLayout.treeGap
        }

        plannerHeight = plannerID.map { height(BoardLayout.plannerNodeID($0)) } ?? 0
        let runTop = BoardLayout.canvasPadding + (plannerID != nil ? plannerHeight + BoardLayout.levelGap : 0)
        let runHeights = runs.map { height(BoardLayout.rootNodeID($0.id)) }
        workerTop = runTop + (runHeights.max() ?? 0) + BoardLayout.levelGap

        roots = runs.indices.map { index in
            GraphNode(
                id: BoardLayout.rootNodeID(runs[index].id),
                kind: .run,
                depth: plannerID != nil ? 1 : 0,
                index: index,
                x: jsRound(lefts[index] + (spans[index] - BoardLayout.nodeWidth) / 2),
                y: runTop,
                width: BoardLayout.nodeWidth,
                height: runHeights[index]
            )
        }
    }

    private mutating func addRun(_ run: BoardRun, index: Int) {
        let root = roots[index]
        var bottom = root.y + root.height

        for (column, job) in run.jobs.enumerated() {
            addWorker(job, root: root, left: lefts[index], column: column, bottom: &bottom)
        }

        trees.append(GraphTree(
            id: run.id,
            label: run.label,
            lane: run.state,
            x: lefts[index],
            y: root.y,
            width: spans[index],
            height: bottom - root.y
        ))
    }

    private mutating func addWorker(
        _ job: JobSnapshot, root: GraphNode, left: Double, column: Int, bottom: inout Double
    ) {
        let node = GraphNode(
            id: job.id,
            kind: .worker,
            depth: root.depth + 1,
            index: column,
            x: left + Double(column) * (BoardLayout.nodeWidth + BoardLayout.siblingGap),
            y: workerTop,
            width: BoardLayout.nodeWidth,
            height: height(job.id)
        )
        workers.append(node)
        bottom = max(bottom, node.y + node.height)
        let lane = RunLane(job.status)
        let start = BoardPoint(x: root.centerX, y: root.y + root.height)
        let end = BoardPoint(x: node.centerX, y: node.y)
        let label = BoardLayout.connectorLabelPoint(from: start, to: end)
        runEdges.append(GraphEdge(
            id: "\(root.id)->\(node.id)",
            from: root.id,
            to: node.id,
            lane: lane,
            start: start,
            end: end,
            note: job.routing.flatMap { GraphEdgeNote(routing: $0, at: label) }
        ))

        addMedia(job, node: node, lane: lane, column: column, bottom: &bottom)
    }

    private mutating func addMedia(
        _ job: JobSnapshot, node: GraphNode, lane: RunLane, column: Int, bottom: inout Double
    ) {
        guard mediaByJobID[job.id] != nil else { return }
        let mediaID = BoardLayout.mediaNodeID(job.id)
        let card = GraphNode(
            id: mediaID,
            kind: .media,
            depth: node.depth + 1,
            index: column,
            x: node.x,
            y: node.y + node.height + BoardLayout.levelGap,
            width: BoardLayout.nodeWidth,
            height: height(mediaID)
        )
        media.append(card)
        bottom = max(bottom, card.y + card.height)
        runEdges.append(GraphEdge(
            id: "\(node.id)->\(card.id)",
            from: node.id,
            to: card.id,
            lane: lane,
            start: BoardPoint(x: node.centerX, y: node.y + node.height),
            end: BoardPoint(x: card.centerX, y: card.y),
            note: nil
        ))
    }

    private func assembledGraph() -> BoardGraph {
        var planner: GraphNode?
        var plannerEdges: [GraphEdge] = []
        if let plannerID, let first = roots.first, let last = roots.last {
            let node = GraphNode(
                id: BoardLayout.plannerNodeID(plannerID),
                kind: .planner,
                depth: 0,
                index: 0,
                x: jsRound((first.centerX + last.centerX) / 2 - BoardLayout.nodeWidth / 2),
                y: BoardLayout.canvasPadding,
                width: BoardLayout.nodeWidth,
                height: plannerHeight
            )
            planner = node
            for (index, root) in roots.enumerated() {
                plannerEdges.append(GraphEdge(
                    id: "\(node.id)->\(root.id)",
                    from: node.id,
                    to: root.id,
                    lane: runs[index].state,
                    start: BoardPoint(x: node.centerX, y: node.y + node.height),
                    end: BoardPoint(x: root.centerX, y: root.y),
                    note: nil
                ))
            }
        }

        return BoardGraph(
            planner: planner,
            trees: trees,
            roots: roots,
            workers: workers,
            media: media,
            edges: plannerEdges + runEdges,
            width: cursor - BoardLayout.treeGap + BoardLayout.canvasPadding,
            height: (trees.map { $0.y + $0.height }.max() ?? 0) + BoardLayout.canvasPadding
        )
    }
}
