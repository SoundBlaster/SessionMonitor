import CryptoKit
import Foundation
import GRDB
import MonitorCore

public final class UsageStore: Sendable {
    private let database: DatabaseQueue

    public init(url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        database = try DatabaseQueue(path: url.path, configuration: configuration)
        try database.writeWithoutTransaction { try $0.execute(sql: "PRAGMA journal_mode=WAL") }
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
        try migrator.migrate(database)
    }

    /// Replaces one complete source snapshot atomically; duplicate IDs remain globally idempotent.
    public func replace(source: String, rollout: ParsedRollout) throws {
        try database.write { database in
            try database.execute(sql: "DELETE FROM source_records WHERE source = ?", arguments: [source])
            try database.execute(sql: "DELETE FROM source_diagnostics WHERE source = ?", arguments: [source])
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
            for (kind, count) in rollout.diagnostics {
                try database.execute(sql: "INSERT INTO source_diagnostics VALUES (?, ?, ?)",
                                     arguments: [source, kind, count])
            }
        }
    }

    public func report(since: Date?, until: Date?) throws -> UsageReport {
        try database.read { database in
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
