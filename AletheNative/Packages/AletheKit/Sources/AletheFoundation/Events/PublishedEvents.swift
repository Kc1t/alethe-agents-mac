import Foundation

public extension BusEventType {
    static let mergeClean = "MergeClean"
    static let mergeConflict = "MergeConflict"
    static let mergeRequested = "MergeRequested"
    static let mergeValidated = "MergeValidated"
    static let mergeValidationFailed = "MergeValidationFailed"
    static let mergeMerged = "MergeMerged"
    static let mergeAborted = "MergeAborted"
    static let graphUpdated = "GraphUpdated"
    static let pluginEnabled = "PluginEnabled"
    static let pluginDisabled = "PluginDisabled"
    static let pluginFailed = "PluginFailed"
    static let resourceMetricsUpdated = "ResourceMetricsUpdated"
}

public extension BusEvent {
    static func mergeAnalyzed(projectID: String?, source: String, target: String, clean: Bool,
                              conflictCount: Int, classes: [String], date: Date = .now) -> BusEvent {
        BusEvent(type: clean ? BusEventType.mergeClean : BusEventType.mergeConflict,
                 correlationID: correlationID(prefix: "merge"), taskID: projectID,
                 data: .object(["source": .string(source), "target": .string(target),
                                "conflict_count": .number(Double(conflictCount)),
                                "classes": .array(classes.map(JSONValue.string))]),
                 date: date)
    }

    static func mergePrepared(environmentID: String, projectID: String?, source: String, target: String,
                              clean: Bool, conflictCount: Int, environmentPath: String,
                              date: Date = .now) -> [BusEvent] {
        var events = [merge(BusEventType.mergeRequested, environmentID, projectID,
                            ["source": .string(source), "target": .string(target), "clean": .bool(clean)], date)]
        if !clean {
            events.append(merge(BusEventType.mergeConflict, environmentID, projectID,
                                ["conflict_count": .number(Double(conflictCount)),
                                 "env": .string(environmentPath)], date))
        }
        return events
    }

    static func mergeValidation(environmentID: String, projectID: String?, failedStage: String?,
                                date: Date = .now) -> BusEvent {
        if let failedStage {
            return merge(BusEventType.mergeValidationFailed, environmentID, projectID,
                         ["stage": .string(failedStage)], date)
        }
        return merge(BusEventType.mergeValidated, environmentID, projectID, [:], date)
    }

    static func mergeMerged(environmentID: String, projectID: String?, source: String, target: String,
                            date: Date = .now) -> BusEvent {
        merge(BusEventType.mergeMerged, environmentID, projectID,
              ["source": .string(source), "target": .string(target)], date)
    }

    static func mergeAborted(environmentID: String, projectID: String?, date: Date = .now) -> BusEvent {
        merge(BusEventType.mergeAborted, environmentID, projectID, [:], date)
    }

    private static func merge(_ type: String, _ environmentID: String, _ projectID: String?,
                              _ data: [String: JSONValue], _ date: Date) -> BusEvent {
        BusEvent(type: type, correlationID: "merge-\(environmentID)", taskID: projectID, data: .object(data), date: date)
    }

    static func graphGenerated(repository: String, action: String = "bootstrap", projectID: String? = nil,
                               date: Date = .now) -> BusEvent {
        BusEvent(type: BusEventType.graphUpdated, correlationID: correlationID(prefix: "graphify"), taskID: projectID,
                 data: .object(["action": .string(action), "repo": .string(repository)]), date: date)
    }

    static func graphRolledBack(snapshotID: String, projectID: String? = nil, date: Date = .now) -> BusEvent {
        BusEvent(type: BusEventType.graphUpdated, correlationID: correlationID(prefix: "graphify"), taskID: projectID,
                 data: .object(["action": .string("rollback"), "snapshot_id": .string(snapshotID)]), date: date)
    }

    static func pluginEnabledChanged(id: String, enabled: Bool, date: Date = .now) -> BusEvent {
        BusEvent(type: enabled ? BusEventType.pluginEnabled : BusEventType.pluginDisabled,
                 correlationID: "plugin-\(id)",
                 data: .object(["id": .string(id), "enabled": .bool(enabled)]), date: date)
    }

    static func pluginFailed(id: String, error: String, date: Date = .now) -> BusEvent {
        BusEvent(type: BusEventType.pluginFailed, correlationID: "plugin-\(id)",
                 data: .object(["id": .string(id), "error": .string(error)]), date: date)
    }

    static func resourceMetrics(memoryPressure: String, systemAvailableMB: Double, systemTotalMB: Double,
                                appMB: Double, ptysMB: Double, processCount: Int, policyTriggerCount: Int,
                                date: Date = .now) -> BusEvent {
        BusEvent(type: BusEventType.resourceMetricsUpdated, correlationID: "resource-manager",
                 data: .object([
                     "memory_pressure": .string(memoryPressure),
                     "system_available_mb": .number(systemAvailableMB),
                     "system_total_mb": .number(systemTotalMB),
                     "app_mb": .number(appMB),
                     "webview_mb": .number(0),
                     "ptys_mb": .number(ptysMB),
                     "process_count": .number(Double(processCount)),
                     "policy_trigger_count": .number(Double(policyTriggerCount)),
                 ]), date: date)
    }
}
