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
        if case .home = kind {
            HomeButton()
        } else if case .usageClaude = kind {
            UsagePill(provider: .claude)
        } else if case .usageCodex = kind {
            UsagePill(provider: .codex)
        } else if case .usageAntigravity = kind {
            UsagePill(provider: .antigravity)
        } else if case .aiUsage = kind {
            AIUsageButton()
        } else if case .notifications = kind {
            NotificationsButton()
        } else if case .memory = kind {
            MemoryIndicator()
        } else if case .profile = kind {
            ProfileToolbarMenu()
        } else if case .remote = kind {
            RemoteToolbarItem()
        } else if case .router9 = kind {
            Router9ToolbarItem()
        } else {
            SyncToolbarItem()
        }
    }

    @available(macOS 26.1, *)
    static func priority(_ rank: ToolbarOverflowRank) -> ToolbarItemVisibilityPriority {
        if case .first = rank {
            if #available(macOS 27, *) { return ToolbarItemVisibilityPriority(lowerThan: .low) }
            return .low
        } else if case .early = rank {
            return .low
        } else if case .standard = rank {
            return .automatic
        } else {
            return .high
        }
    }
}
