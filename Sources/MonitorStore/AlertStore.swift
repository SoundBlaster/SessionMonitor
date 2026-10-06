import Foundation
import GRDB
import MonitorCore
import MonitorPolicies

/// Alert state is operational metadata: it never changes canonical usage or the query watermark.
extension UsageStore {
    static func registerAlertMigration(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("alert-records-v1") { database in
            try database.execute(sql: """
                CREATE TABLE alert_records (
                    key TEXT PRIMARY KEY NOT NULL,
                    scope TEXT NOT NULL,
                    status TEXT NOT NULL,
                    last_seen REAL NOT NULL,
                    payload BLOB NOT NULL
                );
                CREATE INDEX alert_record_scopes ON alert_records(scope, status);
                CREATE INDEX alert_record_status ON alert_records(status, last_seen);
                """)
        }
    }

    /// Reads, transitions and stores alerts in one write transaction, so concurrent evaluations
    /// cannot both raise or notify the same key.
    public func applyAlertEvaluation(
        _ evaluation: AlertEvaluation, tracker: AlertTracker = AlertTracker()
    ) throws -> [AlertEvent] {
        try database.write { database in
            let existing = try Self.alertRecords(
                sql: "SELECT payload FROM alert_records", arguments: [], database: database
            )
            let result = tracker.apply(evaluation, to: existing)
            let encoder = Self.alertEncoder()
            for record in result.changedRecords {
                try database.execute(sql: """
                    INSERT INTO alert_records (key, scope, status, last_seen, payload) VALUES (?, ?, ?, ?, ?)
                    ON CONFLICT(key) DO UPDATE SET
                        scope = excluded.scope, status = excluded.status,
                        last_seen = excluded.last_seen, payload = excluded.payload
                    """, arguments: [
                        record.id, record.candidate.scope.id, record.status.rawValue,
                        record.lastSeenAt.timeIntervalSince1970, try encoder.encode(record)
                    ])
            }
            return result.events
        }
    }

    /// Alert records ordered by most recent observation; `nil` returns every status.
    public func alertRecords(status: AlertStatus? = nil) throws -> [AlertRecord] {
        try database.read { database in
            try Self.alertRecords(sql: """
                SELECT payload FROM alert_records
                WHERE ? IS NULL OR status = ?
                ORDER BY last_seen DESC, key ASC
                """, arguments: [status?.rawValue, status?.rawValue], database: database)
        }
    }

    private static func alertRecords(
        sql: String, arguments: StatementArguments, database: Database
    ) throws -> [AlertRecord] {
        let decoder = alertDecoder()
        return try Data.fetchAll(database, sql: sql, arguments: arguments).map {
            try decoder.decode(AlertRecord.self, from: $0)
        }
    }

    private static func alertEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static func alertDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        return decoder
    }
}
