import AletheFoundation
import Foundation

public enum ProjectColor: String, Codable, CaseIterable, Sendable {
    case orange, pink, purple, blue, teal, green, yellow, red, gray, black
}

public struct ProjectGroup: Codable, Hashable, Sendable, Identifiable {
    public var id: GroupID
    public var name: String
    public var iconUrl: String?
    public var color: ProjectColor?
    public var parentID: GroupID?
    public var projectIDs: [ProjectID]
    public var childOrder: [String]?
    public var isCollapsed: Bool
    public var suspended: Bool?
    public var layoutMode: PaneLayoutMode?
    public var gridLayout: CustomGrid?
    public var gridLayoutHistory: [CustomGridHistoryEntry]?

    public init(id: GroupID = .make(), name: String, color: ProjectColor? = nil, parentID: GroupID? = nil,
                projectIDs: [ProjectID] = [], isCollapsed: Bool = false) {
        self.id = id
        self.name = name
        self.color = color
        self.parentID = parentID
        self.projectIDs = projectIDs
        self.isCollapsed = isCollapsed
    }
}

public struct PaneTab: Codable, Hashable, Sendable, Identifiable {
    public var id: TabID
    public var agent: String
    public var title: String?
    public var workingDirectory: String?
    public var sessionID: String?
    public var unrestricted: Bool
    public var extraArguments: [String]
    public var initialPrompt: String?
    public var createdAt: Date
    public var worktreeAgentID: String?
    public var worktreeBranch: String?
    public var useRouter9: Bool?

    public init(id: TabID = .make(), agent: String, title: String? = nil, workingDirectory: String? = nil,
                sessionID: String? = nil, unrestricted: Bool = false, extraArguments: [String] = [],
                initialPrompt: String? = nil, createdAt: Date = Date(),
                worktreeAgentID: String? = nil, worktreeBranch: String? = nil) {
        self.id = id
        self.agent = agent
        self.title = title
        self.workingDirectory = workingDirectory
        self.sessionID = sessionID
        self.unrestricted = unrestricted
        self.extraArguments = extraArguments
        self.initialPrompt = initialPrompt
        self.createdAt = createdAt
        self.worktreeAgentID = worktreeAgentID
        self.worktreeBranch = worktreeBranch
    }
}

public struct Pane: Codable, Hashable, Sendable, Identifiable {
    public var id: PaneID
    public var content: PaneContent
    public var tabs: [PaneTab]
    public var activeTabID: TabID?
    public var laneVisible: Bool?
    public var gridID: ProjectGridID?
    public var disabled: Bool?
    public var remoteShared: Bool?

    public init(id: PaneID = .make(), content: PaneContent = .terminal, tabs: [PaneTab] = [],
                activeTabID: TabID? = nil, laneVisible: Bool? = nil) {
        self.id = id
        self.content = content
        self.tabs = content.isTerminal ? tabs : []
        self.activeTabID = activeTabID ?? tabs.first?.id
        self.laneVisible = laneVisible
    }

    public var activeTab: PaneTab? {
        tabs.first { $0.id == activeTabID } ?? tabs.first
    }

    public var isLaneVisible: Bool { content.isTerminal && (tabs.count > 1 || laneVisible == true) }

    public var isRemoteShared: Bool { content.isTerminal && remoteShared == true }
}

public enum ProjectWorktreeMode: String, Codable, CaseIterable, Sendable {
    case gitWorktree
    case localCopy
}

public struct Project: Codable, Hashable, Sendable, Identifiable {
    public var id: ProjectID
    public var name: String
    public var iconUrl: String?
    public var hidden: Bool?
    public var archived: Bool?
    public var webConfiguration: JSONObject?
    public var color: ProjectColor
    public var folder: String
    public var panes: [Pane]
    public var paneGroups: [PaneGroup]?
    public var createdAt: Date
    public var layoutMode: PaneLayoutMode?
    public var gridLayout: CustomGrid?
    public var gridLayoutHistory: [CustomGridHistoryEntry]?
    public var grids: [ProjectGrid]?
    public var activeGridID: ProjectGridID?
    public var autoWorktree: Bool?
    public var worktreeMode: ProjectWorktreeMode?
    public var githubURL: String?
    public var graphifyEnabled: Bool?
    public var validationCommands: [String]?
    public var healthCheckCommand: String?
    public var healthCheckPath: String?
    public var conflictAgentProvider: String?
    public var conflictAgentModel: String?
    public var gsdWatcherEnabled: Bool?


    public init(id: ProjectID = .make(), name: String, color: ProjectColor = .blue, folder: String,
                panes: [Pane] = [], createdAt: Date = Date(), layoutMode: PaneLayoutMode? = nil) {
        self.id = id
        self.name = name
        self.color = color
        self.folder = folder
        self.panes = panes
        self.createdAt = createdAt
        self.layoutMode = layoutMode
    }

    public var layout: PaneLayoutMode { activeArrangement.layoutMode ?? .auto }

    public var usesAutoWorktree: Bool { autoWorktree ?? false }
    public var effectiveWorktreeMode: ProjectWorktreeMode { worktreeMode ?? .gitWorktree }
    public var usesGraphify: Bool { graphifyEnabled ?? false }
}

