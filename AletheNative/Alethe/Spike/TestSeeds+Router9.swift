#if DEBUG
import AletheIntegrations
import AletheModel
import Foundation

extension TestSeeds {
    static let router9RouteSeeds: Set<String> = ["router9Route", "router9RouteKeyless"]

    private static var router9DataRoot: URL {
        URL(filePath: UserDefaults.standard.string(forKey: "AletheDataRoot") ?? "/private/tmp")
    }

    private static var fakeRoutedClaudePath: String { router9DataRoot.appending(path: "fake-claude").path }

    static func seedRouter9(_ name: String, into doc: inout WorkspaceDocument) {
        guard router9RouteSeeds.contains(name) else { return }
        let project = doc.addProject(name: "routed", folder: "/private/tmp", color: .purple)
        doc.workspace.selectedProjectID = project
    }

    static func seedRouter9(_ name: String, into preferences: inout PreferencesDocument) {
        guard name == "router9" || router9RouteSeeds.contains(name) else { return }
        preferences.router9 = Router9Preferences(enabled: true)
        preferences.setToolbarItem(.router9, shown: true)
        if router9RouteSeeds.contains(name) {
            writeFakeRoutedClaude()
            var paths = preferences.cliPaths ?? [:]
            paths["claude"] = fakeRoutedClaudePath
            preferences.cliPaths = paths
        }
    }

    @MainActor
    static func seedRouter9(_ name: String, environment: AppEnvironment) {
        let routes = router9RouteSeeds.contains(name)
        guard name == "router9" || name == "router9Fresh" || routes,
              let locations = environment.locations, let profile = environment.profileID else { return }
        let paths = Router9Paths(profileDirectory: locations.profileDirectory(profile))
        if name != "router9Fresh" { writeStubRouter9Install(paths) }
        if name == "router9Route" { environment.router9.saveAPIKey("9r_uitest_route") }
        environment.router9.useStubService(Router9Dependencies(
            resolveExternal: { nil },
            resolveNode: { "/bin/sh" },
            probeVersion: { _ in nil },
            isPortInUse: { _ in false },
            searchDirectories: { [] }
        ))
    }

    private static func writeFakeRoutedClaude() {
        let script = #"""
        #!/bin/sh
        if [ -n "$ANTHROPIC_BASE_URL" ] && [ -n "$ANTHROPIC_AUTH_TOKEN" ]; then
          echo "ROUTED ${ANTHROPIC_BASE_URL#http://}"
        else
          echo "UNROUTED"
        fi
        exec /bin/sleep 600
        """#
        try? FileManager.default.createDirectory(at: router9DataRoot, withIntermediateDirectories: true)
        let url = URL(filePath: fakeRoutedClaudePath)
        try? Data(script.utf8).write(to: url)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func writeStubRouter9Install(_ paths: Router9Paths) {
        let package = paths.entryScript.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try? Data("{\"name\":\"9router\",\"version\":\"\(Router9.pinnedVersion)\"}".utf8)
            .write(to: package.appending(path: "package.json"))
        try? Data("exec /bin/sleep 600\n".utf8).write(to: paths.entryScript)
    }
}
#endif
