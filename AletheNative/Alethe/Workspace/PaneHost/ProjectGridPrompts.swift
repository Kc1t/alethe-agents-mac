import AletheModel
import AppKit
import SwiftUI

@MainActor
enum ProjectGridPrompts {
    static func name(title: String, initial: String, action: String,
                     problem: (String) -> WorkspaceDocument.GridNameProblem?) -> String? {
        var value = initial
        var message = String(localized: "projectGrid.nameHint")
        while true {
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = message
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.stringValue = value
            field.placeholderString = String(localized: "projectGrid.placeholder")
            field.setAccessibilityIdentifier("projectGrid.name")
            alert.accessoryView = field
            alert.addButton(withTitle: action)
            alert.addButton(withTitle: String(localized: "editor.cancel"))
            alert.window.initialFirstResponder = field
            guard alert.runModal() == .alertFirstButtonReturn else { return nil }
            value = field.stringValue
            guard let issue = problem(value) else { return value }
            message = if case .empty = issue {
                String(localized: "projectGrid.error.empty")
            } else if case .taken = issue {
                String(localized: "projectGrid.error.taken")
            } else {
                String(localized: "projectGrid.error.reserved")
            }
        }
    }

    static func webName(rename: Bool, initial: String, problem: @escaping (String) -> WorkspaceDocument.GridNameProblem?) async -> String? {
        let outcome = await WebDialogCenter.shared.present(width: 540) { finish in
            ProjectGridWebModal(mode: rename ? .rename : .create, initial: initial,
                                isValid: { problem($0) == nil }, finish: finish)
        }
        if case .confirmed(let name) = outcome { return name }
        return nil
    }

    static func webDelete(grid: String, paneCount: Int) async -> DeleteChoice? {
        let outcome = await WebDialogCenter.shared.present(width: 540) { finish in
            ProjectGridWebModal(mode: .delete(name: grid, count: paneCount), finish: finish)
        }
        if case .confirmed = outcome {
            return .keepPanes
        }
        if case .alternate = outcome { return .closePanes }
        return nil
    }

    static func createGrid(in project: ProjectID, workspace: WorkspaceModel, undoManager: UndoManager?) {
        if WebDialogCenter.shared.themed {
            Task {
                guard let name = await webName(rename: false, initial: "",
                    problem: { workspace.document.gridNameProblem($0, in: project) }) else { return }
                workspace.update(undoManager: undoManager, actionName: String(localized: "undo.newGrid")) {
                    $0.createGrid(named: name, in: project)
                }
            }
            return
        }
        guard let name = name(title: String(localized: "projectGrid.new.title"), initial: "",
                              action: String(localized: "projectGrid.create"),
                              problem: { workspace.document.gridNameProblem($0, in: project) }) else { return }
        workspace.update(undoManager: undoManager, actionName: String(localized: "undo.newGrid")) {
            $0.createGrid(named: name, in: project)
        }
    }

    enum DeleteChoice { case keepPanes, closePanes }

    static func delete(grid: String, paneCount: Int) -> DeleteChoice? {
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "projectGrid.delete.title"), grid)
        alert.informativeText = paneCount == 0
            ? String(localized: "projectGrid.delete.empty")
            : String(format: String(localized: "projectGrid.delete.message"), paneCount)
        alert.addButton(withTitle: String(localized: "projectGrid.delete.keep"))
        if paneCount > 0 {
            alert.addButton(withTitle: String(localized: "projectGrid.delete.close"))
            alert.buttons.last?.hasDestructiveAction = true
        }
        alert.addButton(withTitle: String(localized: "editor.cancel"))
        let selection = alert.runModal()
        if case .alertFirstButtonReturn = selection {
            return .keepPanes
        } else if case .alertSecondButtonReturn = selection {
            return paneCount > 0 ? .closePanes : nil
        } else {
            return nil
        }
    }
}
