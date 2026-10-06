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
