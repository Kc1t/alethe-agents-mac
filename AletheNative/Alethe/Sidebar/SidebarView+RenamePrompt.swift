import AletheAgents
import AletheDesign
import AletheGit
import AletheGitControl
import AletheModel
import AppKit
import SwiftUI

@MainActor
enum SidebarRenamePrompt {
    static func name(initial: String, width: CGFloat, height: CGFloat, apply: @escaping (String) -> Void) {
        guard WebDialogCenter.shared.themed else {
            if let name = name(initial: initial, width: width, height: height) { apply(name) }
            return
        }
        Task {
            guard let answer = await WebDialogCenter.shared.prompt(String(localized: "dialog.newName"), initial: initial)
            else { return }
            let name = answer.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty { apply(name) }
        }
    }

    static func name(initial: String, width: CGFloat, height: CGFloat) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "sidebar.rename")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: width, height: height))
        field.stringValue = initial
        field.setAccessibilityIdentifier("sidebar.rename.name")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "files.rename"))
        alert.addButton(withTitle: String(localized: "editor.cancel"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}
