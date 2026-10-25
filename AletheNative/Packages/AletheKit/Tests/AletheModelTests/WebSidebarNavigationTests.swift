@testable import AletheModel
import Foundation
import Testing

@Suite struct WebSidebarNavigationTests {
    private struct Sample {
        var doc: WorkspaceDocument
        var group: GroupID
        var a: ProjectID
        var b: ProjectID
        var first: PaneID
        var second: PaneID
    }

    private func sample() -> Sample {
        var doc = WorkspaceDocument()
        let group = doc.addGroup(name: "Group")
        let a = doc.addProject(name: "A", folder: "/a", in: .group(group))
        let b = doc.addProject(name: "B", folder: "/b")
        guard let first = doc.addPane(to: a, tab: PaneTab(agent: "shell")) else {
            preconditionFailure("The fixture project must accept a pane")
        }
        guard let second = doc.addPane(to: b, tab: PaneTab(agent: "shell")) else {
            preconditionFailure("The fixture project must accept a pane")
        }
        doc.startClean()
        doc.workspace.tabs = []
        doc.workspace.history = []
        doc.workspace.historyIndex = -1
        return Sample(doc: doc, group: group, a: a, b: b, first: first, second: second)
    }

    @Test func projectClickLeavesGroupEvenWhenAlreadyVisible() {
        let fixture = sample()
        var doc = fixture.doc
        var group = fixture.group
        var a = fixture.a
        doc.openWebGroup(group, adding: false)
        let groupTab = doc.workspace.activeTabID
        doc.openWebProject(a)
        #expect(doc.workspace.activeTabID != groupTab)
        #expect(doc.activeWorkspaceTab?.kind == .project)
        #expect(doc.workspace.openProjectIDs == [a])
        #expect(doc.workspace.focusedPaneID == nil)
        doc.openWebProject(a)
        #expect(doc.workspace.tabs.count == 2)
    }

    @Test func groupOpenRecursesAndExcludesEmptyProjectsInDocumentOrder() {
        let fixture = sample()
        var doc = fixture.doc
        var group = fixture.group
        var a = fixture.a
        var b = fixture.b
        let child = doc.addGroup(name: "Child", parent: group)
        doc.moveProject(b, to: .group(child), at: 0)
        _ = doc.addProject(name: "Empty", folder: "/empty", in: .group(group))
        doc.openWebGroup(group, adding: false)
        #expect(doc.workspace.openProjectIDs == [a, b])
        #expect(doc.workspace.selectedProjectID == a)
        #expect(doc.workspace.focusedPaneID == nil)
        #expect(doc.activeWorkspaceTab?.webGroupID == group)
    }

    @Test func emptyGroupOpensAnEmptyTab() {
        let fixture = sample()
        var doc = fixture.doc
        var b = fixture.b
        let empty = doc.addGroup(name: "Empty")
        doc.openWebProject(b)
        doc.openWebGroup(empty, adding: false)
        #expect(doc.workspace.openProjectIDs.isEmpty)
        #expect(doc.workspace.selectedProjectID == nil)
        #expect(doc.activeWorkspaceTab?.webGroupID == empty)
        #expect(doc.workspace.tabs.count == 2)
    }

    @Test func emptyGroupAppendIsANoop() {
        let fixture = sample()
        var doc = fixture.doc
        var b = fixture.b
        let empty = doc.addGroup(name: "Empty")
        doc.openWebProject(b)
        let before = doc.currentSnapshot
        let tab = doc.workspace.activeTabID
        doc.openWebGroup(empty, adding: true)
        #expect(doc.currentSnapshot == before)
        #expect(doc.workspace.activeTabID == tab)
        #expect(doc.activeWorkspaceTab?.kind == .project)
    }

    @Test func groupAppendPreservesCurrentTabAndExistingContainers() {
        let fixture = sample()
        var doc = fixture.doc
        var group = fixture.group
        var a = fixture.a
        var b = fixture.b
        doc.openWebProject(b)
        let tab = doc.workspace.activeTabID
        doc.workspace.flat = true
        doc.workspace.fullscreenProjectID = b
        doc.openWebGroup(group, adding: true)
        #expect(doc.workspace.activeTabID == tab)
        #expect(doc.workspace.openProjectIDs == [b, a])
        #expect(doc.workspace.selectedProjectID == a)
        #expect(doc.activeWorkspaceTab?.kind == .composition)
        #expect(doc.activeWorkspaceTab?.projectID == nil)
        #expect(!doc.workspace.flat && doc.workspace.fullscreenProjectID == nil)
        doc.openWebGroup(group, adding: true)
        #expect(doc.workspace.openProjectIDs == [b, a])
    }

