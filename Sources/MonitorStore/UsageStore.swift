import CryptoKit
import Foundation
import GRDB
import MonitorCore

// swiftlint:disable function_body_length type_body_length

public final class UsageStore: Sendable {
    let database: DatabaseQueue
    public let databaseURL: URL

    public init(url: URL) throws {
        let url = try DatabaseSetupLock.prepareDatabaseURL(url)
        databaseURL = url
        let setup = try DatabaseSetupLock(url: url.appendingPathExtension("setup-lock"))
        defer { setup.release() }
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        database = try DatabaseQueue(path: url.path, configuration: configuration)
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode=WAL") }
        try Self.migrator().migrate(database)
    }

    private static func migrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("canonical-v1") { database in
            try database.execute(sql: """
                CREATE TABLE source_records (
                    source TEXT NOT NULL, line INTEGER NOT NULL, response TEXT NOT NULL,
                    session TEXT NOT NULL, turn TEXT NOT NULL, timestamp REAL NOT NULL,
                    model TEXT NOT NULL, input INTEGER NOT NULL CHECK(input >= 0),
                    cached INTEGER CHECK(cached >= 0 AND cached <= input),
                    output INTEGER NOT NULL CHECK(output >= 0), fingerprint TEXT NOT NULL,
                    cache_write INTEGER CHECK(cache_write >= 0),
                    reasoning INTEGER CHECK(reasoning >= 0 AND reasoning <= output),
                    total INTEGER CHECK(total >= 0),
                    PRIMARY KEY(source, line)
                );
                CREATE INDEX responses ON source_records(response, fingerprint);
                CREATE INDEX timestamps ON source_records(timestamp);
                CREATE TABLE source_diagnostics (
                    source TEXT NOT NULL, kind TEXT NOT NULL, count INTEGER NOT NULL,
                    PRIMARY KEY(source, kind)
                );
                CREATE VIEW confirmed AS
                    SELECT response, session, turn, MIN(timestamp) AS timestamp, model, input, cached, output,
                    cache_write, reasoning, total
                    FROM source_records GROUP BY response HAVING COUNT(DISTINCT fingerprint) = 1;
                """)
        }
        migrator.registerMigration("source-checkpoints-v1") { database in
            try database.execute(sql: """
                CREATE TABLE source_checkpoints (
                    source TEXT PRIMARY KEY NOT NULL, checkpoint BLOB NOT NULL
                )
                """)
        }
        migrator.registerMigration("query-watermark-v1") { database in
            try database.execute(sql: """
                CREATE TABLE query_watermark (
                    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
                    database_id TEXT NOT NULL, revision INTEGER NOT NULL,
                    committed_at REAL
                )
                """)
            try database.execute(sql: "INSERT INTO query_watermark VALUES (1, ?, 0, NULL)",
                                 arguments: [UUID().uuidString])
        }
        migrator.registerMigration("session-provenance-v1") { database in
            try database.execute(sql: """
                CREATE TABLE source_provenance (
                    source TEXT NOT NULL,
                    session TEXT NOT NULL,
                    root_session TEXT,
                    display_name TEXT,
                    agent_path TEXT,
                    originator TEXT,
                    client_version TEXT,
                    model_provider TEXT,
                    models TEXT NOT NULL,
                    efforts TEXT NOT NULL,
                    relationship_kind TEXT,
                    parent_session TEXT,
                    PRIMARY KEY(source, session)
                )
                """)
            try database.execute(sql: "CREATE INDEX provenance_sessions ON source_provenance(session)")
        }
        migrator.registerMigration("timeline-evidence-v1") { database in
            try database.execute(sql: """
                CREATE TABLE source_timeline_events (
                    source TEXT NOT NULL, line INTEGER NOT NULL,
                    session TEXT NOT NULL, turn TEXT, timestamp REAL NOT NULL,
                    kind TEXT NOT NULL, evidence TEXT NOT NULL,
                    PRIMARY KEY(source, line)
                );
                CREATE INDEX timeline_event_sessions ON source_timeline_events(session, timestamp);
                """)
        }
        migrator.registerMigration("legacy-estimates-v1") { database in
            try database.execute(sql: """
                CREATE TABLE source_legacy_estimates (
                    source TEXT NOT NULL, line INTEGER NOT NULL, session TEXT,
                    timestamp REAL NOT NULL, input INTEGER NOT NULL CHECK(input >= 0),
                    cached INTEGER CHECK(cached >= 0 AND cached <= input),
                    output INTEGER NOT NULL CHECK(output >= 0),
                    cache_write INTEGER CHECK(cache_write >= 0),
                    reasoning INTEGER CHECK(reasoning >= 0 AND reasoning <= output),
                    total INTEGER NOT NULL CHECK(total >= 0),
                    PRIMARY KEY(source, line)
                );
                CREATE INDEX legacy_estimate_timestamps ON source_legacy_estimates(timestamp);
                """)
        }
        return migrator
    }

    /// Replaces one complete source snapshot atomically; duplicate IDs remain globally idempotent.
    public func replace(source: String, rollout: ParsedRollout) throws {
        try database.write { database in
            try Self.clear(source: source, database: database)
            try Self.insert(rollout, source: source, database: database)
            try database.execute(sql: "DELETE FROM source_checkpoints WHERE source = ?", arguments: [source])
            try Self.advanceWatermark(database)
        }
    }

    public func checkpoint(source: String) throws -> Data? {
        try database.read { database in try Self.checkpoint(source: source, database: database) }
    }

    public func needsProvenanceBackfill(source: String) throws -> Bool {
        try database.read { database in
            try Bool.fetchOne(database, sql: """
                SELECT EXISTS(
                    SELECT 1 FROM source_records AS records
                    WHERE records.source = ?
                      AND NOT EXISTS(
                          SELECT 1 FROM source_provenance AS provenance
                          WHERE provenance.source = records.source
                            AND provenance.session = records.session
                      )
                )
                """, arguments: [source]) ?? false
        }
    }

    /// Adds metadata for existing canonical records without replacing records or diagnostics.
    /// The checkpoint is advanced with the metadata-only decoder result atomically.
    @discardableResult
    public func backfillProvenance(source: String, update: SourceImport,
                                   expectedCheckpoint: Data?) throws -> Bool {
        try database.write { database in
            guard try Self.checkpoint(source: source, database: database) == expectedCheckpoint else {
                throw CheckpointWriteError.staleCheckpoint
            }
            guard let provenance = update.rollout.provenance,
                  try Self.hasMissingProvenance(source: source, database: database) else { return false }
            try Self.insertProvenance(provenance, source: source, database: database)
            try database.execute(sql: """
                INSERT INTO source_checkpoints VALUES (?, ?)
                ON CONFLICT(source) DO UPDATE SET checkpoint = excluded.checkpoint
                """, arguments: [source, update.checkpoint])
            try Self.advanceWatermark(database)
            return true
        }
    }

    /// Events, diagnostics and decoder progress commit together. Stale retries cannot overwrite newer data.
    public func apply(source: String, update: SourceImport, expectedCheckpoint: Data?) throws {
        try database.write { database in
            let current = try Self.checkpoint(source: source, database: database)
            guard current == expectedCheckpoint else { throw CheckpointWriteError.staleCheckpoint }
            if update.mode == .unchanged { return }
            if update.mode == .replaced {
                try Self.clear(source: source, database: database)
            } else if current == nil {
                throw CheckpointWriteError.staleCheckpoint
            }
            // partialTails describes the current tail; all other diagnostics accumulate on append.
            try database.execute(sql: "DELETE FROM source_diagnostics WHERE source = ? AND kind = 'partialTails'",
                                 arguments: [source])
            try Self.insert(update.rollout, source: source, database: database)
            try database.execute(sql: """
                INSERT INTO source_checkpoints VALUES (?, ?)
                ON CONFLICT(source) DO UPDATE SET checkpoint = excluded.checkpoint
                """, arguments: [source, update.checkpoint])
            try Self.advanceWatermark(database)
        }
    }

    private static func checkpoint(source: String, database: Database) throws -> Data? {
        try Data.fetchOne(database, sql: "SELECT checkpoint FROM source_checkpoints WHERE source = ?",
                          arguments: [source])
    }

    private static func hasMissingProvenance(source: String, database: Database) throws -> Bool {
        try Bool.fetchOne(database, sql: """
            SELECT EXISTS(
                SELECT 1 FROM source_records AS records
                WHERE records.source = ?
                  AND NOT EXISTS(
                      SELECT 1 FROM source_provenance AS provenance
                      WHERE provenance.source = records.source
                        AND provenance.session = records.session
                  )
            )
            """, arguments: [source]) ?? false
    }

    private static func clear(source: String, database: Database) throws {
        try database.execute(sql: "DELETE FROM source_records WHERE source = ?", arguments: [source])
        try database.execute(sql: "DELETE FROM source_legacy_estimates WHERE source = ?", arguments: [source])
        try database.execute(sql: "DELETE FROM source_timeline_events WHERE source = ?", arguments: [source])
        try database.execute(sql: "DELETE FROM source_diagnostics WHERE source = ?", arguments: [source])
        try database.execute(sql: "DELETE FROM source_provenance WHERE source = ?", arguments: [source])
    }

    private static func insert(_ rollout: ParsedRollout, source: String, database: Database) throws {
        for record in rollout.records {
            let fingerprint = try Self.fingerprint(record)
            try database.execute(sql: """
                INSERT INTO source_records VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [
                    source, record.sourceLine, record.responseID, record.sessionID, record.turnID,
                    record.timestamp.timeIntervalSince1970, record.model, record.inputTokens,
                    record.cachedInputTokens, record.outputTokens, fingerprint,
                    record.cacheWriteInputTokens, record.reasoningOutputTokens, record.totalTokens
                ])
        }
        for estimate in rollout.legacyEstimates {
            try database.execute(sql: """
                INSERT INTO source_legacy_estimates VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """, arguments: [source, estimate.sourceLine, estimate.sessionID,
                                  estimate.timestamp.timeIntervalSince1970, estimate.inputTokens,
                                  estimate.cachedInputTokens, estimate.outputTokens,
                                  estimate.cacheWriteInputTokens, estimate.reasoningOutputTokens,
                                  estimate.totalTokens])
        }
        for event in rollout.timelineEvents {
            try database.execute(sql: """
                INSERT INTO source_timeline_events VALUES (?, ?, ?, ?, ?, ?, ?)
                """, arguments: [source, event.sourceLine, event.sessionID, event.turnID,
                                  event.timestamp.timeIntervalSince1970, event.kind.rawValue, event.evidence])
        }
        for (kind, count) in rollout.diagnostics {
            try database.execute(sql: """
                INSERT INTO source_diagnostics VALUES (?, ?, ?)
                ON CONFLICT(source, kind) DO UPDATE SET count = count + excluded.count
                """, arguments: [source, kind, count])
        }
        if let provenance = rollout.provenance {
            try Self.insertProvenance(provenance, source: source, database: database)
        }
    }

    private static func insertProvenance(_ provenance: SessionProvenance, source: String,
                                         database: Database) throws {
        let encoder = JSONEncoder()
        let models = try encoder.encode(provenance.models)
        let efforts = try encoder.encode(provenance.efforts)
        try database.execute(sql: """
            INSERT INTO source_provenance VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(source, session) DO UPDATE SET
                root_session = COALESCE(excluded.root_session, source_provenance.root_session),
                display_name = COALESCE(excluded.display_name, source_provenance.display_name),
                agent_path = COALESCE(excluded.agent_path, source_provenance.agent_path),
                originator = COALESCE(excluded.originator, source_provenance.originator),
                client_version = COALESCE(excluded.client_version, source_provenance.client_version),
                model_provider = COALESCE(excluded.model_provider, source_provenance.model_provider),
                models = excluded.models, efforts = excluded.efforts,
                relationship_kind = COALESCE(excluded.relationship_kind, source_provenance.relationship_kind),
                parent_session = COALESCE(excluded.parent_session, source_provenance.parent_session)
            """, arguments: [
                source, provenance.sessionID, provenance.rootSessionID, provenance.displayName,
                provenance.agentPath, provenance.originator, provenance.clientVersion,
                provenance.modelProvider, String(bytes: models, encoding: .utf8) ?? "[]",
                String(bytes: efforts, encoding: .utf8) ?? "[]", provenance.relationship?.kind.rawValue,
                provenance.relationship?.parentSessionID
            ])
    }

    public func report(since: Date?, until: Date?) throws -> UsageReport {
        try database.read { try Self.report($0, since: since, until: until) }
    }

    /// Returns legacy deltas separately. They are estimates, never part of `report`.
    public func legacyEstimates(since: Date? = nil, until: Date? = nil) throws -> [LegacyUsageEstimate] {
        try database.read { database in
            let start = since?.timeIntervalSince1970
            let end = until?.timeIntervalSince1970
            return try Row.fetchAll(database, sql: """
                SELECT * FROM source_legacy_estimates
                WHERE (? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)
                ORDER BY timestamp ASC, source ASC, line ASC
                """, arguments: [start, start, end, end]).map { row in
                LegacyUsageEstimate(source: row["source"], sessionID: row["session"],
                                     timestamp: Date(timeIntervalSince1970: row["timestamp"]),
                                     sourceLine: row["line"], inputTokens: row["input"],
                                     cachedInputTokens: row["cached"], outputTokens: row["output"],
                                     cacheWriteInputTokens: row["cache_write"],
                                     reasoningOutputTokens: row["reasoning"], totalTokens: row["total"])
            }
        }
    }

    /// Watermark and all report queries share one SQLite read transaction.
    /// A previous watermark must come from this same query; changed queries require an initial fetch.
    public func snapshot(query: UsageQuery, after previous: QueryWatermark? = nil) throws -> UsageSnapshot? {
        try database.read { database in
            guard let row = try Row.fetchOne(database, sql: "SELECT * FROM query_watermark WHERE singleton = 1") else {
                throw DatabaseError(resultCode: .SQLITE_CORRUPT, message: "Missing query watermark")
            }
            let committed: Double? = row["committed_at"]
            let watermark = QueryWatermark(databaseID: row["database_id"], revision: row["revision"],
                                           committedAt: committed.map(Date.init(timeIntervalSince1970:)))
            guard watermark != previous else { return nil }
            let report = try Self.report(database, since: query.since, until: query.until)
            return UsageSnapshot(query: query, watermark: watermark,
                                 report: report,
                                 provenance: try Self.provenance(database, sessionIDs: report.sessions.map(\.id)))
        }
    }

    private static func advanceWatermark(_ database: Database) throws {
        try database.execute(sql: """
            UPDATE query_watermark SET revision = revision + 1, committed_at = ? WHERE singleton = 1
            """, arguments: [Date().timeIntervalSince1970])
    }

    private static func report(_ database: Database, since: Date?, until: Date?) throws -> UsageReport {
        let predicate = "(? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)"
        let start = since?.timeIntervalSince1970
        let end = until?.timeIntervalSince1970
        let arguments: StatementArguments = [start, start, end, end]
        let totalsRow = try Row.fetchOne(database, sql: """
            SELECT \(Self.aggregates) FROM confirmed WHERE \(predicate)
            """, arguments: arguments)
        let sessions = try Row.fetchAll(database, sql: """
            SELECT session, CASE WHEN COUNT(DISTINCT model) = 1 THEN MIN(model) ELSE 'mixed' END AS model,
            \(Self.aggregates) FROM confirmed WHERE \(predicate)
            GROUP BY session ORDER BY inputs DESC, session ASC
            """, arguments: arguments).map { row in
                SessionSummary(id: row["session"], model: row["model"], totals: Self.totals(row))
            }
        return UsageReport(totals: totalsRow.map(Self.totals) ?? UsageTotals(),
                           sessions: sessions, diagnostics: try Self.diagnostics(database))
    }

    private static let aggregates = """
        COUNT(*) AS requests, COALESCE(SUM(input), 0) AS inputs,
        COALESCE(SUM(cached), 0) AS cached, COALESCE(SUM(output), 0) AS outputs,
        COALESCE(SUM(cached IS NULL), 0) AS unknown,
        CASE WHEN COUNT(cache_write) = COUNT(*) THEN SUM(cache_write) END AS cache_write,
        CASE WHEN COUNT(reasoning) = COUNT(*) THEN SUM(reasoning) END AS reasoning,
        CASE WHEN COUNT(total) = COUNT(*) THEN SUM(total) END AS total
        """

    private static func totals(_ row: Row) -> UsageTotals {
        UsageTotals(requests: row["requests"], inputTokens: row["inputs"], cachedInputTokens: row["cached"],
                    outputTokens: row["outputs"], unknownCacheRequests: row["unknown"],
                    cacheWriteInputTokens: row["cache_write"], reasoningOutputTokens: row["reasoning"],
                    totalTokens: row["total"])
    }

    private static func diagnostics(_ database: Database) throws -> [String: Int64] {
        var diagnostics: [String: Int64] = [:]
        let query = "SELECT kind, SUM(count) AS count FROM source_diagnostics GROUP BY kind"
        for row in try Row.fetchAll(database, sql: query) {
            diagnostics[row["kind"]] = row["count"]
        }
        diagnostics["conflictingResponseIDs"] = try Int64.fetchOne(database, sql: """
            SELECT COUNT(*) FROM (SELECT response FROM source_records GROUP BY response
            HAVING COUNT(DISTINCT fingerprint) > 1)
            """) ?? 0
        diagnostics["duplicateRecords"] = try Int64.fetchOne(database, sql: """
            SELECT COALESCE(SUM(copies - 1), 0) FROM
            (SELECT COUNT(*) AS copies FROM source_records GROUP BY response, fingerprint)
            """) ?? 0
        return diagnostics
    }

    private static func fingerprint(_ record: UsageRecord) throws -> String {
        let copy = UsageRecord(responseID: record.responseID, sessionID: record.sessionID, turnID: record.turnID,
                               timestamp: Date(timeIntervalSince1970: 0), model: record.model,
                               inputTokens: record.inputTokens, cachedInputTokens: record.cachedInputTokens,
                               outputTokens: record.outputTokens, sourceLine: 0,
                               cacheWriteInputTokens: record.cacheWriteInputTokens,
                               reasoningOutputTokens: record.reasoningOutputTokens, totalTokens: record.totalTokens)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return SHA256.hash(data: try encoder.encode(copy)).map { String(format: "%02x", $0) }.joined()
    }
}

// swiftlint:enable function_body_length type_body_length

public enum CheckpointWriteError: Error {
    case staleCheckpoint
}
