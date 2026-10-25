import Foundation

public struct GraphNode: Hashable, Sendable, Identifiable {
    public var id: String
    public var label: String
    public var kind: String?
    public var group: String?
    public var sourceFile: String?

    public init(id: String, label: String, kind: String? = nil, group: String? = nil, sourceFile: String? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.group = group
        self.sourceFile = sourceFile
    }
}

public struct GraphEdge: Hashable, Sendable, Identifiable {
    public var id: String
    public var source: String
    public var target: String
    public var label: String?

    public init(id: String, source: String, target: String, label: String? = nil) {
        self.id = id
        self.source = source
        self.target = target
        self.label = label
    }

    public var diffKey: String { GraphIDSets.edgeKey(source, target) }
}

public struct GraphData: Hashable, Sendable {
    public var nodes: [GraphNode]
    public var edges: [GraphEdge]
    public var nodeCount: Int
    public var edgeCount: Int
    public var truncated: Bool

    public init(nodes: [GraphNode], edges: [GraphEdge], nodeCount: Int, edgeCount: Int, truncated: Bool) {
        self.nodes = nodes
        self.edges = edges
        self.nodeCount = nodeCount
        self.edgeCount = edgeCount
        self.truncated = truncated
    }

    public static let visualizationLimit = 3000

    public static func parse(_ data: Data, limit: Int = visualizationLimit) throws -> GraphData {
        let root = try GraphJSON.object(data)
        let nodeValues = root["nodes"] as? [Any] ?? []
        let edgeValues = GraphJSON.edges(in: root)

        var nodes: [GraphNode] = []
        var kept = Set<String>()
        for case let object as [String: Any] in nodeValues.prefix(max(limit, 0)) {
            guard let id = GraphJSON.id(object["id"]) else { continue }
            kept.insert(id)
            nodes.append(GraphNode(
                id: id,
                label: GraphJSON.firstString(object, ["label", "name", "title"]) ?? id,
                kind: GraphJSON.firstString(object, ["type", "kind", "category"]),
                group: GraphJSON.firstString(object, ["group", "community", "module"], numbers: true),
                sourceFile: GraphJSON.firstString(object, ["source_file", "sourceFile", "file", "path"])
            ))
        }

        var edges: [GraphEdge] = []
        for case let object as [String: Any] in edgeValues {
            guard let source = GraphJSON.id(object["source"]), let target = GraphJSON.id(object["target"]),
                  kept.contains(source), kept.contains(target) else { continue }
            edges.append(GraphEdge(
                id: GraphJSON.id(object["id"]) ?? GraphIDSets.edgeKey(source, target),
                source: source,
                target: target,
                label: GraphJSON.firstString(object, ["label", "relation", "type"])
            ))
        }
        return GraphData(nodes: nodes, edges: edges, nodeCount: nodeValues.count, edgeCount: edgeValues.count,
                         truncated: nodeValues.count > limit)
    }
}

public struct GraphIDSets: Hashable, Sendable {
    public var nodes: Set<String>
    public var edges: Set<String>

    public init(nodes: Set<String> = [], edges: Set<String> = []) {
        self.nodes = nodes
        self.edges = edges
    }

    public static func edgeKey(_ source: String, _ target: String) -> String { "\(source)->\(target)" }

    public static func parse(_ data: Data) throws -> GraphIDSets {
        let root = try GraphJSON.object(data)
        var sets = GraphIDSets()
        for case let object as [String: Any] in root["nodes"] as? [Any] ?? [] {
            if let id = GraphJSON.id(object["id"]) { sets.nodes.insert(id) }
        }
        for case let object as [String: Any] in GraphJSON.edges(in: root) {
            if let source = GraphJSON.id(object["source"]), let target = GraphJSON.id(object["target"]) {
                sets.edges.insert(edgeKey(source, target))
            }
        }
        return sets
    }
}

public struct GraphDiff: Hashable, Sendable {
    public var addedNodes: Set<String>
    public var removedNodes: Set<String>
    public var addedEdges: Set<String>
    public var removedEdges: Set<String>

    public init(base: GraphIDSets, compare: GraphIDSets) {
        addedNodes = compare.nodes.subtracting(base.nodes)
        removedNodes = base.nodes.subtracting(compare.nodes)
        addedEdges = compare.edges.subtracting(base.edges)
        removedEdges = base.edges.subtracting(compare.edges)
    }

    public var nodesAdded: Int { addedNodes.count }
    public var nodesRemoved: Int { removedNodes.count }
    public var edgesAdded: Int { addedEdges.count }
    public var edgesRemoved: Int { removedEdges.count }
    public var isEmpty: Bool { addedNodes.isEmpty && removedNodes.isEmpty && addedEdges.isEmpty && removedEdges.isEmpty }
}

public enum GraphifyError: Error, Equatable, Sendable {
    case graphNotFound
    case invalidGraph
    case invalidSnapshotID
    case snapshotNotFound
}

private enum GraphJSON {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw GraphifyError.invalidGraph
        }
        return object
    }

    static func edges(in root: [String: Any]) -> [Any] {
        (root["edges"] as? [Any]) ?? (root["links"] as? [Any]) ?? []
    }

    static func id(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() {
            return number.stringValue
        }
        return nil
    }

    static func firstString(_ object: [String: Any], _ keys: [String], numbers: Bool = false) -> String? {
        for key in keys {
            if let string = object[key] as? String { return string }
            if numbers, let id = id(object[key]) { return id }
        }
        return nil
    }
}
