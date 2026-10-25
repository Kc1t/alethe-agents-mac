import Foundation

public enum AgentActivity: String, Hashable, Sendable {
    case idle
    case working
    case needsInput
    case done
}

public struct AgentHookEvent: Equatable, Sendable {
    public var activity: AgentActivity?
    public var sessionID: String?
    public var message: String?

    public init(activity: AgentActivity? = nil, sessionID: String? = nil, message: String? = nil) {
        self.activity = activity
        self.sessionID = sessionID
        self.message = message
    }

    public static func claude(_ body: Data) -> AgentHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let name = object["hook_event_name"] as? String else { return nil }
        let session = (object["session_id"] as? String).flatMap { $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 }
        if case "SessionStart" = name {
            return AgentHookEvent(activity: .idle, sessionID: session)
        } else if case "UserPromptSubmit" = name {
            return AgentHookEvent(activity: .working, sessionID: session)
        } else if case "Stop" = name {
            return AgentHookEvent(activity: .done)
        } else if case "Notification" = name {
            let message = object["message"] as? String
            let idle = message?.lowercased().contains("waiting for your input") == true
            return AgentHookEvent(activity: idle ? .done : .needsInput, message: message)
        } else {
            return nil
        }
    }

    public static func codex(_ body: Data) -> AgentHookEvent? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              object["type"] as? String == "agent-turn-complete" else { return nil }
        let message = object["last-assistant-message"] as? String
        return AgentHookEvent(activity: .done, message: message)
    }
}

public enum AgentHookWiring {
    public static let events = ["SessionStart", "UserPromptSubmit", "Stop", "Notification"]

    public static let orchestratorEvents = ["SubagentStart", "SubagentStop", "PreToolUse", "PostToolUse",
                                            "TeammateIdle", "TaskCreated", "TaskCompleted"]

