import Foundation

public struct GSDPluginInstallReport: Hashable, Sendable {
    public enum Outcome: Hashable, Sendable {
        case written
        case unchanged
        case skipped
    }

    public var plugin: Outcome
    public var modelChain: Outcome
    public var openCodeConfig: Outcome
    public var configBackup: ConfigBackup?
}

public enum GSDOpenCodePlugin {
    public static let pluginRelativePath = ".opencode/plugins/alethe-gsd-state.ts"
    public static let configEntry = "./.opencode/plugins/alethe-gsd-state.ts"
    public static let modelChainRelativePath = ".opencode/alethe-gsd-config.json"
    public static let openCodeConfigName = "opencode.json"
    public static let schemaURL = "https://opencode.ai/config.json"
    static let markerPrefix = "// alethe-managed: v"
    public static let backupSlot = ConfigBackupSlot(agent: "opencode", kind: "project")

    public enum InstallError: Error, Equatable, Sendable {
        case pluginAssetMissing
        case file(ConfigFileError)
    }

    public static func bundledPlugin() throws(InstallError) -> String {
        guard let url = Bundle.module.url(forResource: "alethe-gsd-state", withExtension: "ts", subdirectory: "OpenCodePlugins"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { throw .pluginAssetMissing }
        return text
    }

    public static func managedVersion(of content: String) -> Int? {
        guard let first = content.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false).first,
              first.hasPrefix(markerPrefix) else { return nil }
        return UInt32(first.dropFirst(markerPrefix.count).trimmingCharacters(in: .whitespaces)).map(Int.init)
    }

    public static func shouldWritePlugin(existing: String?, bundledVersion: Int) -> Bool {
        guard let existing else { return true }
        guard let version = managedVersion(of: existing) else { return false }
        return version <= bundledVersion
    }

    @discardableResult
    public static func install(
        root: URL,
        modelChain: [String],
        writer: ConfigFileWriter,
        pluginSource: String? = nil
    ) throws(InstallError) -> GSDPluginInstallReport {
        let source: String
        if let pluginSource { source = pluginSource } else { source = try bundledPlugin() }
        do throws(ConfigFileError) {
            let plugin = try writePlugin(source, root: root, writer: writer)
            let chain = try writeModelChain(modelChain, root: root, writer: writer)
            let (config, backup) = try mergeConfigEntry(root: root, writer: writer)
            return GSDPluginInstallReport(plugin: plugin, modelChain: chain, openCodeConfig: config, configBackup: backup)
        } catch {
            throw .file(error)
        }
    }

    static func writePlugin(
        _ source: String, root: URL, writer: ConfigFileWriter
    ) throws(ConfigFileError) -> GSDPluginInstallReport.Outcome {
        let snapshot = try writer.read(root.appending(path: pluginRelativePath))
        guard shouldWritePlugin(existing: snapshot.exists ? snapshot.text : nil, bundledVersion: managedVersion(of: source) ?? 0) else {
            return .skipped
        }
        guard snapshot.text != source || !snapshot.exists else { return .unchanged }
        try writer.write(source, over: snapshot, backupSlot: nil)
        return .written
    }

    static func writeModelChain(
        _ chain: [String], root: URL, writer: ConfigFileWriter
    ) throws(ConfigFileError) -> GSDPluginInstallReport.Outcome {
        let snapshot = try writer.read(root.appending(path: modelChainRelativePath))
        let body = OrderedJSON.object(OrderedJSONObject([("modelChain", .array(chain.map(OrderedJSON.string)))])).rendered()
        guard !snapshot.exists || snapshot.text != body else { return .unchanged }
        try writer.write(body, over: snapshot, backupSlot: nil)
        return .written
    }

    static func mergeConfigEntry(
        root: URL, writer: ConfigFileWriter
    ) throws(ConfigFileError) -> (GSDPluginInstallReport.Outcome, ConfigBackup?) {
        let url = root.appending(path: openCodeConfigName)
        var attempt = 0
        while true {
            attempt += 1
            let snapshot = try writer.read(url)
            guard let text = mergedConfig(snapshot.exists ? snapshot.text : nil) else { return (.skipped, nil) }
            guard text != snapshot.text || !snapshot.exists else { return (.unchanged, nil) }
            do throws(ConfigFileError) {
                let report = try writer.write(text, over: snapshot, backupSlot: backupSlot)
                return (.written, report.backup)
            } catch .changedSinceRead where attempt < 2 {
                continue
            }
        }
    }

    static func mergedConfig(_ existing: String?) -> String? {
        var editor: JSONConfigEditor
        if let existing {
            guard let parsed = try? JSONConfigEditor(parsing: existing) else { return nil }
            editor = parsed
        } else {
            editor = JSONConfigEditor(root: OrderedJSONObject([("$schema", .string(schemaURL))]))
        }
        var list: [OrderedJSON]
        let pluginValue = editor.value(at: ["plugin"])
        if case .none = pluginValue {
            list = []
        } else if case .array(let items) = pluginValue {
            list = items
        } else {
            return nil
        }
        if list.contains(.string(configEntry)) { return existing ?? editor.rendered() }
        list.append(.string(configEntry))
        guard (try? editor.set(.array(list), at: ["plugin"])) != nil else { return nil }
        return editor.rendered()
    }
}
