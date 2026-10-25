import AletheDesign
import AletheFoundation
import AletheIntegrations
import AppKit
import SwiftUI

extension McpSourceKind {
    private static let titleValues: [McpSourceKind: String] = [
        .user: "mcp.source.user",
        .local: "mcp.source.local",
    ]

    var title: LocalizedStringKey {
        LocalizedStringKey(Self.titleValues[self] ?? "mcp.source.project")
    }
}

extension McpHealthError {
    private static let titleValues: [McpHealthError: String] = [
        .unsupportedAgent: "mcp.health.unsupported",
        .cliNotFound: "mcp.health.cliNotFound",
        .cliFailed: "mcp.health.cliFailed",
        .timedOut: "mcp.health.timedOut",
    ]

    var title: LocalizedStringKey {
        LocalizedStringKey(Self.titleValues[self] ?? "mcp.health.unknown")
    }
}
