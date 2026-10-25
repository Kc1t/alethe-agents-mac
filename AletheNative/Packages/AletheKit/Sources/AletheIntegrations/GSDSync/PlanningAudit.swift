import AletheFoundation
import AletheGit
import Foundation

public struct PlanningCommit: Codable, Equatable, Hashable, Sendable {
    public var hash: String
    public var author: String
    public var timestampMS: UInt64
    public var subject: String
    public var agentID: String?

    public init(hash: String, author: String, timestampMS: UInt64, subject: String, agentID: String?) {
        self.hash = hash
        self.author = author
        self.timestampMS = timestampMS
        self.subject = subject
        self.agentID = agentID
    }

    enum CodingKeys: String, CodingKey {
        case hash, author, subject
        case timestampMS = "timestampMs"
        case agentID = "agentId"
    }
}

public enum PlanningAuditError: Error, Equatable, Sendable {
    case notARepository
    case planningDirectoryNotFound
}

public struct PlanningAudit: Sendable {
    public static let defaultHistoryLimit = 50
    public static let maxHistoryLimit = 500
    public static let trailerKey = "Alethe-Agent"
    static let fieldSeparator: Character = "\u{1f}"
    static let recordSeparator: Character = "\u{1e}"

    public let runner: GitRunner
    public let repositories: GitRepositories
    public let bus: EventBus?

    public init(runner: GitRunner = GitRunner(), repositories: GitRepositories = .shared, bus: EventBus? = nil) {
        self.runner = runner
        self.repositories = repositories
        self.bus = bus
    }

    public func repositoryRoot(_ path: URL) async throws -> URL {
        do {
            return try await GitRepository.discover(path, runner: runner)
        } catch GitError.notARepository {
            throw PlanningAuditError.notARepository
        } catch GitError.commandFailed {
            throw PlanningAuditError.notARepository
        }
    }

    @discardableResult
    public func record(repository path: URL, agentID: String? = nil, reason: String? = nil,
                       projectID: String? = nil) async throws -> PlanningCommit? {
        let root = try await repositoryRoot(path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: PlanningGate.planningFolder(of: root).path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw PlanningAuditError.planningDirectoryNotFound
        }
        let repository = repositories.repository(at: root, runner: runner)
        let folder = PlanningGate.folderName
        let status = try await repository.run(["status", "--porcelain", "--", folder])
        guard !status.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        _ = try await repository.run(["add", "--", folder])
        let subject = Self.subject(reason: reason)
        let trailer = "\(Self.trailerKey): \(agentID ?? "unknown")"
        _ = try await repository.run(["commit", "-m", subject, "-m", trailer, "--", folder])
        let hash = try await repository.run(["rev-parse", "HEAD"]).text.trimmingCharacters(in: .whitespacesAndNewlines)

        let commit = PlanningCommit(hash: hash, author: "", timestampMS: UInt64(max(0, Date.now.timeIntervalSince1970 * 1000)),
                                    subject: subject, agentID: agentID)
        await bus?.publish(BusEventType.planningCommitted, correlationID: BusEvent.correlationID(prefix: "gsd-audit"),
                           taskID: projectID, agentID: agentID,
                           data: .object(["hash": .string(hash), "subject": .string(subject)]))
        return commit
    }

    public func history(repository path: URL, limit: Int? = nil) async throws -> [PlanningCommit] {
        let root = try await repositoryRoot(path)
        let count = max(0, min(limit ?? Self.defaultHistoryLimit, Self.maxHistoryLimit))
        let f = Self.fieldSeparator, r = Self.recordSeparator
        let format = "%H\(f)%an\(f)%ct\(f)%s\(f)%(trailers:key=\(Self.trailerKey),valueonly,separator=,)\(r)"
        let repository = repositories.repository(at: root, runner: runner)
        guard let output = try? await repository.run(["log", "-n", String(count), "--pretty=format:\(format)",
                                                      "--", PlanningGate.folderName]) else { return [] }
        return Self.parseHistory(output.text)
    }

    static func subject(reason: String?) -> String {
        let trimmed = reason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return "gsd(alethe): \(trimmed.isEmpty ? "planning update" : trimmed)"
    }

    static func parseHistory(_ raw: String) -> [PlanningCommit] {
        raw.split(separator: recordSeparator, omittingEmptySubsequences: false).compactMap { record in
            let record = record.trimmingCharacters(in: .newlines)
            guard !record.isEmpty else { return nil }
            let fields = record.split(separator: fieldSeparator, omittingEmptySubsequences: false).map(String.init)
            guard fields.count >= 4 else { return nil }
            let agent = fields.count > 4 ? fields[4].trimmingCharacters(in: .whitespaces) : ""
            let seconds = UInt64(fields[2]) ?? 0
            return PlanningCommit(hash: fields[0], author: fields[1],
                                  timestampMS: seconds.multipliedReportingOverflow(by: 1000).overflow ? .max : seconds * 1000,
                                  subject: fields[3], agentID: agent.isEmpty ? nil : agent)
        }
    }
}
