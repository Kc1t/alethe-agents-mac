import Foundation

public struct RemoteControlSettings: Equatable, Sendable {
    public var maxDevices: Int
    public var sessionExpirySecs: Int
    public var readOnly: Bool
    public var allowShellInput: Bool
    public var reachMode: RemoteReachMode

    public init(maxDevices: Int = 1, sessionExpirySecs: Int = Int(RemoteLimits.defaultSessionExpiry), readOnly: Bool = true,
                allowShellInput: Bool = false, reachMode: RemoteReachMode = .lan) {
        self.maxDevices = maxDevices
        self.sessionExpirySecs = sessionExpirySecs
        self.readOnly = readOnly
        self.allowShellInput = allowShellInput
        self.reachMode = reachMode
    }
}

public actor RemoteControlService {
    public nonisolated let hub: RemoteHub
    private let transport: RemoteTransport

    public init(
        hub: RemoteHub = RemoteHub(),
        terminals: any RemoteTerminalSource,
        workspace: any RemoteWorkspaceSource,
        assets: any RemoteAssetSource,
        configuration: RemoteTransport.Configuration = .standard
    ) {
        self.hub = hub
        let api = RemoteAPI(hub: hub, terminals: terminals, workspace: workspace, assets: assets)
        transport = RemoteTransport(hub: hub, router: api, terminals: terminals, workspace: workspace,
                                    configuration: configuration)
    }

    public nonisolated var events: AsyncStream<RemoteEvent> { hub.events }

    public func info() async -> RemoteInfo {
        await hub.info()
    }

    @discardableResult
    public func setEnabled(_ enabled: Bool) async -> RemoteInfo {
        if enabled {
            await transport.start()
        } else {
            await transport.stop()
        }
        return await hub.info()
    }

    @discardableResult
    public func apply(_ settings: RemoteControlSettings) async -> Bool {
        await hub.setMaxDevices(settings.maxDevices)
        await hub.setSessionExpiry(TimeInterval(settings.sessionExpirySecs))
        await hub.setReadOnly(settings.readOnly)
        await hub.setAllowShellInput(settings.allowShellInput)
        guard await hub.setReachMode(settings.reachMode), await hub.isEnabled else { return false }
        await transport.stop()
        await transport.start()
        return true
    }

    @discardableResult
    public func openPairing() async -> RemoteInfo {
        if await hub.isEnabled {
            await hub.refreshHost()
            await hub.openPairingWindow()
        }
        return await hub.info()
    }

    @discardableResult
    public func closePairing() async -> RemoteInfo {
        await hub.closePairingWindow()
        return await hub.info()
    }

    @discardableResult
    public func revoke(deviceID: Int) async -> RemoteInfo {
        await hub.revokeDevice(deviceID)
        return await hub.info()
    }

    @discardableResult
    public func revokeAll() async -> RemoteInfo {
        await hub.revokeAll()
        await hub.closePairingWindow()
        return await hub.info()
    }

    public func stop() async {
        await transport.stop()
    }
}