    public static func claudeSettings(endpoint: String, token: String, tab: String, orchestrator: Bool = false) -> Data {
        let hook: [[String: Any]] = [["hooks": [[
            "type": "http", "url": "\(endpoint)/hook/claude", "timeout": 5,
            "headers": ["X-Alethe-Token": token, "X-Alethe-Tab": tab],
        ]]]]
        let names = orchestrator ? events + orchestratorEvents : events
        var settings: [String: Any] = ["hooks": Dictionary(uniqueKeysWithValues: names.map { ($0, hook) })]
        if orchestrator { settings["teammateMode"] = "in-process" }
        return (try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }

    public static func codexForwarder(endpoint: String, token: String) -> String {
        """
        #!/bin/sh
        # Alethe: forwards a Codex notification to the app (tab id, then the event JSON).
        exec /usr/bin/curl -s -m 5 -o /dev/null -X POST \\
          -H "X-Alethe-Token: \(token)" -H "X-Alethe-Tab: $1" -H "Content-Type: application/json" \\
          --data-binary "$2" "\(endpoint)/hook/codex"
        """
    }

    public static func codexArguments(script: String, tab: String) -> [String] {
        ["-c", "notify=[\(["/bin/sh", script, tab].map(toml).joined(separator: ","))]"]
    }

    public static func codexHookForwarder(endpoint: String, token: String) -> String {
        """
        #!/bin/sh
        # Alethe: forwards a Codex hook event (JSON on stdin) to the app; the tab id is the argument.
        exec /usr/bin/curl -s -m 5 -o /dev/null -X POST \\
          -H "X-Alethe-Token: \(token)" -H "X-Alethe-Tab: $1" -H "Content-Type: application/json" \\
          --data-binary @- "\(endpoint)/hook/\(codexSubagentRoute)"
        """
    }

    public static let codexSubagentRoute = "codex-subagents"

    public static func codexSubagentArguments(script: String, tab: String) -> [String] {
        func quoted(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = toml("/bin/sh \(quoted(script)) \(quoted(tab))")
        return ["SubagentStart", "SubagentStop"].flatMap { event in
            ["-c", "hooks.\(event)=[{matcher=\".*\",hooks=[{type=\"command\",command=\(command),timeout=5}]}]"]
        }
    }

    static func toml(_ value: String) -> String {
        "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}

public struct ActivityMonitor: Sendable {
    public static let responseIdle: TimeInterval = 4.5
    static let minimumResponse: TimeInterval = 0.7
    static let echoGrace: TimeInterval = 0.35
    static let minimumOutput = 12

    private enum State: Sendable { case idle, armed, working }
    private var state = State.idle
    private var line = ""
    private var prompt = ""
    private var submittedAt: TimeInterval = 0
    private var outputCharacters = 0
    public private(set) var deadline: TimeInterval?

    public init() {}

    public mutating func input(_ text: String, at now: TimeInterval) -> AgentActivity? {
        var result: AgentActivity?
        for character in text {
            if ["\r", "\n"].contains(character) {
                let submitted = line.trimmingCharacters(in: .whitespaces)
                line = ""
                if !submitted.isEmpty {
                    state = .armed
                    prompt = submitted
                    submittedAt = now
                    outputCharacters = 0
                    deadline = nil
                    result = .working
                }
            } else if ["\u{8}", "\u{7F}"].contains(character) {
                if !line.isEmpty { line.removeLast() }
            } else {
                if character.asciiValue.map({ $0 >= 0x20 }) ?? true { line.append(character) }
            }
        }
        return result
    }

    public mutating func output(_ text: String, at now: TimeInterval) {
        guard state != .idle else { return }
        let visible = Self.stripControls(text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visible.isEmpty else { return }
        if now - submittedAt <= Self.echoGrace, !prompt.isEmpty, visible.contains(prompt) { return }
        outputCharacters += visible.count
        if state == .armed, outputCharacters >= Self.minimumOutput { state = .working }
        if state == .working { deadline = now + Self.responseIdle }
    }

    public mutating func tick(at now: TimeInterval) -> AgentActivity? {
        guard state == .working, let deadline, now >= deadline, now - submittedAt >= Self.minimumResponse else { return nil }
        state = .idle
        self.deadline = nil
        return .done
    }

    static func stripControls(_ text: String) -> String {
        text.replacingOccurrences(of: #"""
            \x{1B}\[[0-?]*[ -/]*[@-~]|\x{1B}\][^\x{07}]*(?:\x{07}|\x{1B}\\)|\x{1B}[PX^_].*?\x{1B}\\|\x{1B}[@-_\#
            ]
            """#,
                                  with: "", options: .regularExpression)
    }
}

public struct SubagentHook: Equatable, Sendable {
    public var event: String
    public var agentID: String?
    public var agentType: String?
    public var toolName: String?
    public var input: [String: String]
    public var runInBackground: Bool
    public var response: [String: String]
    public var lastAssistantMessage: String?
    public var transcriptPath: String?
    public var teammateName: String?

    public init(event: String, agentID: String? = nil, agentType: String? = nil, toolName: String? = nil,
                input: [String: String] = [:], runInBackground: Bool = false, response: [String: String] = [:],
                lastAssistantMessage: String? = nil, transcriptPath: String? = nil, teammateName: String? = nil) {
        self.event = event
        self.agentID = agentID
        self.agentType = agentType
        self.toolName = toolName
        self.input = input
        self.runInBackground = runInBackground
        self.response = response
        self.lastAssistantMessage = lastAssistantMessage
        self.transcriptPath = transcriptPath
        self.teammateName = teammateName
    }

    public static let events: Set<String> = ["SubagentStart", "SubagentStop", "PreToolUse", "PostToolUse", "TeammateIdle"]

    public static func parse(_ body: Data) -> SubagentHook? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let event = object["hook_event_name"] as? String, events.contains(event) else { return nil }
        func text(_ value: Any?) -> String? { (value as? String).flatMap { $0.isEmpty ? nil : $0 } }
        func strings(_ value: Any?) -> [String: String] {
            (value as? [String: Any] ?? [:]).compactMapValues { text($0) }
        }
        let input = object["tool_input"] as? [String: Any]
        return SubagentHook(
            event: event,
            agentID: text(object["agent_id"]),
            agentType: text(object["agent_type"]),
            toolName: text(object["tool_name"]),
            input: strings(input),
            runInBackground: input?["run_in_background"] as? Bool == true,
            response: strings(object["tool_response"]),
            lastAssistantMessage: text(object["last_assistant_message"]),
            transcriptPath: text(object["agent_transcript_path"]),
            teammateName: text(object["teammate_name"])
        )
    }
}
