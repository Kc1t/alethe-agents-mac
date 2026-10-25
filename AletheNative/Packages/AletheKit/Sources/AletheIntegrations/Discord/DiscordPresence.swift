import Foundation

public enum DiscordPresenceView: Hashable, Sendable {
    case dashboard
    case terminals
    case orchestration

    public var state: String {
        switch self {
        case .dashboard: "Viewing the dashboard"
        case .terminals: "Managing terminals"
        case .orchestration: "Orchestrating AI agents"
        }
    }
}

@MainActor
public final class DiscordPresenceSession {
    public static let details = "Working with Alethe"
    public static let refreshInterval: Duration = .seconds(30)

    private let client: any DiscordPresenceClient
    private let startedAt: Int64
    private let refreshInterval: Duration
    private(set) public var current: DiscordPresenceView?
    private var wasEnabled = false
    private var stopped = false
    private var refresh: Task<Void, Never>?
    private var queue: Task<Void, Never>?

    public init(client: any DiscordPresenceClient, startedAt: Date = Date(),
                refreshInterval: Duration = DiscordPresenceSession.refreshInterval) {
        self.client = client
        self.startedAt = Int64(startedAt.timeIntervalSince1970)
        self.refreshInterval = refreshInterval
    }

    public func activity(for view: DiscordPresenceView) -> DiscordActivity {
        DiscordActivity(details: Self.details, state: view.state, startedAt: startedAt)
    }

    public func update(enabled: Bool, view: DiscordPresenceView) {
        guard !stopped else { return }
        guard enabled else {
            refresh?.cancel()
            refresh = nil
            current = nil
            if wasEnabled { enqueue { client in await client.clearActivity() } }
            wasEnabled = false
            return
        }
        guard current != view else { return }
        current = view
        wasEnabled = true
        let activity = activity(for: view)
        enqueue { client in await client.setActivity(activity) }
        refresh?.cancel()
        let interval = refreshInterval
        refresh = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled, let self else { return }
                self.enqueue { client in await client.setActivity(activity) }
            }
        }
    }

    public func stop() async {
        guard !stopped else { return }
        stopped = true
        refresh?.cancel()
        refresh = nil
        current = nil
        if wasEnabled { enqueue { client in await client.clearActivity() } }
        wasEnabled = false
        await queue?.value
    }

    public func settle() async {
        await queue?.value
    }

    private func enqueue(_ operation: @escaping @Sendable (any DiscordPresenceClient) async -> Void) {
        let previous = queue
        let client = client
        queue = Task {
            await previous?.value
            await operation(client)
        }
    }
}
