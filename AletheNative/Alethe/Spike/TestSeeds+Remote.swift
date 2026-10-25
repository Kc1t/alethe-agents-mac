#if DEBUG
import AletheModel
import AletheRemote
import Foundation

extension TestSeeds {
    static let remoteSeeds: Set<String> = ["remote", "remoteMessage", remoteE2E]
    static let remoteE2E = "remoteE2E"
    static let remoteStubDevice = "Test Phone"

    private static var remoteDataRoot: URL {
        URL(filePath: UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp")
    }

    static var fakeClaudePath: String { remoteDataRoot.appending(path: "fake-claude").path }

    static func seedRemote(_ name: String, into doc: inout WorkspaceDocument) {
        guard remoteSeeds.contains(name) else { return }
        let project = doc.addProject(name: "remote", folder: remoteDataRoot.path, color: .teal)
        let sharedAgent = name == remoteE2E ? "claude" : "shell"
        if name == remoteE2E { writeFakeClaude() }
        if let shared = doc.addPane(to: project, tab: PaneTab(agent: sharedAgent, title: "shared")) {
            doc.setRemoteShared(shared, true)
        }
        doc.addPane(to: project, tab: PaneTab(agent: "shell", title: "private"))
        doc.workspace.selectedProjectID = project
    }

    static func seedRemote(_ name: String, into preferences: inout PreferencesDocument) {
        guard remoteSeeds.contains(name) else { return }
        guard name == remoteE2E else {
            preferences.remote = RemotePreferences(maxDevices: 2, readOnly: false, allowShellInput: true)
            return
        }
        preferences.remote = RemotePreferences(maxDevices: 1, readOnly: false, allowShellInput: false)
        var paths = preferences.cliPaths ?? [:]
        paths["claude"] = fakeClaudePath
        preferences.cliPaths = paths
    }

    @MainActor
    static func seedRemote(_ name: String, environment: AppEnvironment) {
        guard remoteSeeds.contains(name) else { return }
        let remote = environment.remoteControl
        remote.setEnabled(true)
        guard name == "remoteMessage",
              let tab = environment.workspace?.document.remoteSharedTerminals.first?.tab.id else { return }
        remote.emitForTesting(.message(RemoteMessageEvent(
            terminalID: tab.rawValue, deviceID: 1, deviceName: remoteStubDevice, preview: "hello from the phone")))
    }

    private static func writeFakeClaude() {
        let script = """
        #!/bin/sh
        trap 'echo "fake-claude interrupted"' INT
        echo "fake-claude ready"
        while :; do
          if IFS= read -r line; then echo "fake-claude got: $line"; else sleep 1; fi
        done

        """
        let url = URL(filePath: fakeClaudePath)
        try? FileManager.default.createDirectory(at: remoteDataRoot, withIntermediateDirectories: true)
        try? Data(script.utf8).write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
#endif
