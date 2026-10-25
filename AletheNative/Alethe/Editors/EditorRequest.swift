import AletheModel

enum EditorRequest: Identifiable, Hashable {
    case newProject(ProjectLocation, folder: String? = nil)
    case editProject(ProjectID)
    case newGroup(parent: GroupID?)
    case editGroup(GroupID)
    case newTerminal(ProjectID?)
    case newSubTab(PaneID)
    case addContent(ProjectID?)
    case addBrowser(ProjectID?)
    case previewLink(LinkPreviewTarget)
    case importTauri
    case layoutDesigner(LayoutDesignerScope)
    case findJump
    case conversations(ProjectID?)
    case sessionCost(TabID)
    case handoff(TabID)
    case aiUsage
    case pluginSheet(viewID: String, project: ProjectID?)
    case mergeCenter(ProjectID?, resume: String? = nil)
    case worktrees(ProjectID?)
    case branchTesting(ProjectID?)
    case agentLibrary(ProjectID?)
    case diagnostics
    case dataManagement(DataSettingsAction)
    case crashNotice
    case skills
    case gsdSyncActivity(GSDSyncActivityTarget)
    case onboarding
    case welcome(WelcomeBack)
    case mcpManager(McpManagerRoute)
    case mcpIntro
    case remotePairing
    case gistSync
    case themePicker
    case updateAvailable(SidebarNativeRelease)

    var id: String {
        switch self {
        case .newProject(_, let folder): "newProject:\(folder ?? "")"
        case .editProject(let id): "editProject:\(id)"
        case .newGroup: "newGroup"
        case .editGroup(let id): "editGroup:\(id)"
        case .newTerminal: "newTerminal"
        case .newSubTab(let id): "newSubTab:\(id)"
        case .addContent: "addContent"
        case .addBrowser: "addBrowser"
        case .previewLink(let target): "previewLink:\(target)"
        case .importTauri: "importTauri"
        case .layoutDesigner(let id): "layoutDesigner:\(id)"
        case .findJump: "findJump"
        case .conversations: "conversations"
        case .sessionCost(let tab): "sessionCost:\(tab)"
        case .handoff(let tab): "handoff:\(tab)"
        case .aiUsage: "aiUsage"
        case .pluginSheet(let viewID, _): "pluginSheet:\(viewID)"
        case .mergeCenter: "mergeCenter"
        case .worktrees: "worktrees"
        case .branchTesting: "branchTesting"
        case .agentLibrary: "agentLibrary"
        case .diagnostics: "diagnostics"
        case .dataManagement(let action): "dataManagement:\(action.rawValue)"
        case .crashNotice: "crashNotice"
        case .skills: "skills"
        case .gsdSyncActivity(let target): "gsdSyncActivity:\(target.sessionID)"
        case .onboarding: "onboarding"
        case .welcome: "welcome"
        case .mcpManager: "mcpManager"
        case .mcpIntro: "mcpIntro"
        case .remotePairing: "remotePairing"
        case .gistSync: "gistSync"
        case .themePicker: "themePicker"
        case .updateAvailable: "updateAvailable"
        }
    }
}

enum LayoutDesignerScope: Hashable {
    case project(ProjectID)
    case group(GroupID)
    case workspace
}
