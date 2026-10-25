import AletheAgents
import AletheTerminal

extension AgentCommand {
    func ptyLaunch(size: PTYSize) -> PTYLaunch {
        ShellLaunch.loginShell(command: shellCommand, workingDirectory: workingDirectory, size: size,
                               environmentChanges: environment)
    }
}
