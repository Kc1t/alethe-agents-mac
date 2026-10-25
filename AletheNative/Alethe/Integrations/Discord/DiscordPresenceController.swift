import AletheIntegrations
import AletheModel
import Foundation
import Observation

@Observable
@MainActor
final class DiscordPresenceController {
    @ObservationIgnored private var session: DiscordPresenceSession?
    @ObservationIgnored private let launchedAt = Date()

    func start(environment: AppEnvironment) {
        guard session == nil else { return }
        session = DiscordPresenceSession(client: Self.makeClient(), startedAt: launchedAt)
        follow(environment)
    }

    func stop() async {
        await session?.stop()
    }

    private func follow(_ environment: AppEnvironment) {
        let (enabled, view) = withObservationTracking {
            (environment.preferences?.document.showsDiscordPresence ?? false, Self.view(in: environment))
        } onChange: { [weak self, weak environment] in
            Task { @MainActor in
                guard let self, let environment else { return }
                self.follow(environment)
            }
        }
        session?.update(enabled: enabled, view: view)
    }

    static func view(in environment: AppEnvironment) -> DiscordPresenceView {
        if environment.showingHome { return .dashboard }
        guard let document = environment.workspace?.document,
              let paneID = environment.focusModePaneID ?? document.workspace.focusedPaneID,
              let found = document.pane(paneID),
              found.project.id == document.workspace.selectedProjectID
        else { return .terminals }
        if case .orchestrator = found.pane.content { return .orchestration }
        return .terminals
    }

    private static func makeClient() -> any DiscordPresenceClient {
        #if DEBUG
        if UserDefaults.standard.string(forKey: "AletheDataRoot") != nil { return TestSeeds.discordClient }
        #endif
        return DiscordIPCClient()
    }
}
