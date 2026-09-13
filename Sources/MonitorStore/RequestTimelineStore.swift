import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    /// Reads presentation evidence for one exact session. This query never contributes to accounting.
    public func timeline(sessionID: String, query: UsageQuery) throws -> RequestTimeline {
        try database.read { database in
            let predicate = "(? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)"
            let start = query.since?.timeIntervalSince1970
            let end = query.until?.timeIntervalSince1970
            let arguments: StatementArguments = [sessionID, start, start, end, end]
            var points: [RequestTimelinePoint] = try Row.fetchAll(database, sql: """
                SELECT response, turn, timestamp, input, cached
                FROM confirmed
                WHERE session = ? AND \(predicate)
                ORDER BY timestamp ASC, response ASC
                """, arguments: arguments).map { row in
                    let input: Int64 = row["input"]
                    let cached: Int64? = row["cached"]
                    return RequestTimelinePoint(
                        id: "request:\(row["response"] as String)", sessionID: sessionID,
                        timestamp: Date(timeIntervalSince1970: row["timestamp"]), kind: .usageRequest,
                        turnID: row["turn"], responseID: row["response"],
                        cachedInputTokens: cached,
                        uncachedInputTokens: cached.map { input - $0 }, evidence: "token_usage_record"
                    )
                }
            let eventRows = try Row.fetchAll(database, sql: """
                SELECT line, turn, timestamp, kind, evidence
                FROM source_timeline_events
                WHERE session = ? AND \(predicate)
                ORDER BY timestamp ASC, line ASC
                """, arguments: arguments)
            points.append(contentsOf: eventRows.map { row in
                let kind = TimelineEventKind(rawValue: row["kind"] as String) ?? .unknown
                let line: Int = row["line"]
                return RequestTimelinePoint(
                    id: "event:\(line):\(kind.rawValue)", sessionID: sessionID,
                    timestamp: Date(timeIntervalSince1970: row["timestamp"]), kind: kind,
                    turnID: row["turn"], sourceLine: line, evidence: row["evidence"]
                )
            })
            points.sort {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.id < $1.id
            }
            return RequestTimeline(sessionID: sessionID, query: query, points: points)
        }
    }
}
