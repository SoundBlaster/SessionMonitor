import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    /// Only the selected session's canonical totals, with selection and watermark in one read.
    /// Unlike a full UsageSnapshot, this intentionally omits unrelated sessions/provenance/storage.
    public func agentSessionSnapshot(
        sessionID: String?, query: UsageQuery
    ) throws -> AgentSessionSnapshot {
        let start = query.since?.timeIntervalSince1970
        let end = query.until?.timeIntervalSince1970
        let windowArguments: StatementArguments = [start, start, end, end]
        let scopeArguments: StatementArguments = [query.accountScope.kind.rawValue, query.accountScope.kind.rawValue,
                                                  query.accountScope.profileID, query.accountScope.kind.rawValue]
        return try database.read { database in
            let watermark = try Self.queryWatermark(database)
            let id = try sessionID ?? String.fetchOne(database, sql: """
                SELECT session FROM confirmed
                WHERE (? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)
                \(Self.accountScopePredicate())
                ORDER BY timestamp DESC, response DESC LIMIT 1
                """, arguments: windowArguments + scopeArguments)
            let row = try id.flatMap { id in
                let arguments: StatementArguments = [id, start, start, end, end]
                return try Row.fetchOne(database, sql: """
                    SELECT session, CASE WHEN COUNT(DISTINCT model) = 1 THEN MIN(model) ELSE 'mixed' END AS model,
                           \(Self.aggregates) FROM confirmed WHERE session = ?
                    AND (? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)
                    \(Self.accountScopePredicate())
                    GROUP BY session
                    """, arguments: arguments + scopeArguments)
            }
            let summary = row.map { SessionSummary(id: $0["session"], model: $0["model"], totals: Self.totals($0)) }
            return AgentSessionSnapshot(sessionID: id, summary: summary, watermark: watermark)
        }
    }

    /// The session with the newest confirmed canonical request in the query window, across accounts.
    public func latestSessionID(query: UsageQuery) throws -> String? {
        let start = query.since?.timeIntervalSince1970
        let end = query.until?.timeIntervalSince1970
        return try database.read { database in
            try String.fetchOne(database, sql: """
                SELECT session FROM confirmed
                WHERE (? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)
                ORDER BY timestamp DESC, response DESC
                LIMIT 1
                """, arguments: [start, start, end, end])
        }
    }
}

extension UsageStore {
    /// Sessions with confirmed usage imported from one source path, newest first.
    public func sessionIDs(source: String) throws -> [String] {
        try database.read { database in
            try String.fetchAll(database, sql: """
                SELECT session FROM source_records
                WHERE source = ?
                GROUP BY session
                ORDER BY MAX(timestamp) DESC
                """, arguments: [source])
        }
    }
}

extension UsageStore {
    /// Whether any confirmed canonical request belongs to this session.
    public func hasSession(_ sessionID: String) throws -> Bool {
        try database.read { database in
            try Bool.fetchOne(database, sql: "SELECT EXISTS(SELECT 1 FROM confirmed WHERE session = ?)",
                              arguments: [sessionID]) ?? false
        }
    }
}
