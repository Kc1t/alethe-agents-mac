import Darwin
import Foundation
import GhosttyTerminal

public enum ShellLaunch {
    public nonisolated(unsafe) static var shellOverride: String?

    public static var userShell: String {
        if let shellOverride, FileManager.default.isExecutableFile(atPath: shellOverride) { return shellOverride }
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return "/bin/zsh"
    }

    public static func environment(base: [String: String] = ProcessInfo.processInfo.environment) -> [String: String] {
        var env = base
        env["TERM"] = "xterm-ghostty"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "Alethe"
        if let terminfo = GhosttyRuntimeResources.terminfoDirectoryURL?.path {
            env["TERMINFO"] = terminfo
        }
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        for key in ["TERM_SESSION_ID", "ITERM_SESSION_ID", "GHOSTTY_RESOURCES_DIR", "XPC_SERVICE_NAME"] {
            env.removeValue(forKey: key)
        }
        return env
    }

    public static func loginShell(command: String? = nil, workingDirectory: String? = nil,
                                  size: PTYSize = PTYSize(columns: 80, rows: 24),
                                  environmentChanges: [String: String?] = [:]) -> PTYLaunch {
        let shell = userShell
        var env = environment()
        for (key, value) in environmentChanges { env[key] = value }
        let name = "-" + (shell as NSString).lastPathComponent
        let arguments = command.map { [name, "-c", $0] } ?? [name]
        let launch = PTYLaunch(
            executable: shell,
            arguments: arguments,
            environment: env,
            workingDirectory: workingDirectory ?? NSHomeDirectory(),
            size: size
        )
        return command == nil ? ShellIntegration.apply(to: launch) : launch
    }
}