    @Test func appendWithoutActiveTabOpensGroupTab() {
        let fixture = sample()
        var doc = fixture.doc
        var group = fixture.group
        doc.openWebGroup(group, adding: true)
        #expect(doc.activeWorkspaceTab?.webGroupID == group)
    }

    @Test func savedGroupTabRestoresItsCompositionAndFocus() {
        let fixture = sample()
        var doc = fixture.doc
        var group = fixture.group
        var b = fixture.b
        var first = fixture.first
        doc.openWebGroup(group, adding: false)
        let tab = doc.workspace.activeTabID
        doc.focusWebPane(first)
        doc.openWebProject(b)
        doc.openWebGroup(group, adding: false)
        #expect(doc.workspace.activeTabID == tab)
        #expect(doc.workspace.focusedPaneID == first)
        #expect(doc.workspace.tabs.count == 2)
    }

    @Test func visibleTerminalClickPreservesComposition() {
        let fixture = sample()
        var doc = fixture.doc
        var group = fixture.group
        var a = fixture.a
        var b = fixture.b
        var first = fixture.first
        doc.openWebProject(b)
        doc.openWebGroup(group, adding: true)
        let tab = doc.workspace.activeTabID
        doc.focusWebPane(first)
        #expect(doc.workspace.activeTabID == tab)
        #expect(doc.workspace.openProjectIDs == [b, a])
        #expect(doc.workspace.focusedPaneID == first)
        #expect(doc.workspace.selectedProjectID == a)
        #expect(doc.workspace.history.last?.snapshot.focusedPaneID == first)
    }

    @Test func hiddenTerminalClickOpensItsProjectGrid() {
        let fixture = sample()
        var doc = fixture.doc
        var a = fixture.a
        var b = fixture.b
        var first = fixture.first
        doc.openWebProject(b)
        doc.focusWebPane(first)
        #expect(doc.workspace.openProjectIDs == [a])
        #expect(doc.activeWorkspaceTab?.kind == .project)
        #expect(doc.workspace.focusedPaneID == first)
    }

    @Test func terminalDoubleClickOpensAndReusesAnIndividualTab() {
        let fixture = sample()
        var doc = fixture.doc
        var a = fixture.a
        var first = fixture.first
        guard let other = doc.addPane(to: a, tab: PaneTab(agent: "codex")) else {
            preconditionFailure("The fixture project must accept a pane")
        }
        doc.openWebProject(a)
        doc.openWebPane(first)
        let tab = doc.workspace.activeTabID
        #expect(doc.activeWorkspaceTab?.webPaneID == first)
        #expect(doc.webPaneIsVisible(first))
        #expect(!doc.webPaneIsVisible(other))
        doc.openWebProject(a)
        doc.openWebPane(first)
        #expect(doc.workspace.activeTabID == tab)
        #expect(doc.workspace.tabs.count == 2)
    }

    @Test func paneMoveKeepsSessionsAndUsesDestinationGrid() {
        let fixture = sample()
        var doc = fixture.doc
        var a = fixture.a
        var b = fixture.b
        var first = fixture.first
        let original = doc.pane(first)?.pane.tabs
        let grid = doc.createGrid(named: "Work", in: b)
        doc.moveWebPane(first, to: b)
        #expect(doc.project(a)?.panes.isEmpty == true)
        #expect(doc.pane(first)?.project.id == b)
        #expect(doc.pane(first)?.pane.tabs == original)
        #expect(doc.pane(first)?.pane.gridID == grid)
    }

    @Test func sourceIdentitySurvivesEncodingWithoutNewFields() throws {
        let fixture = sample()
        var doc = fixture.doc
        var group = fixture.group
        doc.openWebGroup(group, adding: false)
        let data = try JSONEncoder().encode(doc)
        var decoded = try JSONDecoder().decode(WorkspaceDocument.self, from: data)
        decoded.repair()
        #expect(decoded.activeWorkspaceTab?.webGroupID == group)
        #expect(decoded.label(of: try #require(decoded.activeWorkspaceTab))?.name == "Group")
    }

    @Test func groupLabelTracksRename() throws {
        let fixture = sample()
        var doc = fixture.doc
        var group = fixture.group
        doc.openWebGroup(group, adding: false)
        doc.updateGroup(group) { $0.name = "Renamed" }
        #expect(doc.label(of: try #require(doc.activeWorkspaceTab))?.name == "Renamed")
    }

    @Test func nativeProjectSelectionStillPreservesAnOpenComposition() {
        let fixture = sample()
        var doc = fixture.doc
        var a = fixture.a
        var b = fixture.b
        doc.openInTab(a)
        doc.open(b)
        doc.syncActiveTab()
        let tab = doc.workspace.activeTabID
        doc.openInTab(a)
        #expect(doc.workspace.activeTabID == tab)
        #expect(doc.workspace.openProjectIDs == [a, b])
    }
}
