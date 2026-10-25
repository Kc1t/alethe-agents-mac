import Foundation

public enum OnboardingStep: String, CaseIterable, Codable, Sendable {
    case name
    case importData
    case appearance
    case agents
    case features
    case mcp

    public static func steps(tauriDataAvailable: Bool, mcpEnabled: Bool) -> [OnboardingStep] {
        allCases.filter { step in
            switch step {
            case .importData: tauriDataAvailable
            case .mcp: mcpEnabled
            case .name, .appearance, .agents, .features: true
            }
        }
    }
}

public enum LaunchGreeting: Equatable, Sendable {
    case none
    case onboarding
    case welcomeBack(WelcomeBack)
}

public struct WelcomeBack: Hashable, Sendable {
    public var day: Int
    public var updatedFrom: String?
    public var absentDays: Int?

    public init(day: Int, updatedFrom: String? = nil, absentDays: Int? = nil) {
        self.day = day
        self.updatedFrom = updatedFrom
        self.absentDays = absentDays
    }

    public static let absence: TimeInterval = 7 * 86_400

    public static func day(since first: Date?, now: Date) -> Int {
        guard let first else { return 1 }
        return max(1, Int((now.timeIntervalSince(first) / 86_400).rounded(.down)) + 1)
    }
}

extension PreferencesDocument {
    public mutating func recordLaunch(version: String, hasProjects: Bool, now: Date = Date()) -> LaunchGreeting {
        defer {
            if firstLaunchAt == nil { firstLaunchAt = now }
            lastLaunchAt = now
            lastSeenVersion = version
        }
        guard onboardingDone == true else {
            if hasProjects {
                onboardingDone = true
                return .none
            }
            return .onboarding
        }
        let updatedFrom = lastSeenVersion.flatMap { $0 == version ? nil : $0 }
        let absentDays = lastLaunchAt.flatMap { last -> Int? in
            let gap = now.timeIntervalSince(last)
            return gap >= WelcomeBack.absence ? Int((gap / 86_400).rounded(.down)) : nil
        }
        guard updatedFrom != nil || absentDays != nil else { return .none }
        return .welcomeBack(WelcomeBack(day: WelcomeBack.day(since: firstLaunchAt, now: now),
                                        updatedFrom: updatedFrom, absentDays: absentDays))
    }
}

public enum OnboardingName {
    public static func suggested(fullName: String, userName: String) -> String {
        let first = fullName.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
        return first.isEmpty ? userName.trimmingCharacters(in: .whitespaces) : first
    }
}