public struct GridWeights: Codable, Hashable, Sendable {
    public var columns: [Double]
    public var rows: [Double]

    public init(columns: [Double] = [], rows: [Double] = []) {
        self.columns = columns
        self.rows = rows
    }
}

public struct WorkspaceState: Codable, Hashable, Sendable {
    public var openProjectIDs: [ProjectID]
    public var containerWeights: [Double]
    public var gridWeights: [String: GridWeights]
    public var focusedPaneID: PaneID?
    public var selectedProjectID: ProjectID?
    public var collapsedProjectIDs: [ProjectID]
    public var fullscreenProjectID: ProjectID?
    public var isolatedPaneID: PaneID?
    public var tabs: [WorkspaceTab]
    public var closedTabs: [WorkspaceTab]
    public var activeTabID: WorkspaceTabID?
    public var history: [WorkspaceHistoryEntry]
    public var historyIndex: Int
    public var flat: Bool

    public init(openProjectIDs: [ProjectID] = [], containerWeights: [Double] = [],
                gridWeights: [String: GridWeights] = [:], focusedPaneID: PaneID? = nil,
                selectedProjectID: ProjectID? = nil, collapsedProjectIDs: [ProjectID] = [],
                fullscreenProjectID: ProjectID? = nil, isolatedPaneID: PaneID? = nil, tabs: [WorkspaceTab] = [],
                closedTabs: [WorkspaceTab] = [], activeTabID: WorkspaceTabID? = nil,
                history: [WorkspaceHistoryEntry] = [], historyIndex: Int = -1, flat: Bool = false) {
        self.openProjectIDs = openProjectIDs
        self.containerWeights = containerWeights
        self.gridWeights = gridWeights
        self.focusedPaneID = focusedPaneID
        self.selectedProjectID = selectedProjectID
        self.collapsedProjectIDs = collapsedProjectIDs
        self.fullscreenProjectID = fullscreenProjectID
        self.isolatedPaneID = isolatedPaneID
        self.tabs = tabs
        self.closedTabs = closedTabs
        self.activeTabID = activeTabID
        self.history = history
        self.historyIndex = historyIndex
        self.flat = flat
    }

    public static let flatWeightsKey = "flat"

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        openProjectIDs = try container.decode([ProjectID].self, forKey: .openProjectIDs)
        containerWeights = try container.decode([Double].self, forKey: .containerWeights)
        gridWeights = try container.decode([String: GridWeights].self, forKey: .gridWeights)
        focusedPaneID = try container.decodeIfPresent(PaneID.self, forKey: .focusedPaneID)
        selectedProjectID = try container.decodeIfPresent(ProjectID.self, forKey: .selectedProjectID)
        collapsedProjectIDs = try container.decodeIfPresent([ProjectID].self, forKey: .collapsedProjectIDs) ?? []
        fullscreenProjectID = try container.decodeIfPresent(ProjectID.self, forKey: .fullscreenProjectID)
        isolatedPaneID = try container.decodeIfPresent(PaneID.self, forKey: .isolatedPaneID)
        tabs = try container.decodeIfPresent([WorkspaceTab].self, forKey: .tabs) ?? []
        closedTabs = try container.decodeIfPresent([WorkspaceTab].self, forKey: .closedTabs) ?? []
        activeTabID = try container.decodeIfPresent(WorkspaceTabID.self, forKey: .activeTabID)
        history = try container.decodeIfPresent([WorkspaceHistoryEntry].self, forKey: .history) ?? []
        historyIndex = try container.decodeIfPresent(Int.self, forKey: .historyIndex) ?? history.count - 1
        flat = try container.decodeIfPresent(Bool.self, forKey: .flat) ?? false
    }
}

public struct WorkspaceDocument: VersionedDocument, Hashable {
    public static let currentVersion = 2
    public static let migrations: [Int: @Sendable (inout JSONObject) throws -> Void] = [
        1: { object in
            guard var projects = object["projects"]?.arrayValue else { return }
            for index in projects.indices {
                guard var project = projects[index].objectValue,
                      var panes = project["panes"]?.arrayValue else { continue }
                for pane in panes.indices {
                    guard var value = panes[pane].objectValue, value["content"] == nil else { continue }
                    value["content"] = .object(["kind": .string("terminal")])
                    panes[pane] = .object(value)
                }
                project["panes"] = .array(panes)
                projects[index] = .object(project)
            }
            object["projects"] = .array(projects)
        },
    ]
    public static let initial = WorkspaceDocument()

    public var schemaVersion: Int
    public var groups: [ProjectGroup]
    public var ungroupedProjectIDs: [ProjectID]
    public var projects: [Project]
    public var workspace: WorkspaceState

    public init(schemaVersion: Int = currentVersion, groups: [ProjectGroup] = [],
                ungroupedProjectIDs: [ProjectID] = [], projects: [Project] = [],
                workspace: WorkspaceState = WorkspaceState()) {
        self.schemaVersion = schemaVersion
        self.groups = groups
        self.ungroupedProjectIDs = ungroupedProjectIDs
        self.projects = projects
        self.workspace = workspace
    }
}
