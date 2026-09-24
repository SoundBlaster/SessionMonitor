import CryptoKit
import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    /// Reads only the minimal, identity-internal observations needed to derive the
    /// privacy-safe cache-rate widget report. It never changes canonical accounting.
    public func cacheHitRateObservations(since: Date, until: Date) throws -> [CacheHitRateObservation] {
        try database.read { database in
            try Row.fetchAll(database, sql: """
                SELECT session, timestamp, input, cached
                FROM confirmed
                WHERE timestamp >= ? AND timestamp < ?
                ORDER BY timestamp ASC, response ASC
                """, arguments: [since.timeIntervalSince1970, until.timeIntervalSince1970]).map { row in
                    CacheHitRateObservation(
                        timestamp: Date(timeIntervalSince1970: row["timestamp"]),
                        sessionID: row["session"],
                        cacheableInputTokens: row["input"],
                        cachedInputTokens: row["cached"]
                    )
                }
        }
    }

    // swiftlint:disable function_body_length
    /// Reads presentation evidence for one exact session. This query never contributes to accounting.
    public func timeline(sessionID: String, query: UsageQuery) throws -> RequestTimeline {
        try database.read { database in
            let predicate = "(? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)"
            let start = query.since?.timeIntervalSince1970
            let end = query.until?.timeIntervalSince1970
            let arguments: StatementArguments = [
                sessionID, start, start, end, end,
                query.accountScope.kind.rawValue, query.accountScope.kind.rawValue,
                query.accountScope.profileID, query.accountScope.kind.rawValue
            ]
            let accountPredicate = Self.accountScopePredicate()
            var points: [RequestTimelinePoint] = try Row.fetchAll(database, sql: """
                SELECT response, turn, timestamp, input, cached, model, account_scope_key
                FROM confirmed
                WHERE session = ? AND \(predicate) \(accountPredicate)
                ORDER BY timestamp ASC, response ASC
                """, arguments: arguments).map { row in
                    let input: Int64 = row["input"]
                    let cached: Int64? = row["cached"]
                    let scopeKey: String = row["account_scope_key"]
                    return RequestTimelinePoint(
                        id: Self.requestPointID(scopeKey: scopeKey, responseID: row["response"]),
                        sessionID: sessionID,
                        timestamp: Date(timeIntervalSince1970: row["timestamp"]), kind: .usageRequest,
                        turnID: row["turn"], responseID: row["response"],
                        cachedInputTokens: cached,
                        uncachedInputTokens: cached.map { input - $0 }, evidence: "token_usage_record",
                        model: row["model"]
                    )
                }
            let eventRows = try Row.fetchAll(database, sql: """
                SELECT events.line, events.turn, events.timestamp, events.kind, events.evidence,
                       events.tool_name, events.model, events.activity_class
                FROM (
                    SELECT events.*, scope.profile_id AS account_profile_id
                    FROM source_timeline_events AS events
                    JOIN source_account_scope AS scope ON scope.source = events.source
                ) AS events
                WHERE events.session = ? AND \(predicate) \(accountPredicate)
                ORDER BY events.timestamp ASC, events.line ASC
                """, arguments: arguments)
            points.append(contentsOf: eventRows.map { row in
                let kind = TimelineEventKind(rawValue: row["kind"] as String) ?? .unknown
                let line: Int = row["line"]
                return RequestTimelinePoint(
                    id: "event:\(line):\(kind.rawValue)", sessionID: sessionID,
                    timestamp: Date(timeIntervalSince1970: row["timestamp"]), kind: kind,
                    turnID: row["turn"], sourceLine: line, evidence: row["evidence"],
                    toolName: row["tool_name"], model: row["model"],
                    activityClass: (row["activity_class"] as String?).flatMap(ActivityToolClass.init(rawValue:))
                )
            })
            points.sort {
                if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
                return $0.id < $1.id
            }
            return RequestTimeline(sessionID: sessionID, query: query, points: points)
        }
    }
    // swiftlint:enable function_body_length

    private static func requestPointID(scopeKey: String, responseID: String) -> String {
        let scopeDigest = SHA256.hash(data: Data(scopeKey.utf8))
            .map { String(format: "%02x", $0) }.joined()
        return "request:\(scopeDigest):\(responseID)"
    }
}
