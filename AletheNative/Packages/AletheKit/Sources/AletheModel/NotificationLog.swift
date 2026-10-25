import Foundation

public struct AppNotification: Identifiable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var body: String
    public var tab: TabID?
    public var agent: String?
    public var createdAt: Date

    public init(id: UUID = UUID(), title: String, body: String, tab: TabID? = nil, agent: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.tab = tab
        self.agent = agent
        self.createdAt = createdAt
    }
}

public struct NotificationLog: Sendable {
    public static let capacity = 12
    public static let duplicateWindow: TimeInterval = 5

    public private(set) var entries: [AppNotification] = []
    public private(set) var unseen = 0

    public init() {}

    @discardableResult
    public mutating func post(_ notification: AppNotification) -> Bool {
        if let last = entries.first, last.title == notification.title, last.body == notification.body,
           notification.createdAt.timeIntervalSince(last.createdAt) < Self.duplicateWindow {
            return false
        }
        entries = Array(([notification] + entries).prefix(Self.capacity))
        unseen = min(unseen + 1, Self.capacity)
        return true
    }

    public mutating func markSeen() { unseen = 0 }

    public mutating func clear() {
        entries = []
        unseen = 0
    }
}
