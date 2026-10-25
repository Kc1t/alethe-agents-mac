import Foundation

public enum AletheExtensionPoint {
    public static let hostBundleIdentifier = "com.kc1t.alethe.mac"
    public static let name = "sidebar-tab"
    public static let sidebarSceneID = "sidebar"
}

public struct ExtensionManifestPayload: Codable, Sendable, Equatable {
    public struct Command: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String

        public init(id: String, title: String) {
            self.id = id
            self.title = title
        }
    }

    public struct SidebarTab: Codable, Sendable, Equatable {
        public var title: String
        public var symbol: String

        public init(title: String, symbol: String) {
            self.title = title
            self.symbol = symbol
        }
    }

    public var name: String
    public var version: String
    public var apiMajor: Int
    public var apiMinor: Int
    public var capabilities: [String]
    public var commands: [Command]
    public var sidebarTab: SidebarTab?

    public init(
        name: String,
        version: String,
        apiMajor: Int = 1,
        apiMinor: Int = 0,
        capabilities: [String],
        commands: [Command] = [],
        sidebarTab: SidebarTab? = nil
    ) {
        self.name = name
        self.version = version
        self.apiMajor = apiMajor
        self.apiMinor = apiMinor
        self.capabilities = capabilities
        self.commands = commands
        self.sidebarTab = sidebarTab
    }
}

public enum HostRequest: Codable, Sendable, Equatable {
    case storageGet(key: String)
    case storageSet(key: String, value: String?)
}

public enum HostResponse: Codable, Sendable, Equatable {
    case value(String?)
    case done
    case denied(capability: String)
    case failed(String)
}

public enum ExtensionWire {
    public static func encode<T: Encodable>(_ value: T) -> Data {
        (try? JSONEncoder().encode(value)) ?? Data()
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? JSONDecoder().decode(type, from: data)
    }
}

@objc public protocol AletheHostXPC {
    func handle(_ request: Data, reply: @escaping @Sendable (Data) -> Void)
}

@objc public protocol AletheExtensionXPC {
    func manifest(reply: @escaping @Sendable (Data) -> Void)
    func runCommand(_ id: String, reply: @escaping @Sendable (String?) -> Void)
}

extension NSXPCInterface {
    public static func aletheHost() -> NSXPCInterface { NSXPCInterface(with: AletheHostXPC.self) }
    public static func aletheExtension() -> NSXPCInterface { NSXPCInterface(with: AletheExtensionXPC.self) }
}
