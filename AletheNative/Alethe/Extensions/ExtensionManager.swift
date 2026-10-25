import AletheExtensionHost
import AletheFoundation
import AlethePluginKit
import CoreServices
import ExtensionFoundation
import Foundation
import Observation

@Observable
@MainActor
final class ExtensionManager {
    struct Entry: Identifiable {
        enum Status: Equatable {
            case loading
            case ready
            case failed(String)
            case stopped
        }

        let identity: AppExtensionIdentity
        var payload: ExtensionManifestPayload?
        var manifest: PluginManifest?
        var status: Status = .loading
        var lastReply: String?

        var id: String { identity.bundleIdentifier }
    }

    struct ConsentRequest: Identifiable {
        let manifest: PluginManifest
        let capabilities: Set<PluginCapability>
        var id: String { manifest.id }
    }

    private(set) var entries: [Entry] = []
    private(set) var state = ExtensionHostState()
    private(set) var awaitingSystemApproval = 0
    private(set) var discoveryError: String?
    var pendingConsent: ConsentRequest?
    @ObservationIgnored let events = EventOutbox()

    private let stateURL: URL
    private let dataRoot: URL
    @ObservationIgnored private var monitor: AppExtensionPoint.Monitor?
    @ObservationIgnored private var processes: [String: AppExtensionProcess] = [:]
    @ObservationIgnored private var connections: [String: NSXPCConnection] = [:]
    @ObservationIgnored private var storages: [String: PluginStorage] = [:]

    init(profileDirectory: URL) {
        dataRoot = profileDirectory
        stateURL = profileDirectory.appending(path: "extensions.json")
        state = ExtensionHostState.load(from: stateURL)
    }

    func start() async {
        #if DEBUG
        if let path = UserDefaults.standard.string(forKey: "AletheRegisterExtensionApp") {
            LSRegisterURL(URL(filePath: path) as CFURL, true)
        }
        #endif
        do {
            let monitor = try await AppExtensionPoint.Monitor(appExtensionPoint: .aletheSidebarTab)
            self.monitor = monitor
            observe()
        } catch {
            discoveryError = String(describing: error)
        }
    }

    private func observe() {
        guard let monitor else { return }
        withObservationTracking {
            sync(monitor.state)
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
    }

    private func sync(_ monitorState: AppExtensionPoint.Monitor.State) {
        awaitingSystemApproval = monitorState.unapprovedCount + monitorState.disabledCount
        let identities = monitorState.identities
        let ids = Set(identities.map(\.bundleIdentifier))
        for entry in entries where !ids.contains(entry.id) { teardown(entry.id) }
        entries.removeAll { !ids.contains($0.id) }
        for identity in identities where !entries.contains(where: { $0.id == identity.bundleIdentifier }) {
            entries.append(Entry(identity: identity))
            connect(identity)
        }
        entries.sort { $0.identity.localizedName.localizedStandardCompare($1.identity.localizedName) == .orderedAscending }
    }

    private func connect(_ identity: AppExtensionIdentity) {
        let id = identity.bundleIdentifier
        let configuration = AppExtensionProcess.Configuration(appExtensionIdentity: identity) { [weak self] in
            Task { @MainActor in self?.processStopped(id) }
        }
        do {
            let process = try AppExtensionProcess(configuration: configuration)
            let connection = try process.makeXPCConnection()
            configureHostSide(of: connection, for: id)
            connection.remoteObjectInterface = .aletheExtension()
            connection.interruptionHandler = { @Sendable [weak self] in Task { @MainActor in self?.processStopped(id) } }
            connection.resume()
            processes[id] = process
            connections[id] = connection
            proxy(id)?.manifest { [weak self] data in
                let payload = ExtensionWire.decode(ExtensionManifestPayload.self, from: data)
                Task { @MainActor in self?.received(payload, for: id) }
            }
        } catch {
            update(id) { $0.status = .failed(error.localizedDescription) }
        }
    }

    func configureHostSide(of connection: NSXPCConnection, for id: String) {
        connection.exportedInterface = .aletheHost()
        connection.exportedObject = ExtensionHostService(bundleIdentifier: id, manager: self)
    }

    private func proxy(_ id: String) -> (any AletheExtensionXPC)? {
        connections[id]?.remoteObjectProxyWithErrorHandler { @Sendable [weak self] _ in
            Task { @MainActor in self?.processStopped(id) }
        } as? any AletheExtensionXPC
    }

    private func received(_ payload: ExtensionManifestPayload?, for id: String) {
        guard let payload else {
            update(id) { $0.status = .failed(String(localized: "extensions.error.manifest")) }
            return
        }
        do {
            let manifest = try ExtensionCapabilityMapper.manifest(for: ExtensionDescriptor(bundleIdentifier: id, payload: payload))
            update(id) {
                $0.payload = payload
                $0.manifest = manifest
                $0.status = .ready
            }
        } catch {
            update(id) { $0.status = .failed(String(describing: error)) }
        }
    }

    private func processStopped(_ id: String) {
        guard processes[id] != nil else { return }
        teardown(id)
        update(id) { entry in
            if entry.status != .loading || entry.payload != nil { entry.status = .stopped }
            else { entry.status = .failed(String(localized: "extensions.error.manifest")) }
        }
    }

    private func teardown(_ id: String) {
        connections.removeValue(forKey: id)?.invalidate()
        processes.removeValue(forKey: id)?.invalidate()
    }

    func reload(_ id: String) {
        guard let entry = entries.first(where: { $0.id == id }) else { return }
        teardown(id)
        update(id) { $0.status = .loading }
        connect(entry.identity)
    }

    private func update(_ id: String, _ change: (inout Entry) -> Void) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let before = entries[index].status
        change(&entries[index])
        if case .failed(let error) = entries[index].status, entries[index].status != before {
            events.publish(.pluginFailed(id: id, error: error))
        }
    }

