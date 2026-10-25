import Foundation

public enum SidebarDragPayload: Equatable, Sendable {
    case project(ProjectID), group(GroupID), pane(PaneID)
}

public enum SidebarWebDropTarget: Hashable, Sendable {
    case project(ProjectID)
    case terminals(ProjectID)
    case groupHeader(GroupID)
    case groupBody(GroupID)
    case ungrouped
}

public struct SidebarDropRegion: Equatable, Sendable {
    public let target: SidebarWebDropTarget
    public let hit: CGRect
    public let visual: CGRect

    public init(target: SidebarWebDropTarget, hit: CGRect, visual: CGRect) {
        self.target = target
        self.hit = hit
        self.visual = visual
    }
}

public struct SidebarDropPlan: Equatable, Sendable {
    public enum Action: Equatable, Sendable {
        case place(SidebarChild, container: GroupID?, before: SidebarChild?)
        case movePane(PaneID, to: ProjectID)
        case addFolders(container: GroupID?)
    }

    public enum Mark: Equatable, Sendable {
        case line(rect: CGRect, edge: SidebarDropEdge, indent: CGFloat)
        case box(CGRect)
    }

    public let action: Action
    public let mark: Mark
    public let fill: SidebarWebDropTarget?

    public init(action: Action, mark: Mark, fill: SidebarWebDropTarget? = nil) {
        self.action = action
        self.mark = mark
        self.fill = fill
    }
}

public enum SidebarWebDropRules {
    public enum Source: Equatable, Sendable {
        case item(SidebarDragPayload)
        case files
    }

    public static func plan(_ source: Source, regions: [SidebarDropRegion], at point: CGPoint, width: CGFloat,
                            in document: WorkspaceDocument) -> SidebarDropPlan? {
        guard point.x >= 0, point.x <= width else { return nil }
        let rows = regions.filter { $0.hit.height > 0 }.sorted { $0.hit.minY < $1.hit.minY }
        guard let first = rows.first, let lowest = rows.map(\.hit.maxY).max() else { return nil }
        let layout = Layout(rows: rows, document: document)
        let y = max(point.y, first.hit.minY)
        if y >= lowest { return layout.blank(source) }
        let containing = rows.filter { $0.hit.minY <= y && y < $0.hit.maxY }.min { $0.hit.height < $1.hit.height }
        guard let row = containing ?? rows.min(by: { layout.distance(from: y, to: $0) < layout.distance(from: y, to: $1) })
        else { return nil }
        if case .files = source { return layout.files(row) }
        else if case .item(.pane(let id)) = source { return layout.pane(id, row) }
        else if case .item(.project(let id)) = source { return layout.project(id, row, y: y) }
        else {
            guard case .item(.group(let id)) = source else {
                preconditionFailure("Unexpected enum case")
            }
            return layout.group(id, row, y: y)
        }
    }

    private struct Layout {
        let rows: [SidebarDropRegion]
        let document: WorkspaceDocument
        var projects: [ProjectID: SidebarDropRegion] = [:]
        var terminals: [ProjectID: [SidebarDropRegion]] = [:]
        var headers: [GroupID: SidebarDropRegion] = [:]
        var placeholders: [GroupID: SidebarDropRegion] = [:]

        init(rows: [SidebarDropRegion], document: WorkspaceDocument) {
            self.rows = rows
            self.document = document
            for row in rows {
                if case .project(let id) = row.target { projects[id] = row }
                else if case .terminals(let id) = row.target { terminals[id, default: []].append(row) }
                else if case .groupHeader(let id) = row.target { headers[id] = row }
                else if case .groupBody(let id) = row.target { placeholders[id] = row }
                else {

                }
            }
        }

        func distance(from y: CGFloat, to row: SidebarDropRegion) -> CGFloat {
            y < row.hit.minY ? row.hit.minY - y : y >= row.hit.maxY ? y - row.hit.maxY : 0
        }

        func container(of project: ProjectID) -> GroupID? {
            if case .group(let id)? = document.location(of: project) { return id }
            return nil
        }

        func node(of project: ProjectID) -> CGRect? {
            var rect = projects[project]?.visual
            for terminal in terminals[project] ?? [] { rect = rect.map { $0.union(terminal.visual) } ?? terminal.visual }
            return rect
        }

