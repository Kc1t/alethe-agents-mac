import Foundation

public enum ConflictClass: String, Sendable, Hashable, Codable, CaseIterable {
    case rust, typeScript, ui, cargo, package, json, config, asset, planning
    case sentinel
    case graph, other

    public var variantName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    public static func classify(_ path: String) -> ConflictClass {
        let lower = path.replacingOccurrences(of: "\\", with: "/").lowercased()
        let fileName = lower.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? lower

        if [".gsd-child-session", ".gsd-child-busy", ".gsd-child-error"].contains(fileName) {
            return .sentinel
        }
        if lower.hasPrefix(".planning/") || lower.contains("/.planning/") { return .planning }
        if lower.hasPrefix("graphify-out/") || lower.contains("/graphify-out/") { return .graph }
        if let classification = Self.fileClasses[fileName] { return classification }
        let ext = fileName.split(separator: ".", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        return Self.extensionClasses[ext] ?? .other
    }

    private static let fileClasses: [String: ConflictClass] = [
        "cargo.toml": .cargo, "cargo.lock": .cargo,
        "package.json": .package, "package-lock.json": .package, "yarn.lock": .package, "pnpm-lock.yaml": .package,
    ]

    private static let extensionClasses: [String: ConflictClass] = [
        "rs": .rust,
        "ts": .typeScript, "tsx": .typeScript, "js": .typeScript, "jsx": .typeScript,
        "mts": .typeScript, "cts": .typeScript,
        "css": .ui, "scss": .ui, "less": .ui, "json": .json,
        "toml": .config, "yml": .config, "yaml": .config, "ini": .config,
        "conf": .config, "env": .config, "properties": .config,
        "png": .asset, "jpg": .asset, "jpeg": .asset, "gif": .asset, "webp": .asset,
        "svg": .asset, "ico": .asset, "ttf": .asset, "otf": .asset, "woff": .asset,
        "woff2": .asset, "mp3": .asset, "mp4": .asset, "bin": .asset,
    ]

    public var strategy: String { Self.strategies[self] ?? Self.otherStrategy }

    private static let otherStrategy = "Preserve both intentions; if unsure, keep both snippets and flag it in the commit."

    private static let strategies: [ConflictClass: String] = [
        .rust: "Rust code: preserve both intentions; after resolving, the code must compile (cargo check).",
        .typeScript: "TypeScript/JS code: preserve both intentions; duplicate imports/exports are the common cause; tsc must pass.",
        .ui: "Styles: merge the rules from both branches; never invent new colors — use the existing theme tokens.",
        .cargo: "Cargo.toml/lock: merge the dependencies from both branches; on a Cargo.lock conflict, "
            + "prefer regenerating (cargo update -p / cargo check) over hand-editing.",
        .package: "package.json/lockfile: merge the dependencies; on a lockfile conflict, prefer regenerating "
            + "(npm install) over hand-editing.",
        .json: "JSON: the result must be valid JSON; merge the keys from both branches; watch out for commas.",
        .config: "Configuration: merge the entries; for duplicate keys with different values, understand each "
            + "branch's intent before choosing.",
        .asset: "Binary/asset: there is no textual merge — pick the correct version (usually the newest) via git checkout --theirs/--ours.",
        .planning: "Planning (.planning/): preserve both branches' history; never discard tasks from either side.",
        .sentinel: "Ephemeral machine state from GSD Sync (session ID, busy/error flag) — this is NOT content "
            + "to merge, it's a single-line opaque value. NEVER paste both values together nor leave any "
            + "conflict marker (<<<<<<<, =======, >>>>>>>) in the file. Resolve by deleting the file "
            + "entirely (it is recreated on its own on the next GSD Sync cycle) — never pick a 'middle "
            + "ground' value.",
        .graph: "Graph (graphify-out/): don't resolve by hand — the graph is generated; pick either side and "
            + "regenerate with Graphify afterward.",
        .other: "Preserve both intentions; if unsure, keep both snippets and flag it in the commit.",
    ]
}
