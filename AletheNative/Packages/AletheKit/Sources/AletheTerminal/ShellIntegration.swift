import Foundation
import GhosttyTerminal

public enum ShellIntegration {
    public enum Shell: Equatable, Sendable {
        case zsh, bash
    }

    public static let features = "cursor,title"

    public static func detect(executable: String) -> Shell? {
        switch (executable as NSString).lastPathComponent {
        case "zsh": .zsh
        case "bash" where executable != "/bin/bash": .bash
        default: nil
        }
    }

    public static func apply(to launch: PTYLaunch,
                             resources: URL? = GhosttyRuntimeResources.directoryURL,
                             home: String = NSHomeDirectory(),
                             fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> PTYLaunch {
        guard let resources, let shell = detect(executable: launch.executable),
              !launch.arguments.dropFirst().contains(where: isCommandFlag) else { return launch }
        let root = resources.appending(path: "shell-integration").path
        var result = launch
        switch shell {
        case .zsh:
            let directory = root + "/zsh"
            guard fileExists(directory + "/.zshenv") else { return launch }
            if let old = launch.environment["ZDOTDIR"] { result.environment["GHOSTTY_ZSH_ZDOTDIR"] = old }
            result.environment["ZDOTDIR"] = directory
        case .bash:
            let script = root + "/bash/ghostty.bash"
            guard fileExists(script), let bash = bashArguments(launch.arguments) else { return launch }
            result.arguments = bash.arguments
            if let old = launch.environment["ENV"] { result.environment["GHOSTTY_BASH_ENV"] = old }
            result.environment["ENV"] = script
            result.environment["GHOSTTY_BASH_INJECT"] = bash.inject
            if let rcfile = bash.rcfile { result.environment["GHOSTTY_BASH_RCFILE"] = rcfile }
            if launch.environment["HISTFILE"] == nil {
                result.environment["HISTFILE"] = home + "/.bash_history"
                result.environment["GHOSTTY_BASH_UNEXPORT_HISTFILE"] = "1"
            }
        }
        result.environment["GHOSTTY_SHELL_FEATURES"] = features
        return result
    }

    private static func isCommandFlag(_ argument: String) -> Bool {
        argument.count > 1 && argument.hasPrefix("-") && !argument.hasPrefix("--") && argument.contains("c")
    }

    static func bashArguments(_ arguments: [String]) -> (arguments: [String], inject: String, rcfile: String?)? {
        guard let executable = arguments.first else { return nil }
        var result = [executable, "--posix"]
        var inject = "1"
        var rcfile: String?
        var rest = arguments.dropFirst()[...]
        while let argument = rest.popFirst() {
            switch argument {
            case "--posix":
                return nil
            case "--norc", "--noprofile":
                inject += " " + argument
            case "--rcfile", "--init-file":
                rcfile = rest.popFirst()
            case "-", "--":
                result.append(argument)
                result.append(contentsOf: rest)
                rest = []
            default:
                if isCommandFlag(argument) { return nil }
                result.append(argument)
            }
        }
        return (result, inject, rcfile)
    }
}
