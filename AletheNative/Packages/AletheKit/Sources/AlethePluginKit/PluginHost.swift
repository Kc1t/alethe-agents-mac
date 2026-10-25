import AletheFoundation
import Foundation
import Observation

public struct PluginHostState: VersionedDocument {
    public static let currentVersion = 1
    public static let migrations: [Int: @Sendable (inout JSONObject) throws -> Void] = [:]
    public static let initial = PluginHostState(schemaVersion: 1, enabled: [:], viewPlacements: nil)
    public var schemaVersion: Int
    public var enabled: [String: Bool]
    public var viewPlacements: ViewPlacements?
}

@MainActor
@Observable
public final class PluginHost {
    public enum State: Equatable, Sendable {
        case disabled
        case active
        case failed(String)
    }

    public struct Record: Sendable, Identifiable {
        public var manifest: PluginManifest
        public var isEnabled: Bool
        public var state: State
        public var id: String { manifest.id }
    }

    public private(set) var records: [Record] = []
    public private(set) var contributions = PluginContributions()
    private var placements = ViewPlacements.empty
    @ObservationIgnored public let events = EventOutbox()

    @ObservationIgnored private let pluginTypes: [any AlethePlugin.Type]
    @ObservationIgnored private let dataRoot: URL
    @ObservationIgnored private let services: PluginServices
    @ObservationIgnored private let storageDebounce: Duration
    @ObservationIgnored private let stateStore: DocumentStore<PluginHostState>
    @ObservationIgnored private var hostState = PluginHostState.initial
    @ObservationIgnored private var stateRevision: UInt64 = 0
    @ObservationIgnored private var instances: [String: any AlethePlugin] = [:]
    @ObservationIgnored private var contexts: [String: PluginContext] = [:]
    @ObservationIgnored private var storages: [String: PluginStorage] = [:]

    public init(
        plugins: [any AlethePlugin.Type],
        dataRoot: URL,
        services: PluginServices = PluginServices(),
        storageDebounce: Duration = .milliseconds(300)
    ) {
        self.pluginTypes = plugins
        self.dataRoot = dataRoot
        self.services = services
        self.storageDebounce = storageDebounce
        self.stateStore = DocumentStore(url: dataRoot.appending(path: "plugins.json"))
    }

    public func load() async {
        hostState = (try? await stateStore.load().document) ?? .initial
        placements = hostState.viewPlacements ?? .empty
        records = []
        var seen = Set<String>()
        for type in pluginTypes {
            let manifest = type.manifest
            let enabled = hostState.enabled[manifest.id] ?? manifest.enabledByDefault
            var record = Record(manifest: manifest, isEnabled: enabled, state: .disabled)
            if let error = validate(manifest, seen: seen) {
                record.state = .failed(String(describing: error))
            }
            seen.insert(manifest.id)
            records.append(record)
        }
        for index in records.indices where records[index].isEnabled && records[index].state == .disabled {
            activate(at: index)
        }
        for record in records {
            if case .failed(let error) = record.state { events.publish(.pluginFailed(id: record.id, error: error)) }
        }
        rebuildContributions()
    }

    public func record(for id: String) -> Record? {
        records.first { $0.id == id }
    }

    public func instance(for id: String) -> (any AlethePlugin)? {
        instances[id]
    }

    public func contributions(of id: String) -> PluginContributions? {
        contexts[id]?.contributions
    }

    public func setEnabled(_ enabled: Bool, for id: String) async throws {
        guard let index = records.firstIndex(where: { $0.id == id }) else { throw PluginError.unknownPlugin(id) }
        records[index].isEnabled = enabled
        hostState.enabled[id] = enabled
        stateRevision += 1
        try await stateStore.save(hostState, revision: stateRevision)

        if enabled {
            if records[index].state != .active,
               validate(records[index].manifest, seen: Set(records[..<index].map(\.id))) == nil {
                activate(at: index)
            }
        } else {
            await deactivate(at: index)
            records[index].state = .disabled
        }
        events.publish(.pluginEnabledChanged(id: id, enabled: enabled))
        if enabled, case .failed(let error) = records[index].state {
            events.publish(.pluginFailed(id: id, error: error))
        }
        rebuildContributions()
    }

    public var viewPlacements: ViewPlacements { placements }

    public func moveSidebarTab(_ id: String, to side: SidebarSide, at index: Int) async throws {
        var updated = placements
        updated.move(id, to: side, at: index, in: contributions.sidebarTabs)
        try await savePlacements(updated)
    }

    public func resetViewPlacements() async throws {
        try await savePlacements(.empty)
    }

    private func savePlacements(_ updated: ViewPlacements) async throws {
        guard updated != placements else { return }
        placements = updated
        hostState.viewPlacements = updated == .empty ? nil : updated
        stateRevision += 1
        try await stateStore.save(hostState, revision: stateRevision)
    }

    public func shutdown() async {
        for index in records.indices where records[index].state == .active {
            await deactivate(at: index)
            records[index].state = .disabled
        }
        rebuildContributions()
    }

    private func validate(_ manifest: PluginManifest, seen: Set<String>) -> PluginError? {
        if !manifest.hasValidID { return .invalidID(manifest.id) }
        if seen.contains(manifest.id) { return .duplicatePlugin(manifest.id) }
        if !manifest.apiVersion.isCompatible() {
            return .incompatibleAPI(required: manifest.apiVersion, host: .current)
        }
        return nil
    }

    private func activate(at index: Int) {
        let manifest = records[index].manifest
        guard let type = pluginTypes.first(where: { $0.manifest.id == manifest.id }) else { return }
        let id = manifest.id
        let context = PluginContext(manifest: manifest, services: services) { [unowned self] in
            self.storage(for: id)
        }
        let plugin = type.init()
        do {
            try plugin.activate(context: context)
            instances[id] = plugin
            contexts[id] = context
            records[index].state = .active
        } catch {
            context.isActive = false
            records[index].state = .failed(String(describing: error))
        }
    }

    private func deactivate(at index: Int) async {
        let id = records[index].id
        if let plugin = instances.removeValue(forKey: id) { plugin.deactivate() }
        contexts.removeValue(forKey: id)?.isActive = false
        try? await storages[id]?.flush()
    }

    private func storage(for id: String) -> PluginStorage {
        if let storage = storages[id] { return storage }
        let storage = PluginStorage(root: dataRoot, pluginID: id, debounce: storageDebounce)
        storages[id] = storage
        return storage
    }

    private func rebuildContributions() {
        var all = PluginContributions()
        for record in records where record.state == .active {
            if let context = contexts[record.id] { all.append(context.contributions) }
        }
        contributions = all
    }
}
