import Foundation

public enum PaneContent: Hashable, Sendable {
    case terminal
    case markdown(path: String)
    case image(path: String)
    case video(path: String)
    case diff(path: String?, staged: Bool)
    case web(url: String, options: WebPaneOptions)
    case graphify
    case orchestrator

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case terminal, markdown, image, video, diff, web, graphify, orchestrator
    }

    public var kind: Kind {
        if case .terminal = self { return .terminal }
        else if case .markdown = self { return .markdown }
        else if case .image = self { return .image }
        else if case .video = self { return .video }
        else if case .diff = self { return .diff }
        else if case .web = self { return .web }
        else if case .graphify = self { return .graphify }
        else { return .orchestrator }
    }

    public var isTerminal: Bool { self == .terminal }

    public var filePath: String? {
        if case .markdown(let path) = self { return path }
        else if case .image(let path) = self { return path }
        else if case .video(let path) = self { return path }
        else { return nil }
    }

    public static func forFile(_ rawPath: String) -> PaneContent? {
        let path = rawPath.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: #":\d+(:\d+)?$"#, with: "", options: .regularExpression)
        let fileExtension = (path as NSString).pathExtension.lowercased()
        if ["mp4", "m4v", "mov", "avi", "mkv", "webm", "ogv"].contains(fileExtension) { return .video(path: path) }
        if ["png", "jpg", "jpeg", "gif", "webp", "bmp", "avif", "ico", "svg"].contains(fileExtension) { return .image(path: path) }
        if ["md", "markdown", "mdx"].contains(fileExtension) { return .markdown(path: path) }
        return nil
    }
}

extension PaneContent: Codable {
    private enum CodingKeys: String, CodingKey { case kind, path, url, staged, options }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let path = try container.decodeIfPresent(String.self, forKey: .path)
        let matchedValue = try container.decode(Kind.self, forKey: .kind)
        if case .terminal = matchedValue { self = .terminal }
        else if case .markdown = matchedValue { self = .markdown(path: path ?? "") }
        else if case .image = matchedValue { self = .image(path: path ?? "") }
        else if case .video = matchedValue { self = .video(path: path ?? "") }
        else if case .diff = matchedValue { self = .diff(path: path, staged: try container.decodeIfPresent(Bool.self,
            forKey: .staged) ?? false) }
        else if case .web = matchedValue {
            self = .web(url: try container.decodeIfPresent(String.self, forKey: .url) ?? "",
            options: try container.decodeIfPresent(WebPaneOptions.self, forKey: .options) ?? WebPaneOptions())
        } else if case .graphify = matchedValue { self = .graphify } else { self = .orchestrator }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        if case .terminal = self {

        } else if case .graphify = self {

        } else if case .orchestrator = self {

        }
        else if case .markdown(let path) = self { try container.encode(path, forKey: .path) }
        else if case .image(let path) = self { try container.encode(path, forKey: .path) }
        else if case .video(let path) = self { try container.encode(path, forKey: .path) }
        else if case .diff(let path, let staged) = self {
            try container.encodeIfPresent(path, forKey: .path)
            if staged { try container.encode(true, forKey: .staged) }
        } else {
            guard case .web(let url, let options) = self else {
                preconditionFailure("Unexpected enum case")
            }
            try container.encode(url, forKey: .url)
            if options != WebPaneOptions() { try container.encode(options, forKey: .options) }
        }
    }
}
