import AletheFoundation
import Foundation

public enum ToolbarItemKind: String, CaseIterable, Codable, Hashable, Sendable {
    case home
    case usageClaude = "usage.claude"
    case usageCodex = "usage.codex"
    case usageAntigravity = "usage.antigravity"
    case aiUsage = "usage"
    case notifications
    case memory
    case profile
    case remote
    case router9
    case sync

    public static let usageProviders = ["claude", "codex", "antigravity"]

    public static func usagePill(for provider: String) -> ToolbarItemKind? {
        ToolbarItemKind(rawValue: "usage.\(provider)")
    }

    public var usageProvider: String? {
        guard rawValue.hasPrefix("usage.") else { return nil }
        return String(rawValue.dropFirst("usage.".count))
    }

    public var shownByDefault: Bool { self != .router9 }

    public var overflowRank: ToolbarOverflowRank {
        if case .usageClaude = self {
            return .first
        } else if case .usageCodex = self {
            return .first
        } else if case .usageAntigravity = self {
            return .first
        } else if case .memory = self {
            return .early
        } else if case .aiUsage = self {
            return .early
        } else if case .router9 = self {
            return .early
        } else if case .sync = self {
            return .early
        } else if case .notifications = self {
            return .standard
        } else if case .remote = self {
            return .standard
        } else if case .home = self {
            return .last
        } else {
            return .last
        }
    }
}

public enum ToolbarOverflowRank: Int, Comparable, Sendable {
    case first, early, standard, last

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension PreferencesDocument {
    public func showsToolbarItem(_ item: ToolbarItemKind) -> Bool {
        toolbarItems?[item.rawValue] ?? item.shownByDefault
    }

    public mutating func setToolbarItem(_ item: ToolbarItemKind, shown: Bool) {
        var items = toolbarItems ?? [:]
        items[item.rawValue] = shown == item.shownByDefault ? nil : shown
        toolbarItems = items.isEmpty ? nil : items
    }

    public var usagePillProviders: [String] {
        ToolbarItemKind.usageProviders.filter { provider in
            ToolbarItemKind.usagePill(for: provider).map(showsToolbarItem) ?? false
        }
    }

    static func migrateUsagePills(_ object: inout JSONObject) {
        guard let pills = object.removeValue(forKey: "usagePills") else { return }
        let shown = Set(pills.arrayValue?.compactMap(\.stringValue) ?? [])
        var items = object["toolbarItems"]?.objectValue ?? [:]
        for provider in ToolbarItemKind.usageProviders {
            if let item = ToolbarItemKind.usagePill(for: provider) { items[item.rawValue] = .bool(shown.contains(provider)) }
        }
        if !items.isEmpty { object["toolbarItems"] = .object(items) }
    }
}
