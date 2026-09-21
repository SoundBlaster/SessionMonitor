import Foundation
import GRDB
import MonitorCore

public enum ActivityQueryError: Error {
    case conflictingSessionScopes
}

extension UsageStore {
    static func backfillActivityEventClassifications(_ database: Database) throws {
        try database.execute(sql: "UPDATE source_timeline_events SET activity_class = 'wait' WHERE kind = 'wait'")
        try database.execute(
            sql: "UPDATE source_timeline_events SET activity_class = 'goal_continuation' WHERE kind = 'goalTurn'"
        )
        try database.execute(sql: "UPDATE source_timeline_events SET activity_class = 'unknown' WHERE kind = 'tool'")
    }

    static func insertActivityEvents(_ events: [TimelineSourceEvent], source: String,
                                     database: Database) throws {
        for event in events {
            try database.execute(sql: """
                INSERT INTO source_timeline_events
                (source, line, session, turn, timestamp, kind, evidence, tool_name, model, activity_class)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [source, event.sourceLine, event.sessionID, event.turnID,
                                  event.timestamp.timeIntervalSince1970, event.kind.rawValue, event.evidence,
                                  event.toolName, event.model, event.activityClass?.rawValue])
        }
    }

    /// Reads canonical response totals and explicit operational events without changing accounting.
    public func activity(
        query: UsageQuery, sessionID: String? = nil, rootSessionID: String? = nil
    ) throws -> ActivityRollupReport {
        guard sessionID == nil || rootSessionID == nil else {
            throw ActivityQueryError.conflictingSessionScopes
        }
        return try database.read { database in
            let timePredicate = "(? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)"
            let start = query.since?.timeIntervalSince1970
            let end = query.until?.timeIntervalSince1970
            let scopePredicate = """
                AND (? IS NULL OR session = ?)
                AND (? IS NULL OR session = ? OR session IN (
                    SELECT session FROM source_provenance WHERE root_session = ?
                ))
                """
            let arguments: StatementArguments = [
                start, start, end, end, sessionID, sessionID, rootSessionID, rootSessionID, rootSessionID
            ]
            let usageRows = try Row.fetchAll(database, sql: """
                SELECT session, model, input, cached, output, cache_write, reasoning, total
                FROM confirmed
                WHERE \(timePredicate) \(scopePredicate)
                ORDER BY session, model, timestamp, response
                """, arguments: arguments)
            let usageRollup = Self.rollupUsage(usageRows)

            let eventRows = try Self.fetchActivityEvents(
                database, timePredicate: timePredicate, scopePredicate: scopePredicate, arguments: arguments
            )
            let eventRollup = Self.rollupToolEvents(eventRows)
            let coverage = ActivityCoverage(
                state: eventRollup.observed == 0 ? .unknown : .observed,
                unknownReason: eventRollup.observed == 0
                    ? "No explicit activity tool events were observed; source event coverage is unknown."
                    : (eventRollup.unknown == 0
                        ? nil : "Some observed tool events have unknown tool identity or classification."),
                observedToolEvents: eventRollup.observed, unknownClassEvents: eventRollup.unknown
            )
            return ActivityRollupReport(
                query: query, sessionID: sessionID, rootSessionID: rootSessionID,
                totals: usageRollup.totals, usageByThreadAndModel: usageRollup.byThreadAndModel,
                usageByModel: usageRollup.byModel, toolEvents: eventRollup.items, coverage: coverage
            )
        }
    }

    private static func fetchActivityEvents(
        _ database: Database, timePredicate: String, scopePredicate: String, arguments: StatementArguments
    ) throws -> [Row] {
        try Row.fetchAll(database, sql: """
                SELECT session, model, kind, activity_class, tool_name, evidence, line
                FROM (
                    SELECT DISTINCT session, turn, timestamp, kind, activity_class, tool_name,
                                    model, evidence, line
                    FROM source_timeline_events
                )
                WHERE \(timePredicate)
                  AND (kind = 'tool' OR activity_class IS NOT NULL
                       OR (kind = 'unknown' AND tool_name IS NOT NULL))
                  \(scopePredicate)
                ORDER BY session, model, activity_class, tool_name, evidence, line
                """, arguments: arguments)
    }

    private static func rollupUsage(_ rows: [Row]) -> UsageRollupResult {
        var threadTotals: [UsageGroupKey: UsageTotalsAccumulator] = [:]
        var modelTotals: [String: UsageTotalsAccumulator] = [:]
        var totals = UsageTotalsAccumulator()
        for row in rows {
            let sessionID: String = row["session"]
            let model: String = row["model"]
            totals.add(row: row)
            let threadKey = UsageGroupKey(sessionID: sessionID, model: model)
            threadTotals[threadKey, default: UsageTotalsAccumulator()].add(row: row)
            modelTotals[model, default: UsageTotalsAccumulator()].add(row: row)
        }
        var byThreadAndModel: [ActivityUsageRollup] = []
        for (key, value) in threadTotals {
            byThreadAndModel.append(ActivityUsageRollup(sessionID: key.sessionID, model: key.model,
                                                        totals: value.value))
        }
        byThreadAndModel.sort {
            $0.sessionID == $1.sessionID ? $0.model < $1.model : $0.sessionID < $1.sessionID
        }
        var byModel: [ActivityModelRollup] = []
        for (model, value) in modelTotals {
            byModel.append(ActivityModelRollup(model: model, totals: value.value))
        }
        byModel.sort { $0.model < $1.model }
        return UsageRollupResult(totals: totals.value, byThreadAndModel: byThreadAndModel, byModel: byModel)
    }

    private static func rollupToolEvents(_ rows: [Row]) -> ToolEventRollupResult {
        var groups: [ToolEventGroupKey: (count: Int64, lines: [Int])] = [:]
        var observed: Int64 = 0
        var unknown: Int64 = 0
        for row in rows {
            let kind: String = row["kind"]
            guard let classification = (row["activity_class"] as String?)
                .flatMap(ActivityToolClass.init(rawValue:))
                    ?? ((kind == "tool" || (kind == "unknown" && (row["tool_name"] as String?) != nil))
                        ? .unknown : nil) else {
                continue
            }
            let key = ToolEventGroupKey(
                sessionID: row["session"], model: row["model"], classification: classification,
                toolName: row["tool_name"], evidence: row["evidence"]
            )
            var group = groups[key, default: (0, [])]
            group.count += 1
            group.lines.append(row["line"])
            groups[key] = group
            observed += 1
            if classification == .unknown { unknown += 1 }
        }

        var items: [ActivityToolEventRollup] = []
        for (key, value) in groups {
            items.append(ActivityToolEventRollup(
                sessionID: key.sessionID, model: key.model, classification: key.classification,
                toolName: key.toolName, evidence: key.evidence, count: value.count, sourceLines: value.lines
            ))
        }
        items.sort {
            if $0.classification != $1.classification {
                return $0.classification.rawValue < $1.classification.rawValue
            }
            if $0.sessionID != $1.sessionID { return $0.sessionID < $1.sessionID }
            if $0.toolName != $1.toolName { return ($0.toolName ?? "") < ($1.toolName ?? "") }
            return ($0.sourceLines.first ?? 0) < ($1.sourceLines.first ?? 0)
        }
        return ToolEventRollupResult(items: items, observed: observed, unknown: unknown)
    }

}

private struct UsageGroupKey: Hashable {
    let sessionID: String
    let model: String
}

private struct ToolEventGroupKey: Hashable {
    let sessionID: String
    let model: String?
    let classification: ActivityToolClass
    let toolName: String?
    let evidence: String
}

private struct ToolEventRollupResult {
    let items: [ActivityToolEventRollup]
    let observed: Int64
    let unknown: Int64
}

private struct UsageRollupResult {
    let totals: UsageTotals
    let byThreadAndModel: [ActivityUsageRollup]
    let byModel: [ActivityModelRollup]
}

private struct UsageTotalsAccumulator {
    private var requests: Int64 = 0
    private var inputTokens: Int64 = 0
    private var cachedInputTokens: Int64 = 0
    private var outputTokens: Int64 = 0
    private var unknownCacheRequests: Int64 = 0
    private var cacheWriteInputTokens: Int64 = 0
    private var hasCompleteCacheWrite = true
    private var reasoningOutputTokens: Int64 = 0
    private var hasCompleteReasoning = true
    private var totalTokens: Int64 = 0
    private var hasCompleteTotal = true

    mutating func add(row: Row) {
        let input: Int64 = row["input"]
        let cached: Int64? = row["cached"]
        let output: Int64 = row["output"]
        let cacheWrite: Int64? = row["cache_write"]
        let reasoning: Int64? = row["reasoning"]
        let total: Int64? = row["total"]
        requests += 1
        inputTokens += input
        outputTokens += output
        if let cached { cachedInputTokens += cached } else { unknownCacheRequests += 1 }
        if let cacheWrite { cacheWriteInputTokens += cacheWrite } else { hasCompleteCacheWrite = false }
        if let reasoning { reasoningOutputTokens += reasoning } else { hasCompleteReasoning = false }
        if let total { totalTokens += total } else { hasCompleteTotal = false }
    }

    var value: UsageTotals {
        UsageTotals(
            requests: requests, inputTokens: inputTokens, cachedInputTokens: cachedInputTokens,
            outputTokens: outputTokens, unknownCacheRequests: unknownCacheRequests,
            cacheWriteInputTokens: hasCompleteCacheWrite && requests > 0 ? cacheWriteInputTokens : nil,
            reasoningOutputTokens: hasCompleteReasoning && requests > 0 ? reasoningOutputTokens : nil,
            totalTokens: hasCompleteTotal && requests > 0 ? totalTokens : nil
        )
    }
}
