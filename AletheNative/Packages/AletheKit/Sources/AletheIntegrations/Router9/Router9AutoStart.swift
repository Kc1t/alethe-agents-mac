import AletheModel

extension Router9Source {
    public init(_ preference: AletheModel.Router9Source) {
        switch preference {
        case .managed: self = .managed
        case .external: self = .external
        }
    }
}

extension Router9RoutingConfig {
    public init(_ preferences: Router9Preferences, apiKey: String) {
        self.init(enabled: preferences.enabled, port: preferences.port, apiKey: apiKey)
    }
}

extension Router9 {
    public static func wantsAutoStart(_ preferences: Router9Preferences) -> Bool {
        preferences.enabled && preferences.autoStart
    }

    public static func autoStartSource(_ preferences: Router9Preferences, status: Router9Status?) -> Router9Source? {
        guard wantsAutoStart(preferences), let status, !status.running, !status.portInUse else { return nil }
        return resolveSource(status, preferred: Router9Source(preferences.source))?.source
    }
}
