import AletheAgents
import AletheModel

extension Router9 {
    public static func routingAvailable(_ preferences: Router9Preferences, hasAPIKey: Bool, hasInstall: Bool,
                                        agent: AgentKind) -> Bool {
        preferences.enabled && hasAPIKey && hasInstall && supports(agent)
    }

    public static func launchEnvironment(for tab: PaneTab, config: Router9RoutingConfig?) -> [String: String] {
        guard tab.useRouter9 == true else { return [:] }
        return environment(for: AgentKind(rawValue: tab.agent), config: config)
    }

    public static func wantsRouting(_ tab: PaneTab) -> Bool {
        tab.useRouter9 == true && supports(AgentKind(rawValue: tab.agent))
    }
}
