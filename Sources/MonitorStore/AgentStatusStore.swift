import Foundation
import GRDB
import MonitorCore

extension UsageStore {
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
