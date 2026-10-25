import Foundation

public enum Router9Source: String, Codable, CaseIterable, Hashable, Sendable {
    case managed
    case external
}

public struct Router9Preferences: Codable, Hashable, Sendable {
    public static let defaultPort = 20128

    public var enabled: Bool
    public var autoStart: Bool
    public var source: Router9Source
    public var port: Int {
        didSet { port = Self.normalizedPort(port) }
    }
    public var defaultForNewAgents: Bool

    public init(enabled: Bool = false, autoStart: Bool = false, source: Router9Source = .managed,
                port: Int = defaultPort, defaultForNewAgents: Bool = false) {
        self.enabled = enabled
        self.autoStart = autoStart
        self.source = source
        self.port = Self.normalizedPort(port)
        self.defaultForNewAgents = defaultForNewAgents
    }

    public static func normalizedPort(_ port: Int) -> Int {
        (1...65535).contains(port) ? port : defaultPort
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, autoStart, source, port, defaultForNewAgents
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            enabled: (try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? false,
            autoStart: (try? container.decodeIfPresent(Bool.self, forKey: .autoStart)) ?? false,
            source: (try? container.decodeIfPresent(Router9Source.self, forKey: .source)) ?? .managed,
            port: (try? container.decodeIfPresent(Int.self, forKey: .port)) ?? Self.defaultPort,
            defaultForNewAgents: (try? container.decodeIfPresent(Bool.self, forKey: .defaultForNewAgents)) ?? false
        )
    }
}

public struct RemotePreferences: Codable, Hashable, Sendable {
    public static let maxDevicesRange = 1...4
    public static let sessionExpiryRange = (5 * 60)...(24 * 60 * 60)
    public static let defaultSessionExpiry = 60 * 60

    public var maxDevices: Int {
        didSet { maxDevices = Self.clamp(maxDevices, Self.maxDevicesRange) }
    }
    public var sessionExpirySecs: Int {
        didSet { sessionExpirySecs = Self.clamp(sessionExpirySecs, Self.sessionExpiryRange) }
    }
    public var readOnly: Bool
    public var allowShellInput: Bool
    public var useTailscale: Bool

    public init(maxDevices: Int = 1, sessionExpirySecs: Int = defaultSessionExpiry, readOnly: Bool = true,
                allowShellInput: Bool = false, useTailscale: Bool = false) {
        self.maxDevices = Self.clamp(maxDevices, Self.maxDevicesRange)
        self.sessionExpirySecs = Self.clamp(sessionExpirySecs, Self.sessionExpiryRange)
        self.readOnly = readOnly
        self.allowShellInput = allowShellInput
        self.useTailscale = useTailscale
    }

    static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }

    private enum CodingKeys: String, CodingKey {
        case maxDevices, sessionExpirySecs, readOnly, allowShellInput, useTailscale
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            maxDevices: (try? container.decodeIfPresent(Int.self, forKey: .maxDevices)) ?? 1,
            sessionExpirySecs: (try? container.decodeIfPresent(Int.self, forKey: .sessionExpirySecs))
                ?? Self.defaultSessionExpiry,
            readOnly: (try? container.decodeIfPresent(Bool.self, forKey: .readOnly)) ?? true,
            allowShellInput: (try? container.decodeIfPresent(Bool.self, forKey: .allowShellInput)) ?? false,
            useTailscale: (try? container.decodeIfPresent(Bool.self, forKey: .useTailscale)) ?? false
        )
    }
}
