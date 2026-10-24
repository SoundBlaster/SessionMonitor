import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    static func registerSourceStorageMigration(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("source-storage-v1") { database in
            try database.execute(sql: """
                CREATE TABLE source_storage (
                    source TEXT PRIMARY KEY NOT NULL,
                    session TEXT,
                    file_identity TEXT NOT NULL,
                    byte_count INTEGER NOT NULL CHECK(byte_count >= 0),
                    modified_at REAL NOT NULL,
                    observed_at REAL NOT NULL
                );
                CREATE INDEX storage_sessions ON source_storage(session);
                """)
        }
    }

    /// Persisted with the records/checkpoint. Unchanged imports backfill old indexes without reading bodies
    /// or emitting a new watermark for identical metadata. Queries never stat the source paths.
    @discardableResult
    static func updateSourceStorage(
        _ observation: SourceFileObservation?, source: String, database: Database
    ) throws -> Bool {
        guard let observation else { return false }
        try database.execute(sql: """
            INSERT INTO source_storage(source, session, file_identity, byte_count, modified_at, observed_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(source) DO UPDATE SET session = excluded.session,
                file_identity = excluded.file_identity, byte_count = excluded.byte_count,
                modified_at = excluded.modified_at, observed_at = excluded.observed_at
            WHERE source_storage.session IS NOT excluded.session
                OR source_storage.file_identity != excluded.file_identity
                OR source_storage.byte_count != excluded.byte_count
                OR source_storage.modified_at != excluded.modified_at
            """, arguments: [source, observation.sessionID, observation.identity, observation.byteCount,
                              observation.modifiedAt.timeIntervalSince1970, Date().timeIntervalSince1970])
        return database.changesCount > 0
    }

    static func sessionStorage(
        _ database: Database, accountScope: UsageAccountScope
    ) throws -> [String: SessionStorageSummary] {
        // Legacy sources with no owner metadata remain explicitly unknown until import observes an owner.
        // The IN subquery avoids scanning all records/events once their source metadata is available.
        let unknownSources = """
            SELECT scope.source FROM source_account_scope AS scope
            WHERE NOT EXISTS (SELECT 1 FROM source_provenance AS p WHERE p.source = scope.source)
              AND NOT EXISTS (SELECT 1 FROM source_storage AS s
                              WHERE s.source = scope.source AND s.session IS NOT NULL)
            """
        let rows = try Row.fetchAll(database, sql: """
            WITH candidates AS (
                SELECT p.source, p.session FROM source_provenance AS p
                WHERE NOT EXISTS (SELECT 1 FROM source_storage AS s
                                  WHERE s.source = p.source AND s.session IS NOT NULL AND s.session != p.session)
                UNION SELECT source, session FROM source_storage WHERE session IS NOT NULL
                UNION SELECT source, session FROM source_records WHERE source IN (\(unknownSources))
                UNION SELECT source, session FROM source_timeline_events WHERE source IN (\(unknownSources))
                UNION SELECT source, session FROM source_legacy_estimates
                    WHERE session IS NOT NULL AND source IN (\(unknownSources))
            ), ranked AS (
                SELECT candidates.session, storage.byte_count, storage.modified_at,
                    ROW_NUMBER() OVER (
                        PARTITION BY COALESCE('file:' || storage.file_identity,
                            'source:' || candidates.source || ':session:' || candidates.session)
                        ORDER BY storage.observed_at DESC, candidates.source
                    ) AS position
                FROM candidates
                JOIN (SELECT source, profile_id AS account_profile_id FROM source_account_scope) AS scope
                    ON scope.source = candidates.source
                LEFT JOIN source_storage AS storage
                    ON storage.source = candidates.source AND storage.session = candidates.session
                WHERE 1 = 1 \(accountScopePredicate("scope"))
            )
            SELECT session, COALESCE(SUM(byte_count), 0) AS known_bytes, COUNT(*) AS files,
                   SUM(byte_count IS NULL) AS unknown_files, MAX(modified_at) AS modified_at
            FROM ranked WHERE position = 1 GROUP BY session
            """, arguments: [accountScope.kind.rawValue, accountScope.kind.rawValue,
                              accountScope.profileID, accountScope.kind.rawValue])
        return Dictionary(uniqueKeysWithValues: rows.compactMap { row -> (String, SessionStorageSummary)? in
            let files: Int = row["files"]
            let unknown: Int = row["unknown_files"]
            guard unknown < files else { return nil }
            let modified: Double? = row["modified_at"]
            return (row["session"] as String, SessionStorageSummary(
                knownBytes: row["known_bytes"], fileCount: row["files"], unknownSizeFileCount: row["unknown_files"],
                lastModifiedAt: modified.map { Date(timeIntervalSince1970: $0) }
            ))
        })
    }

}
