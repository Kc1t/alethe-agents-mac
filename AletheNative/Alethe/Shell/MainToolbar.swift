import AletheAgents
import AletheModel
import SwiftUI

struct MainToolbar: ViewModifier {
    static let id = "main"

    @Environment(AppEnvironment.self) private var environment

    func body(content: Content) -> some View {
        let preferences = environment.preferences?.document ?? PreferencesDocument()
        let shown = Set(ToolbarItemKind.allCases.filter(preferences.showsToolbarItem))
        if #available(macOS 26.1, *) {
            content.toolbar(id: Self.id) {
                ForEach(ToolbarItemKind.allCases, id: \.self) { kind in
                    Self.item(kind, shown: shown.contains(kind)).visibilityPriority(Self.priority(kind.overflowRank))
                }
            }
        } else {
            content.toolbar(id: Self.id) {
                ForEach(ToolbarItemKind.allCases, id: \.self) { kind in
                    Self.item(kind, shown: shown.contains(kind))
                }
            }
        }
    }

    private static func item(_ kind: ToolbarItemKind, shown: Bool) -> some CustomizableToolbarContent {
        ToolbarItem(id: kind.rawValue, placement: kind == .home ? .navigation : .primaryAction) {
            view(for: kind)
        }
        .hidden(!shown)
    }

    @MainActor @ViewBuilder
    private static func view(for kind: ToolbarItemKind) -> some View {
        switch kind {
        case .home: HomeButton()
        case .usageClaude: UsagePill(provider: .claude)
        case .usageCodex: UsagePill(provider: .codex)
        case .usageAntigravity: UsagePill(provider: .antigravity)
        case .aiUsage: AIUsageButton()
        case .notifications: NotificationsButton()
        case .memory: MemoryIndicator()
        case .profile: ProfileToolbarMenu()
        case .remote: RemoteToolbarItem()
        case .router9: Router9ToolbarItem()
        case .sync: SyncToolbarItem()
        }
    }

    @available(macOS 26.1, *)
    static func priority(_ rank: ToolbarOverflowRank) -> ToolbarItemVisibilityPriority {
        switch rank {
        case .first:
            if #available(macOS 27, *) { return ToolbarItemVisibilityPriority(lowerThan: .low) }
            return .low
        case .early: return .low
        case .standard: return .automatic
        case .last: return .high
        }
    }
}
