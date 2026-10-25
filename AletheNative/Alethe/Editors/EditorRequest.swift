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
        if case .newProject(_, let folder) = self { return "newProject:\(folder ?? "")" }
        if case .editProject(let id) = self { return "editProject:\(id)" }
        if case .newGroup = self { return "newGroup" }
        if case .editGroup(let id) = self { return "editGroup:\(id)" }
        if case .newTerminal = self { return "newTerminal" }
        if case .newSubTab(let id) = self { return "newSubTab:\(id)" }
        if case .addContent = self { return "addContent" }
        if case .addBrowser = self { return "addBrowser" }
        if case .previewLink(let target) = self { return "previewLink:\(target)" }
        if case .importTauri = self { return "importTauri" }
        if case .layoutDesigner(let id) = self { return "layoutDesigner:\(id)" }
        if case .findJump = self { return "findJump" }
        if case .conversations = self { return "conversations" }
        if case .sessionCost(let tab) = self { return "sessionCost:\(tab)" }
        if case .handoff(let tab) = self { return "handoff:\(tab)" }
        if case .aiUsage = self { return "aiUsage" }
        if case .pluginSheet(let viewID, _) = self { return "pluginSheet:\(viewID)" }
        if case .mergeCenter = self { return "mergeCenter" }
        if case .worktrees = self { return "worktrees" }
        if case .branchTesting = self { return "branchTesting" }
        if case .agentLibrary = self { return "agentLibrary" }
        if case .diagnostics = self { return "diagnostics" }
        if case .dataManagement(let action) = self { return "dataManagement:\(action.rawValue)" }
        if case .crashNotice = self { return "crashNotice" }
        if case .skills = self { return "skills" }
        if case .gsdSyncActivity(let target) = self { return "gsdSyncActivity:\(target.sessionID)" }
        if case .onboarding = self { return "onboarding" }
        if case .welcome = self { return "welcome" }
        if case .mcpManager = self { return "mcpManager" }
        if case .mcpIntro = self { return "mcpIntro" }
        if case .remotePairing = self { return "remotePairing" }
        if case .gistSync = self { return "gistSync" }
        if case .themePicker = self { return "themePicker" }
        return "updateAvailable"
    }
}

enum LayoutDesignerScope: Hashable {
    case project(ProjectID)
    case group(GroupID)
    case workspace
}
