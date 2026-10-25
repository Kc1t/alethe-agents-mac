import Foundation
import os

public enum LogDomain: String, CaseIterable, Codable, Sendable {
    case app, terminal, agents, git, integrations, persistence, orchestrator
}

public enum DiagnosticLevel: String, CaseIterable, Codable, Sendable {
    case warning, error, fault

    private static let logTypes: [Self: OSLogType] = [.warning: .default, .error: .error, .fault: .fault]

    var osLogType: OSLogType {
        Self.logTypes[self] ?? .default
    }
}

public struct DiagnosticEvent: Codable, Equatable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var date: Date
    public var level: DiagnosticLevel
    public var domain: LogDomain
    public var message: String

    public init(id: UUID = UUID(), date: Date = .now, level: DiagnosticLevel, domain: LogDomain, message: String) {
        self.id = id
        self.date = date
        self.level = level
        self.domain = domain
        self.message = message
    }
}

public enum AppLog {
    public static let subsystem = AppIdentity.bundleIdentifier

    private static let loggers: [LogDomain: Logger] = Dictionary(
        uniqueKeysWithValues: LogDomain.allCases.map { ($0, Logger(subsystem: subsystem, category: $0.rawValue)) }
    )

    public static func logger(_ domain: LogDomain) -> Logger {
        loggers[domain] ?? Logger(subsystem: subsystem, category: domain.rawValue)
    }

    public static func info(_ domain: LogDomain, _ message: String) {
        logger(domain).info("\(message, privacy: .private)")
    }

    public static func shown(_ message: String?, _ domain: LogDomain, level: DiagnosticLevel = .error) {
        guard let message, !message.isEmpty else { return }
        record(level, domain, message)
    }

    public static func record(_ level: DiagnosticLevel, _ domain: LogDomain, _ message: String) {
        Diagnostics.shared.record(level, domain, message)
    }
}