        func region(of child: SidebarChild) -> SidebarDropRegion? {
            if case .project(let id) = child { return projects[id] } else {
                guard case .group(let id) = child else {
                    preconditionFailure("Unexpected enum case")
                }
                return headers[id]
            }
        }

        func next(after child: SidebarChild, in container: GroupID?, skipping item: SidebarChild) -> SidebarChild? {
            let list = document.sidebarChildren(of: container).filter { $0 != item }
            guard let index = list.firstIndex(of: child), index + 1 < list.count else { return nil }
            return list[index + 1]
        }

        func fraction(_ y: CGFloat, in row: SidebarDropRegion) -> CGFloat {
            guard row.visual.height > 0 else { return 0 }
            return min(max((y - row.visual.minY) / row.visual.height, 0), 1)
        }

        func line(_ rect: CGRect, _ edge: SidebarDropEdge, indent: CGFloat = 0) -> SidebarDropPlan.Mark {
            .line(rect: rect, edge: edge, indent: indent)
        }

        func place(_ item: SidebarChild, in container: GroupID?, before: SidebarChild?) -> SidebarDropPlan.Action {
            .place(item, container: container, before: before)
        }

        func topLevelEnd(_ item: SidebarChild) -> SidebarDropPlan {
            let ungrouped = projects.filter { container(of: $0.key) == nil }.values.min { $0.visual.minY < $1.visual.minY }
            let mark: SidebarDropPlan.Mark
            if case .group = item, let ungrouped { mark = line(ungrouped.visual, .before) }
            else if let last = rows.max(by: { $0.hit.maxY < $1.hit.maxY }) {
                mark = line(last.visual, .after)
            } else {
                mark = .box(.zero)
            }
            return SidebarDropPlan(action: place(item, in: nil, before: nil), mark: mark)
        }

        func beside(_ row: SidebarDropRegion, child: SidebarChild, container: GroupID?, item: SidebarChild, y: CGFloat)
            -> SidebarDropPlan {
            if y < row.visual.midY { return SidebarDropPlan(action: place(item, in: container, before: child),
                mark: line(row.visual, .before)) }
            var rect = row.visual
            if case .project(let id) = child, let node = node(of: id) { rect = node }
            return SidebarDropPlan(action: place(item, in: container, before: next(after: child, in: container, skipping: item)),
                                   mark: line(rect, .after))
        }

        func afterNode(of project: ProjectID, item: SidebarChild, fallback: CGRect) -> SidebarDropPlan {
            let container = container(of: project)
            return SidebarDropPlan(
                action: place(item, in: container, before: next(after: .project(project), in: container, skipping: item)),
                mark: line(node(of: project) ?? fallback, .after))
        }

        func into(group id: GroupID, item: SidebarChild, row: SidebarDropRegion, fill: SidebarWebDropTarget) -> SidebarDropPlan {
            SidebarDropPlan(action: place(item, in: id, before: nil), mark: .box(row.visual), fill: fill)
        }

        func blank(_ source: Source) -> SidebarDropPlan? {
            if case .item(.project(let id)) = source { return topLevelEnd(.project(id)) }
            else if case .item(.group(let id)) = source { return topLevelEnd(.group(id)) }
            else if case .item(.pane) = source { return nil }
            else {
                guard let last = rows.max(by: { $0.hit.maxY < $1.hit.maxY }) else { return nil }
                return SidebarDropPlan(action: .addFolders(container: nil), mark: line(last.visual, .after))
            }
        }

        func project(_ id: ProjectID, _ row: SidebarDropRegion, y: CGFloat) -> SidebarDropPlan? {
            let item = SidebarChild.project(id)
            if case .project(let other) = row.target {
                guard other != id else { return nil }
                return beside(row, child: .project(other), container: container(of: other), item: item, y: y)
            } else if case .terminals(let other) = row.target {
                guard other != id else { return nil }
                return afterNode(of: other, item: item, fallback: row.visual)
            } else if case .groupHeader(let target) = row.target {
                guard let parent = document.group(target)?.parentID else {
                    return y >= row.visual.minY ? into(group: target, item: item, row: row, fill: .groupHeader(target)) : nil
                }
                if fraction(y, in: row) < 0.3 { return SidebarDropPlan(action: place(item, in: parent,
                    before: .group(target)), mark: line(row.visual, .before)) }
                return into(group: target, item: item, row: row, fill: .groupHeader(target))
            }
            else if case .groupBody(let target) = row.target { return SidebarDropPlan(action: place(item, in: target,
                before: nil), mark: .box(row.hit), fill: .groupBody(target)) }
            else { return SidebarDropPlan(action: place(item, in: nil, before: nil), mark: .box(row.hit), fill: .ungrouped) }
        }

