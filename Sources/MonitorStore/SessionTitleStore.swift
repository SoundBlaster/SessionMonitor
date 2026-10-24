import Foundation
import GRDB

extension UsageStore {
    static func registerSessionTitleMigration(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("session-title-v1") { database in
            try database.execute(sql: "ALTER TABLE source_provenance ADD COLUMN session_title TEXT")
        }
    }

    /// Metadata stays source-scoped, and renames invalidate already-open report snapshots.
    public func updateSessionTitles(source: String, titles: [String: String]) throws {
        try database.write { database in
            let rows = try Row.fetchAll(database, sql: """
                SELECT session, session_title FROM source_provenance WHERE source = ?
                """, arguments: [source])
            var changed = false
            for row in rows {
                let session: String = row["session"]
                let existing: String? = row["session_title"]
                let title = titles[session]
                guard existing != title else { continue }
                try database.execute(sql: """
                    UPDATE source_provenance SET session_title = ? WHERE source = ? AND session = ?
                    """, arguments: [title, source, session])
                changed = true
            }
            if changed { try Self.advanceWatermark(database) }
        }
    }
}
