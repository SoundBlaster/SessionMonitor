import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    static func registerSourceRelocationMigration(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("source-relocation-v1") { database in
            try database.execute(sql: "CREATE INDEX source_storage_identity ON source_storage(file_identity)")
        }
    }

    /// Two matches are enough to reject ambiguous identity without loading historical sources.
    public func relocationCandidates(fileIdentity: String) throws -> [SourceRelocation] {
        try database.read { database in
            try Row.fetchAll(database, sql: """
                SELECT storage.source, storage.file_identity, progress.checkpoint, scope.scope_key,
                       (scope.state = 'unknown' AND scope.profile_id IS NULL) AS is_unknown
                FROM source_storage storage
                JOIN source_account_scope scope ON scope.source = storage.source
                LEFT JOIN source_checkpoints progress ON progress.source = storage.source
                WHERE storage.file_identity = ? ORDER BY storage.source LIMIT 2
                """, arguments: [fileIdentity]).map(Self.relocationEvidence)
        }
    }

    public func relocationDestinationIsAvailable(source: String) throws -> Bool {
        try database.read { try Self.relocationDestinationIsAvailable(source: source, database: $0) }
    }

    private static func relocationDestinationIsAvailable(source: String, database: Database) throws -> Bool {
        try Bool.fetchOne(database, sql: """
            SELECT NOT EXISTS (SELECT 1 FROM source_account_scope WHERE source = ?)
                AND NOT EXISTS (SELECT 1 FROM source_checkpoints WHERE source = ?)
                AND NOT EXISTS (SELECT 1 FROM source_storage WHERE source = ?)
                AND NOT EXISTS (
                    SELECT 1 FROM account_source_roots
                    WHERE source_root = ? OR substr(?, 1, length(source_root) + 1) = source_root || '/'
                )
            """, arguments: [source, source, source, source, source]) == true
    }

    static func relocate(_ evidence: SourceRelocation, to source: String, update: SourceImport,
                         expectedCheckpoint: Data?, database: Database) throws {
        let row = try Row.fetchOne(database, sql: """
            SELECT storage.source, storage.file_identity, progress.checkpoint, scope.scope_key,
                   (scope.state = 'unknown' AND scope.profile_id IS NULL) AS is_unknown
            FROM source_storage storage
            JOIN source_account_scope scope ON scope.source = storage.source
            LEFT JOIN source_checkpoints progress ON progress.source = storage.source
            WHERE storage.source = ?
            """, arguments: [evidence.source])
        guard let row, evidence.isUnknownAccountScope,
              let expectedCheckpoint, evidence.checkpoint == expectedCheckpoint,
              relocationEvidence(row) == evidence,
              update.rollout.sourceFile?.identity == evidence.fileIdentity,
              try relocationDestinationIsAvailable(source: source, database: database) else {
            throw CheckpointWriteError.staleCheckpoint
        }
        // All source-owned history and progress move in the import's transaction. Projection triggers
        // invalidate changed quota witnesses; advanceWatermark drains them before the commit is visible.
        for table in ["source_records", "source_diagnostics", "source_provenance", "source_timeline_events",
                      "source_legacy_estimates", "source_usage_limit_snapshots", "source_context_windows",
                      "source_storage", "source_checkpoints", "source_account_scope"] {
            try database.execute(sql: "UPDATE \(table) SET source = ? WHERE source = ?",
                                 arguments: [source, evidence.source])
        }
    }

    private static func relocationEvidence(_ row: Row) -> SourceRelocation {
        SourceRelocation(source: row["source"], fileIdentity: row["file_identity"], checkpoint: row["checkpoint"],
                         scopeKey: row["scope_key"], isUnknownAccountScope: row["is_unknown"])
    }
}
