import Foundation

public enum CLIVersion {
    public static let flags = ["--version", "-v", "version"]

    public static func parse(_ output: String) -> String? {
        output.split { !($0.isNumber || $0 == ".") }
            .first { $0.contains(".") && $0.first?.isNumber == true }
            .map { String($0).trimmingCharacters(in: CharacterSet(charactersIn: ".")) }
    }

    public static func probe(_ executable: String, timeout: Duration = .seconds(5)) async -> String? {
        for flag in flags {
            if let version = await run(executable, flag, timeout: timeout).flatMap(parse) { return version }
        }
        return nil
    }

    private static func run(_ executable: String, _ flag: String, timeout: Duration) async -> String? {
        await CLIOutput.run(executable, [flag], timeout: timeout)
    }
}

public enum CLIOutput {
    public static func run(_ executable: String, _ arguments: [String], timeout: Duration,
                           directory: String? = nil) async -> String? {
        let process = Process()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        if let directory, FileManager.default.fileExists(atPath: directory) {
            process.currentDirectoryURL = URL(filePath: directory, directoryHint: .isDirectory)
        }
        var environment = ProcessInfo.processInfo.environment
        let directory = (executable as NSString).deletingLastPathComponent
        environment["PATH"] = directory + ":" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let reader = Task.detached { String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self) }
        let watchdog = Task.detached {
            try? await Task.sleep(for: timeout)
            if process.isRunning { process.terminate() }
        }
        let text = await reader.value
        watchdog.cancel()
        return text
    }
}
