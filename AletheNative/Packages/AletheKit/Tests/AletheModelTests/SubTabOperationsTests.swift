@testable import AletheModel
import Foundation
import Testing

@Suite struct SubTabOperationsTests {
    private struct Sample {
        var doc: WorkspaceDocument
        var project: ProjectID
        var pane: PaneID
        var tabs: [TabID]
    }

    private func sample(tabs count: Int) -> Sample {
        var doc = WorkspaceDocument()
        let project = doc.addProject(name: "a", folder: "/a")
        let tabs = (0..<count).map { PaneTab(agent: $0 == 0 ? "shell" : "claude", title: "t\($0)") }
        guard let pane = doc.addPane(to: project, tab: tabs[0]) else {
            preconditionFailure("The fixture project must accept a pane")
        }
        for tab in tabs.dropFirst() { doc.addTab(tab, to: pane) }
        return Sample(doc: doc, project: project, pane: pane, tabs: tabs.map(\.id))
    }

    @Test func addingATabShowsAndFocusesIt() {
        let fixture = sample(tabs: 1)
        var doc = fixture.doc
        var project = fixture.project
        var pane = fixture.pane
        var tabs = fixture.tabs
        doc.workspace.focusedPaneID = nil
        doc.close(project)
        let added = PaneTab(agent: "codex")
        let wasAdded = doc.addTab(added, to: pane)
        #expect(wasAdded)
        #expect(doc.pane(pane)?.pane.tabs.map(\.id) == tabs + [added.id])
        #expect(doc.pane(pane)?.pane.activeTabID == added.id)
        #expect(doc.workspace.focusedPaneID == pane)
        #expect(doc.workspace.openProjectIDs == [project])
    }

    @Test func addingToAMissingPaneDoesNothing() {
        let fixture = sample(tabs: 1)
        var doc = fixture.doc
        let before = doc
        let wasAdded = doc.addTab(PaneTab(agent: "shell"), to: .make())
        #expect(!wasAdded)
        #expect(doc == before)
    }

    @Test func closingTheActiveTabShowsTheNextThenThePrevious() {
        let fixture = sample(tabs: 3)
        var doc = fixture.doc
        var pane = fixture.pane
        var tabs = fixture.tabs
        doc.activateTab(tabs[1])
        doc.closeTab(tabs[1])
        #expect(doc.pane(pane)?.pane.activeTabID == tabs[2])
        doc.closeTab(tabs[2])
        #expect(doc.pane(pane)?.pane.activeTabID == tabs[0])
    }

    @Test func closingAnInactiveTabKeepsTheActiveOne() {
        let fixture = sample(tabs: 3)
        var doc = fixture.doc
        var pane = fixture.pane
        var tabs = fixture.tabs
        doc.closeTab(tabs[0])
        #expect(doc.pane(pane)?.pane.activeTabID == tabs[2])
        #expect(doc.pane(pane)?.pane.tabs.map(\.id) == [tabs[1], tabs[2]])
    }

    @Test func activatingSelectsTheProjectAndFocusesThePane() {
        let fixture = sample(tabs: 2)
        var doc = fixture.doc
        var project = fixture.project
        var pane = fixture.pane
        var tabs = fixture.tabs
        doc.workspace.focusedPaneID = nil
        doc.workspace.selectedProjectID = nil
        doc.activateTab(tabs[0])
        #expect(doc.pane(pane)?.pane.activeTabID == tabs[0])
        #expect(doc.workspace.focusedPaneID == pane)
        #expect(doc.workspace.selectedProjectID == project)
    }

    @Test func cyclingWrapsAround() {
        let fixture = sample(tabs: 3)
        var doc = fixture.doc
        var pane = fixture.pane
        var tabs = fixture.tabs
        doc.activateTab(tabs[2])
        #expect(doc.tab(1, from: pane) == tabs[0])
        #expect(doc.tab(-1, from: pane) == tabs[1])
        doc.activateTab(tabs[0])
        #expect(doc.tab(-1, from: pane) == tabs[2])
    }

    @Test func laneIsShownWithSeveralTabsOrWhenAskedFor() {
        let fixture = sample(tabs: 1)
        var doc = fixture.doc
        var pane = fixture.pane
        #expect(doc.pane(pane)?.pane.isLaneVisible == false)
        doc.setLaneVisible(true, for: pane)
        #expect(doc.pane(pane)?.pane.isLaneVisible == true)
        doc.setLaneVisible(false, for: pane)
        #expect(doc.pane(pane)?.pane.laneVisible == nil)
        doc.addTab(PaneTab(agent: "claude"), to: pane)
        #expect(doc.pane(pane)?.pane.isLaneVisible == true)
    }

    @Test func laneVisibilityIsOptionalInTheFile() throws {
        let fixture = sample(tabs: 1)
        let doc = fixture.doc
        let pane = fixture.pane
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as? [String: Any])
        var projects = try #require(json["projects"] as? [[String: Any]])
        var panes = try #require(projects[0]["panes"] as? [[String: Any]])
        panes[0].removeValue(forKey: "laneVisible")
        projects[0]["panes"] = panes
        json["projects"] = projects
        let decoded = try JSONDecoder().decode(WorkspaceDocument.self,
                                               from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.pane(pane)?.pane.laneVisible == nil)
    }
}

@Suite struct PromptHistoryDocumentTests {
    @Test func pruneKeepsOnlyExistingTabs() {
        let kept = TabID.make(), gone = TabID.make()
        var doc = PromptHistoryDocument(histories: [kept.rawValue: ["a"], gone.rawValue: ["b"]])
        doc.prune(keeping: [kept])
        #expect(doc.histories == [kept.rawValue: ["a"]])
    }
}
