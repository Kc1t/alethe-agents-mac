import Foundation

public enum ProjectStack: String, Codable, CaseIterable, Sendable {
    case web, cli, desktop, fullstack, unknown
}

public struct StackDetection: Codable, Equatable, Sendable {
    public var stack: ProjectStack
    public var hasFrontend: Bool
    public var hasBackend: Bool
    public var hasTauri: Bool
    public var suggestedCommands: [String]

    public init(stack: ProjectStack, hasFrontend: Bool, hasBackend: Bool, hasTauri: Bool, suggestedCommands: [String]) {
        self.stack = stack
        self.hasFrontend = hasFrontend
        self.hasBackend = hasBackend
        self.hasTauri = hasTauri
        self.suggestedCommands = suggestedCommands
    }
}

public enum ProjectStackDetector {
    public enum Failure: Error, Equatable, Sendable {
        case folderNotFound
    }

    static let frontendDependencies = ["react", "vue", "svelte", "next", "vite", "@angular/core"]

    public static func detect(_ root: URL) throws(Failure) -> StackDetection {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw .folderNotFound
        }
        func has(_ name: String) -> Bool { isFile(root.appending(path: name)) }

        let hasTauri = has("tauri.conf.json") || has("src-tauri/tauri.conf.json")
        let hasFrontend = has("package.json") && packageHasFrontendSignal(root.appending(path: "package.json"))
        let hasPython = has("requirements.txt") || has("pyproject.toml")
        let hasBackend = hasPython || has("go.mod") || (has("Cargo.toml") && !hasTauri)

        let stack: ProjectStack = if hasTauri {
            .desktop
        } else if hasFrontend && hasBackend {
            .fullstack
        } else if hasFrontend {
            .web
        } else if hasBackend {
            .cli
        } else {
            .unknown
        }

        let commands = suggestedCommands(
            for: stack, pythonCommands: hasPython ? ["python -m py_compile ."] : [], has: has)
        return StackDetection(stack: stack, hasFrontend: hasFrontend, hasBackend: hasBackend, hasTauri: hasTauri,
                              suggestedCommands: commands)
    }

    private static func suggestedCommands(for stack: ProjectStack, pythonCommands: [String],
                                          has: (String) -> Bool) -> [String] {
        var commands: [String] = []
        if stack == .desktop {
            commands = ["npm run build", "cargo check --manifest-path src-tauri/Cargo.toml"]
        } else if stack == .web {
            commands = ["npm run build"]
        } else if stack == .fullstack {
            commands = ["npm run build"]
            commands.append(contentsOf: pythonCommands)
            if has("Cargo.toml") { commands.append("cargo check") }
            if has("go.mod") { commands.append("go build ./...") }
        } else if stack == .cli {
            if has("Cargo.toml") { commands.append("cargo check") }
            if has("go.mod") { commands.append("go build ./...") }
            commands.append(contentsOf: pythonCommands)
        }
        return commands
    }

    private static func isFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    private static func packageHasFrontendSignal(_ file: URL) -> Bool {
        guard let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        if let scripts = json["scripts"] as? [String: Any],
           scripts["dev"] != nil || scripts["build"] != nil || scripts["start"] != nil {
            return true
        }
        let dependencies = json["dependencies"] as? [String: Any] ?? [:]
        let devDependencies = json["devDependencies"] as? [String: Any] ?? [:]
        return frontendDependencies.contains { dependencies[$0] != nil || devDependencies[$0] != nil }
    }
}
