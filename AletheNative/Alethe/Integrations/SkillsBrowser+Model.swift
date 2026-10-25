import AletheDesign
import AletheDocuments
import AletheFoundation
import AletheIntegrations
import AppKit
import SwiftUI

@MainActor @Observable
final class SkillsBrowserModel {
    struct Removal: Hashable {
        var group: String
        var entries: [SkillSummary]
    }

    let store: SkillStore
    private(set) var snapshots: [SkillAgentSnapshot]?
    private(set) var groups: [SkillGroup] = []
    private(set) var detail: SkillDetail?
    private(set) var blocks: [MarkdownBlock] = []
    private(set) var busy = false
    private(set) var error: String? { didSet { if error != oldValue { AppLog.shown(error, .integrations) } } }
    private(set) var detailError: String? { didSet { if detailError != oldValue { AppLog.shown(detailError, .integrations) } } }
    private(set) var note: String?
    var query = "" { didSet { loadDetail() } }
    var agentFilter: SkillAgent? { didSet { loadDetail() } }
    var selection: String? { didSet { loadDetail() } }

    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var detailKey: String?

    init(store: SkillStore) { self.store = store }

    var visibleGroups: [SkillGroup] {
        groups.filter { $0.matches(query) && $0.isInstalled(for: agentFilter) }
    }

    var activeGroup: SkillGroup? {
        let visible = visibleGroups
        return visible.first { $0.name == selection } ?? visible.first
    }

    func load() async {
        loadTask?.cancel()
        let store = store
        let task = Task {
            do {
                let snapshots = try await store.scan()
                self.snapshots = snapshots
                groups = SkillGroup.group(snapshots)
                error = nil
                if !groups.contains(where: { $0.name == selection }) { selection = nil }
            } catch is CancellationError {
            } catch {
                snapshots = snapshots ?? []
                self.error = Self.describe(error)
            }
            loadDetail()
        }
        loadTask = task
        await task.value
    }

    func cancel() {
        loadTask?.cancel()
        detailTask?.cancel()
        detailKey = nil
    }

    private func loadDetail() {
        guard let source = activeGroup?.entries.first else {
            detailTask?.cancel()
            detailKey = nil
            detail = nil
            blocks = []
            detailError = nil
            return
        }
        guard source.id != detailKey else { return }
        detailTask?.cancel()
        detailKey = source.id
        let store = store
        detailError = nil
        detailTask = Task {
            do {
                let detail = try await store.detail(agent: source.agent, name: source.name)
                let base = URL(filePath: detail.summary.path, directoryHint: .isDirectory)
                let body = detail.body
                let blocks = await Task.detached { MarkdownBlocks.parse(body, base: base) }.value
                try Task.checkCancellation()
                self.detail = detail
                self.blocks = blocks
            } catch is CancellationError {
            } catch {
                detail = nil
                blocks = []
                detailError = Self.describe(error)
            }
        }
    }

    func remove(_ removal: Removal) {
        guard !busy else { return }
        busy = true
        error = nil
        note = nil
        let store = store
        Task {
            var removed: [String] = []
            var failures: [String] = []
            var keptShared: String?
            var trashed = false
            for entry in removal.entries {
                do {
                    let report = try await store.uninstall(agent: entry.agent, name: entry.name)
                    removed.append(entry.agent.label)
                    keptShared = report.sharedCopyPath ?? keptShared
                    trashed = trashed || report.movedToTrash
                } catch {
                    failures.append("\(entry.agent.label): \(Self.describe(error))")
                }
            }
            if !removed.isEmpty {
                var note = format("skills.removed", removal.group, removed.joined(separator: ", "))
                if let keptShared { note += " " + format("skills.removed.linkOnly", keptShared) }
                if trashed { note += " " + String(localized: "skills.removed.trash") }
                self.note = note
            }
            if !failures.isEmpty {
                error = format("skills.remove.failed", failures.joined(separator: " · "))
            }
            detail = nil
            detailKey = nil
            await load()
            busy = false
        }
    }

    static func describe(_ error: any Error) -> String {
        let matchedValue = error as? SkillError
        if case .invalidName? = matchedValue {
            return String(localized: "skills.error.invalidName")
        } else if case .notFound? = matchedValue {
            return String(localized: "skills.error.notFound")
        } else if case .outsideRoot? = matchedValue {
            return String(localized: "skills.error.outsideRoot")
        } else if case .bundled? = matchedValue {
            return String(localized: "skills.error.bundled")
        } else if case .removeFailed(let reason)? = matchedValue {
            return reason
        } else {
            return error.localizedDescription
        }
    }
}

extension SkillAgent {
    private static let labelValues: [SkillAgent: String] = [
        .claude: "Claude Code",
        .codex: "Codex",
        .opencode: "OpenCode",
        .antigravity: "Antigravity",
    ]

    var label: String {
        Self.labelValues[self] ?? String(localized: "skills.agent.shared")
    }

    private static let colorTokenValues: [SkillAgent: ThemeToken] = [
        .claude: .agentClaude,
        .codex: .agentCodex,
        .opencode: .agentOpencode,
        .antigravity: .agentAntigravity,
    ]

    var colorToken: ThemeToken {
        Self.colorTokenValues[self] ?? .textTertiary
    }
}

extension SkillNode {
    var childrenIfFolder: [SkillNode]? { isDirectory ? children : nil }
}
