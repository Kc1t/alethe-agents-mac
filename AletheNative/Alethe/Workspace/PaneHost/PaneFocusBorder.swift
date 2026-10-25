import Foundation

enum PaneFocusBorder {
    static let enabledKey = "pane.focusBorder.enabled"
    static let opacityKey = "pane.focusBorder.opacity"

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    static var opacity: Double {
        min(1, max(0.1, UserDefaults.standard.object(forKey: opacityKey) as? Double ?? 1))
    }
}