    func isActive(_ entry: Entry) -> Bool {
        guard let manifest = entry.manifest else { return false }
        return state.isActive(manifest)
    }

    func setEnabled(_ enabled: Bool, for id: String) {
        guard let manifest = entries.first(where: { $0.id == id })?.manifest else { return }
        if enabled {
            let enableResult = state.requestEnable(manifest)
            if case .enabled = enableResult {
                save()
            } else if case .needsConsent(let capabilities) = enableResult {
                pendingConsent = ConsentRequest(manifest: manifest, capabilities: capabilities)
            }
        } else {
            state.disable(id)
            save()
        }
    }

    func resolveConsent(approved: Bool) {
        guard let request = pendingConsent else { return }
        pendingConsent = nil
        if approved { state.approve(request.manifest) } else { state.decline(request.manifest) }
        save()
    }

    private func save() {
        try? state.save(to: stateURL)
    }

    func runCommand(_ commandID: String, of id: String) {
        guard let entry = entries.first(where: { $0.id == id }), isActive(entry) else { return }
        proxy(id)?.runCommand(commandID) { [weak self] reply in
            Task { @MainActor in self?.update(id) { $0.lastReply = reply } }
        }
    }

    func handle(_ request: HostRequest, from id: String) async -> HostResponse {
        let storage = storages[id] ?? PluginStorage(root: dataRoot, pluginID: ExtensionRequestRouter.storageID(for: id))
        storages[id] = storage
        let state = self.state
        return await ExtensionRequestRouter.handle(request, isAllowed: { state.isAllowed($0, for: id) }, storage: storage)
    }

    var sidebarTabs: [SidebarTabContribution] {
        entries.compactMap { entry in
            guard isActive(entry), let tab = entry.payload?.sidebarTab else { return nil }
            return SidebarTabContribution(id: Self.tabPrefix + entry.id, title: tab.title, symbol: tab.symbol,
                                          side: .right, viewID: Self.tabPrefix + entry.id)
        }
    }

    static let tabPrefix = "extension:"

    func identity(forViewID viewID: String) -> AppExtensionIdentity? {
        guard viewID.hasPrefix(Self.tabPrefix) else { return nil }
        let id = String(viewID.dropFirst(Self.tabPrefix.count))
        return entries.first { $0.id == id && isActive($0) }?.identity
    }

    func shutdown() async {
        for id in Array(processes.keys) { teardown(id) }
        for storage in storages.values { try? await storage.flush() }
    }
}

final class ExtensionHostService: NSObject, AletheHostXPC, @unchecked Sendable {
    private let bundleIdentifier: String
    private weak var manager: ExtensionManager?

    init(bundleIdentifier: String, manager: ExtensionManager) {
        self.bundleIdentifier = bundleIdentifier
        self.manager = manager
    }

    func handle(_ request: Data, reply: @escaping @Sendable (Data) -> Void) {
        guard let request = ExtensionWire.decode(HostRequest.self, from: request) else {
            reply(ExtensionWire.encode(HostResponse.failed("malformed request")))
            return
        }
        let id = bundleIdentifier
        Task { @MainActor [weak manager] in
            let response = await manager?.handle(request, from: id) ?? .failed("host unavailable")
            reply(ExtensionWire.encode(response))
        }
    }
}
