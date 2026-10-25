import AletheDesign
import AppKit
import SwiftUI

struct AgentLogo: View {
    let agent: String
    var size: CGFloat = 16
    var templateColor: Color? = nil
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.theme) private var theme
    @Environment(\.metrics) private var metrics

    var body: some View {
        let side = metrics.size(size)
        Group {
            if metrics.isWebInterface, Self.asset(for: agent, isLight: theme.isLight) == nil, let definition
                = environment.preferences?.document.customAgents?.first(where: { $0.id == agent }) {
                CustomAgentIcon(definition: definition, size: size)
            } else if let asset = Self.asset(for: agent, isLight: theme.isLight),
               metrics.isWebInterface || !Self.webOnlyAgents.contains(agent) {
                assetImage(asset, side: side)
                    .resizable()
                    .renderingMode(asset.template ? .template : .original)
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(templateColor ?? theme[.fgMuted])
            } else {
                Image(systemName: metrics.isWebInterface ? "cpu" : "sparkles")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(theme[AgentTokens.accent(for: agent)])
            }
        }
        .frame(width: side, height: side)
        .accessibilityHidden(true)
    }

    private func assetImage(_ asset: Asset, side: CGFloat) -> Image {
        if metrics.isWebInterface, let image = Self.menuImage(for: agent, isLight: theme.isLight, side: side) {
            return Image(nsImage: image)
        }
        return Image(asset.name)
    }

    @MainActor static func menuImage(for agent: String, isLight: Bool, side: CGFloat) -> NSImage? {
        guard let asset = asset(for: agent, isLight: isLight) else { return nil }
        return menuImage(named: asset.name, template: asset.template, side: side)
    }

    @MainActor static func menuImage(named name: String, template: Bool = false, side: CGFloat) -> NSImage? {
        let key = "\(name):\(template):\(side)" as NSString
        if let cached = menuImages.object(forKey: key) { return cached }
        guard let source = NSImage(named: name) else { return nil }
        let bounds = NSRect(x: 0, y: 0, width: side, height: side)
        let image = NSImage(size: bounds.size)
        image.lockFocus()
        source.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1)
        image.unlockFocus()
        image.isTemplate = template
        menuImages.setObject(image, forKey: key)
        return image
    }

    @MainActor private static let menuImages: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 128
        return cache
    }()

    private static let webOnlyAgents: Set<String> = ["mimo", "cursor", "copilot", "kimi", "grok", "codewhale", "wsl"]

    struct Asset: Equatable {
        let name: String
        let template: Bool
    }

    private static let assets: [String: Asset] = [
        "claude": Asset(name: "AgentLogo-claude", template: false),
        "codex": Asset(name: "AgentLogo-codex", template: false),
        "freebuff": Asset(name: "AgentLogo-freebuff", template: false),
        "antigravity": Asset(name: "AgentLogo-antigravity", template: false),
        "kiro": Asset(name: "AgentLogo-kiro", template: false),
        "mimo": Asset(name: "AgentLogo-mimo", template: true),
        "cursor": Asset(name: "AgentLogo-cursor", template: true),
        "copilot": Asset(name: "AgentLogo-copilot", template: true),
        "kimi": Asset(name: "AgentLogo-kimi", template: true),
        "grok": Asset(name: "AgentLogo-grok", template: true),
        "codewhale": Asset(name: "AgentLogo-codewhale", template: true),
        "wsl": Asset(name: "AgentLogo-wsl", template: true),
        "shell": Asset(name: "AgentLogo-shell", template: true)
    ]

    static func asset(for agent: String, isLight: Bool) -> Asset? {
        if agent == "opencode" {
            return Asset(name: isLight ? "AgentLogo-opencode-light" : "AgentLogo-opencode-dark", template: false)
        }
        return assets[agent]
    }
}
