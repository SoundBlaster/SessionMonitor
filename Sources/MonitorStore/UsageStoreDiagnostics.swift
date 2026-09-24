import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    static func diagnostics(_ database: Database) throws -> [String: Int64] {
        var diagnostics: [String: Int64] = [:]
        let query = "SELECT kind, SUM(count) AS count FROM source_diagnostics GROUP BY kind"
        for row in try Row.fetchAll(database, sql: query) {
            diagnostics[row["kind"]] = row["count"]
        }
        diagnostics["conflictingResponseIDs"] = try Int64.fetchOne(database, sql: """
            SELECT COUNT(*) FROM (
                SELECT scope.scope_key, records.response FROM source_records AS records
                JOIN source_account_scope AS scope ON scope.source = records.source
                GROUP BY scope.scope_key, records.response
                HAVING COUNT(DISTINCT records.fingerprint) > 1
            )
            """) ?? 0
        diagnostics["duplicateRecords"] = try Int64.fetchOne(database, sql: """
            SELECT COALESCE(SUM(copies - 1), 0) FROM (
                SELECT COUNT(*) AS copies FROM source_records AS records
                JOIN source_account_scope AS scope ON scope.source = records.source
                GROUP BY scope.scope_key, records.response, records.fingerprint
            )
            """) ?? 0
        return diagnostics
    }
}
