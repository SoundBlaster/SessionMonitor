import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    typealias SessionSpans = [String: (first: Date, last: Date)]

    /// First and last confirmed request of every session over all imported history of the account scope, so a
    /// session id shared by several profiles never shows another account's dates.
    static func sessionSpans(_ database: Database, accountScope: UsageAccountScope) throws -> SessionSpans {
        let rows = try Row.fetchAll(database, sql: """
            SELECT session, MIN(timestamp) AS first_at, MAX(timestamp) AS last_at FROM confirmed
            WHERE 1 = 1 \(accountScopePredicate()) GROUP BY session
            """, arguments: [
                accountScope.kind.rawValue, accountScope.kind.rawValue, accountScope.profileID,
                accountScope.kind.rawValue
            ])
        return Dictionary(uniqueKeysWithValues: rows.map { row in
            (row["session"] as String,
             (Date(timeIntervalSince1970: row["first_at"]), Date(timeIntervalSince1970: row["last_at"])))
        })
    }

    static func sessionSummary(_ row: Row, spans: SessionSpans) -> SessionSummary {
        let span = spans[row["session"] as String]
        return SessionSummary(id: row["session"], model: row["model"], totals: totals(row),
                              firstRequestAt: span?.first, lastRequestAt: span?.last)
    }
}
