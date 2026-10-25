import Foundation

public struct ViewPlacements: Hashable, Sendable, Codable {
    public var left: [String]
    public var right: [String]

    public init(left: [String] = [], right: [String] = []) {
        self.left = left
        self.right = right
    }

    public static let empty = ViewPlacements()

    public func arranged(_ tabs: [SidebarTabContribution]) -> (left: [SidebarTabContribution], right: [SidebarTabContribution]) {
        var byID: [String: SidebarTabContribution] = [:]
        for tab in tabs where byID[tab.id] == nil { byID[tab.id] = tab }
        var used = Set<String>()
        func placed(_ ids: [String]) -> [SidebarTabContribution] {
            ids.compactMap { id in
                guard let tab = byID[id], used.insert(id).inserted else { return nil }
                return tab
            }
        }
        var left = placed(self.left)
        var right = placed(self.right)
        for tab in tabs where used.insert(tab.id).inserted {
            if tab.side == .left { left.append(tab) } else { right.append(tab) }
        }
        return (left, right)
    }

    public func side(of id: String, in tabs: [SidebarTabContribution]) -> SidebarSide? {
        let arranged = arranged(tabs)
        if arranged.left.contains(where: { $0.id == id }) { return .left }
        if arranged.right.contains(where: { $0.id == id }) { return .right }
        return nil
    }

    public mutating func move(_ id: String, to side: SidebarSide, at index: Int, in tabs: [SidebarTabContribution]) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        let arranged = arranged(tabs)
        var left = arranged.left.map(\.id).filter { $0 != id }
        var right = arranged.right.map(\.id).filter { $0 != id }
        if side == .left {
            left.insert(id, at: min(max(index, 0), left.count))
        } else {
            right.insert(id, at: min(max(index, 0), right.count))
        }
        let current = Set(tabs.map(\.id))
        self.left = left + self.left.filter { !current.contains($0) }
        self.right = right + self.right.filter { !current.contains($0) }
    }

    public mutating func reset() {
        self = .empty
    }
}
