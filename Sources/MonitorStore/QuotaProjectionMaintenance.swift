import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    static func registerQuotaProjectionMigration(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("quota-presentation-projection-v1") { database in
            try database.execute(sql: Self.quotaProjectionSchema)
            for operation in ["INSERT", "DELETE", "UPDATE"] {
                let record = operation == "DELETE" ? "OLD" : "NEW"
                let previous = operation == "UPDATE"
                    ? """
                        INSERT INTO quota_projection_dirty SELECT OLD.event_identity
                        WHERE NOT EXISTS (
                            SELECT 1 FROM quota_projection_dirty WHERE event_identity = OLD.event_identity
                        );
                        """ : ""
                let changedScope = operation == "UPDATE" ? """
                    WHEN OLD.profile_id IS NOT NEW.profile_id OR OLD.scope_key IS NOT NEW.scope_key
                      OR OLD.state IS NOT NEW.state OR OLD.account_id IS NOT NEW.account_id
                      OR OLD.user_id IS NOT NEW.user_id
                    """ : ""
                try database.execute(sql: """
                    CREATE TRIGGER quota_projection_raw_\(operation) AFTER \(operation)
                    ON source_usage_limit_snapshots BEGIN
                        INSERT INTO quota_projection_dirty SELECT \(record).event_identity
                        WHERE NOT EXISTS (SELECT 1 FROM quota_projection_dirty
                                          WHERE event_identity = \(record).event_identity);
                        \(previous)
                    END;
                    CREATE TRIGGER quota_projection_scope_\(operation) AFTER \(operation)
                    ON source_account_scope \(changedScope) BEGIN
                        INSERT INTO quota_projection_dirty
                            SELECT DISTINCT event_identity FROM source_usage_limit_snapshots snapshots
                            WHERE source = \(record).source AND NOT EXISTS (
                                SELECT 1 FROM quota_projection_dirty d WHERE d.event_identity = snapshots.event_identity
                            );
                    END;
                    """)
            }
            try database.execute(sql: """
                CREATE TRIGGER quota_projection_label AFTER UPDATE ON account_profiles
                WHEN OLD.label IS NOT NEW.label BEGIN
                    INSERT INTO quota_projection_dirty
                    SELECT DISTINCT snapshots.event_identity FROM source_usage_limit_snapshots snapshots
                    JOIN source_account_scope scope ON scope.source = snapshots.source
                    WHERE scope.profile_id = NEW.profile_id AND NOT EXISTS (
                        SELECT 1 FROM quota_projection_dirty d WHERE d.event_identity = snapshots.event_identity
                    );
                END;
                INSERT INTO quota_projection_dirty SELECT DISTINCT event_identity FROM source_usage_limit_snapshots;
                """)
            try Self.refreshQuotaProjection(database)
        }
    }

    /// Rebuilds only changed event identities, including their mirrors in other sources/accounts.
    /// Runs before the import/mapping watermark advances, in the caller's write transaction.
    static func refreshQuotaProjection(_ database: Database) throws {
        guard try Bool.fetchOne(database, sql: "SELECT EXISTS(SELECT 1 FROM quota_projection_dirty)") == true else {
            return
        }
        try database.execute(sql: """
            CREATE TEMP TABLE IF NOT EXISTS quota_projection_batch (event_identity TEXT PRIMARY KEY NOT NULL)
            """)
        var seriesKeys: [QuotaPresentationSeriesKey: String] = [:]
        while true {
            // This LIMIT batches migration/import work; every queued identity is drained before commit.
            try database.execute(sql: """
                DELETE FROM quota_projection_batch;
                INSERT INTO quota_projection_batch SELECT event_identity FROM quota_projection_dirty LIMIT 1024;
                """)
            guard try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM quota_projection_batch") != 0 else { break }
            try database.execute(sql: """
                DELETE FROM quota_projection_windows
                    WHERE event_identity IN (SELECT event_identity FROM quota_projection_batch);
                DELETE FROM quota_projection_snapshots
                    WHERE event_identity IN (SELECT event_identity FROM quota_projection_batch);
                """)
            let rows = try Row.fetchAll(database, sql: Self.usageLimitRowsCTE(onlyProjectionBatch: true) + """
                SELECT * FROM ranked WHERE duplicate_rank = 1 ORDER BY timestamp, event_identity, slot_key
                """, arguments: Self.usageLimitArguments(try UsageQuery()))
            for snapshot in Self.snapshots(from: rows) {
                try Self.insertQuotaProjection(snapshot, seriesKeys: &seriesKeys, database: database)
            }
            try database.execute(sql: """
                DELETE FROM quota_projection_dirty
                    WHERE event_identity IN (SELECT event_identity FROM quota_projection_batch)
                """)
        }
    }

    private static func insertQuotaProjection(
        _ snapshot: UsageLimitSnapshotObservation, seriesKeys: inout [QuotaPresentationSeriesKey: String],
        database: Database
    ) throws {
        guard let scope = snapshot.accountScopeID else {
            throw DatabaseError(resultCode: .SQLITE_CORRUPT, message: "Quota projection has no account scope")
        }
        try database.execute(sql: """
            INSERT INTO quota_projection_snapshots VALUES (?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [scope, snapshot.eventIdentity, snapshot.accountScopeState.rawValue,
                              snapshot.timestamp.timeIntervalSince1970, snapshot.state.rawValue,
                              snapshot.windows.count, snapshot.accountProfileID, snapshot.accountProfileLabel])
        for window in snapshot.windows {
            let series = QuotaPresentationSeriesKey(snapshot: snapshot, window: window)
            let key = seriesKeys[series] ?? series.storageKey()
            seriesKeys[series] = key
            try database.execute(sql: """
                INSERT INTO quota_projection_windows VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [key, scope, snapshot.eventIdentity, window.slot.rawValue,
                                  snapshot.timestamp.timeIntervalSince1970, snapshot.sourceLine,
                                  window.resetsAt?.timeIntervalSince1970])
        }
    }
}
