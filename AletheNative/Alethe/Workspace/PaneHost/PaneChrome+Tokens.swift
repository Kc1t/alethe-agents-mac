import AletheDesign
import AletheModel
import AppKit
import SwiftUI

enum AgentTokens {
    private static let accents: [String: ThemeToken] = [
        "claude": .agentClaude,
        "codex": .agentCodex,
        "opencode": .agentOpencode,
        "cursor": .agentCursor,
        "antigravity": .agentAntigravity,
        "mimo": .agentMimo,
        "freebuff": .agentFreebuff,
        "kiro": .agentKiro,
        "kimi": .agentKimi,
        "grok": .agentGrok,
        "codewhale": .agentCodewhale
    ]

    static func accent(for agent: String) -> ThemeToken {
        accents[agent] ?? .agentShell
    }
}

extension PaneLayoutMode {
    var title: LocalizedStringKey {
        if case .auto = self {
            "workspace.layout.auto"
        } else if case .spotlight = self {
            "workspace.layout.spotlight"
        } else if case .sidebar = self {
            "workspace.layout.sidebar"
        } else {
            "workspace.layout.grid"
        }
    }

    var symbol: String {
        if case .auto = self {
            "square.grid.2x2"
        } else if case .spotlight = self {
            "rectangle.righthalf.inset.filled"
        } else if case .sidebar = self {
            "rectangle.leadinghalf.inset.filled"
        } else {
            "square.grid.3x3"
        }
    }
}

enum GridAction {
    case activate(ProjectGridID?)
    case new
    case rename(ProjectGridID)
    case delete(ProjectGridID)
}

struct GridTarget: Identifiable {
    let grid: ProjectGridID?
    let name: String?
    var id: String { grid?.rawValue ?? "" }

    static func all(for pane: Pane, in project: Project) -> [GridTarget] {
        guard !project.namedGrids.isEmpty else { return [] }
        let targets = [GridTarget(grid: nil, name: nil)] + project.namedGrids.map { GridTarget(grid: $0.id, name: $0.name) }
        return targets.filter { $0.grid != project.shownGridID }
    }
}
