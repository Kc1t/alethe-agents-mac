import Foundation

public struct CrashArtifact: Equatable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Sendable {
        case systemReport
        case metricKit
    }

    public var kind: Kind
    public var url: URL
    public var date: Date
    public var id: URL { url }

    public init(kind: Kind, url: URL, date: Date) {
        self.kind = kind
        self.url = url
        self.date = date
    }
}

public enum CrashEvidence {
    public static let metricKitFolder = "metrickit"

    public static var systemReportDirectories: [URL] {
        let logs = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Logs/DiagnosticReports")
        return [logs, logs.appending(path: "Retired")]
    }

    public static func find(processName: String = AppIdentity.productName, since: Date?,
                            reportDirectories: [URL] = systemReportDirectories,
                            metricKitDirectory: URL?) -> [CrashArtifact] {
        let reports = reportDirectories.flatMap { files(in: $0) }
            .filter { $0.url.lastPathComponent.hasPrefix("\(processName)-") && $0.url.pathExtension == "ips" }
            .filter { isRecent($0.date, since: since) }
            .max { $0.date < $1.date }
            .map { CrashArtifact(kind: .systemReport, url: $0.url, date: $0.date) }
        let payloads = metricKitDirectory.map { files(in: $0) } ?? []
        let metricKit = payloads
            .filter { $0.url.pathExtension == "json" }
            .filter { isRecent($0.date, since: since) }
            .sorted { $0.date > $1.date }
            .map { CrashArtifact(kind: .metricKit, url: $0.url, date: $0.date) }
        return (reports.map { [$0] } ?? []) + metricKit
    }

    private static func isRecent(_ date: Date, since: Date?) -> Bool {
        guard let since else { return true }
        return date >= since.addingTimeInterval(-1)
    }

    private static func files(in directory: URL) -> [(url: URL, date: Date)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey],
                                                                  options: .skipsHiddenFiles)) ?? []
        return urls.compactMap { url in
            guard let date = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { return nil }
            return (url, date)
        }
    }
}