        func group(_ id: GroupID, _ row: SidebarDropRegion, y: CGFloat) -> SidebarDropPlan? {
            let item = SidebarChild.group(id)
            if case .project(let other) = row.target {
                if let parent = container(of: other), document.isGroup(parent, inside: id) { return nil }
                guard let parent = container(of: other) else { return topLevelEnd(item) }
                return beside(row, child: .project(other), container: parent, item: item, y: y)
            } else if case .terminals(let other) = row.target {
                if let parent = container(of: other), document.isGroup(parent, inside: id) { return nil }
                guard container(of: other) != nil else { return topLevelEnd(item) }
                return afterNode(of: other, item: item, fallback: row.visual)
            } else if case .groupHeader(let target) = row.target {
                guard !document.isGroup(target, inside: id), let group = document.group(target) else { return nil }
                return header(group, row, item: item, y: y)
            } else if case .groupBody(let target) = row.target {
                guard !document.isGroup(target, inside: id) else { return nil }
                return SidebarDropPlan(action: place(item, in: target, before: nil), mark: .box(row.hit), fill: .groupBody(target))
            } else { return SidebarDropPlan(action: place(item, in: nil, before: nil), mark: .box(row.hit), fill: .ungrouped) }
        }

        func header(_ target: ProjectGroup, _ row: SidebarDropRegion, item: SidebarChild, y: CGFloat) -> SidebarDropPlan {
            let parent = target.parentID
            let t = fraction(y, in: row)
            let before = SidebarDropPlan(action: place(item, in: parent, before: .group(target.id)), mark: line(row.visual, .before))
            if target.isCollapsed {
                if t < 0.3 { return before }
                if t > 0.7 {
                    return SidebarDropPlan(
                        action: place(item, in: parent, before: next(after: .group(target.id), in: parent, skipping: item)),
                        mark: line(row.visual, .after))
                }
                return into(group: target.id, item: item, row: row, fill: .groupHeader(target.id))
            }
            if t < 0.5 { return before }
            let first = document.sidebarChildren(of: target.id).first { $0 != item }
            let childX = first.flatMap { region(of: $0) }?.visual.minX ?? placeholders[target.id]?.visual.minX ?? row.visual.minX
            return SidebarDropPlan(action: place(item, in: target.id, before: first),
                                   mark: line(row.visual, .after, indent: max(0, childX - row.visual.minX)))
        }

        func pane(_ id: PaneID, _ row: SidebarDropRegion) -> SidebarDropPlan? {
            if case .project(let other) = row.target {
                guard document.pane(id)?.project.id != other else { return nil }
                let rect = node(of: other) ?? row.visual
                return SidebarDropPlan(action: .movePane(id, to: other), mark: .box(rect), fill: .project(other))
            } else if case .terminals(let other) = row.target {
                guard document.pane(id)?.project.id != other else { return nil }
                let rect = node(of: other) ?? row.visual
                return SidebarDropPlan(action: .movePane(id, to: other), mark: .box(rect), fill: .project(other))
            } else { return nil }
        }

        func files(_ row: SidebarDropRegion) -> SidebarDropPlan? {
            if case .project(let other) = row.target {
                return SidebarDropPlan(action: .addFolders(container: container(of: other)),
                mark: .box(node(of: other) ?? row.visual), fill: .project(other))
            } else if case .terminals(let other) = row.target {
                return SidebarDropPlan(action: .addFolders(container: container(of: other)),
                mark: .box(node(of: other) ?? row.visual), fill: .project(other))
            }
            else
                if case .groupHeader(let target) = row.target { return SidebarDropPlan(action: .addFolders(container: target),
                mark: .box(row.visual), fill: .groupHeader(target)) }
            else
                if case .groupBody(let target) = row.target { return SidebarDropPlan(action: .addFolders(container: target),
                mark: .box(row.hit), fill: .groupBody(target)) }
            else { return SidebarDropPlan(action: .addFolders(container: nil), mark: .box(row.hit), fill: .ungrouped) }
        }
    }
}
