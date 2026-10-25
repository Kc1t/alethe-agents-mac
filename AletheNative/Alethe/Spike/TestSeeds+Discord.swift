#if DEBUG
import AletheIntegrations
import AletheModel

extension TestSeeds {
    static let discordClient: any DiscordPresenceClient = SilentDiscordClient()

    static func seedDiscord(_ name: String, into doc: inout WorkspaceDocument) {}

    static func seedDiscord(_ name: String, into preferences: inout PreferencesDocument) {
        if name == "discordPresence" { preferences.discordPresence = true }
    }

    @MainActor
    static func seedDiscord(_ name: String, environment: AppEnvironment) {}
}

private struct SilentDiscordClient: DiscordPresenceClient {
    func setActivity(_ activity: DiscordActivity) async -> Bool { true }
    func clearActivity() async {}
}
#endif
