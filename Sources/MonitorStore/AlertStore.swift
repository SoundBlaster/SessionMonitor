import Foundation
import GRDB
import MonitorCore
import MonitorPolicies

/// An outbox entry: the transition was committed together with alert state, delivery is pending.
public struct PendingAlertEvent: Equatable, Sendable {
    public let id: Int64
    public let event: AlertEvent

    public init(id: Int64, event: AlertEvent) {
        self.id = id
        self.event = event
    }
}

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
        migrator.registerMigration("alert-outbox-v1") { database in
            try database.execute(sql: """
                CREATE TABLE alert_outbox (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    payload BLOB NOT NULL
                )
                """)
        }
    }

    /// Undelivered transitions kept when no sink drained them; the oldest are dropped beyond this bound.
    public static let alertOutboxLimit = 1_000

    /// Reads, transitions and stores alerts in one write transaction, so concurrent evaluations
    /// cannot both raise or notify the same key. The same transaction queues every event in the
    /// outbox, so a crash before sinks run never loses a transition.
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
            for event in result.events {
                try database.execute(sql: "INSERT INTO alert_outbox (payload) VALUES (?)",
                                     arguments: [try encoder.encode(event)])
            }
            try database.execute(sql: """
                DELETE FROM alert_outbox
                WHERE id <= (SELECT MAX(id) FROM alert_outbox) - ?
                """, arguments: [Self.alertOutboxLimit])
            return result.events
        }
    }

    /// Committed transitions not yet acknowledged by a delivery pass, oldest first.
    public func pendingAlertEvents() throws -> [PendingAlertEvent] {
        try database.read { database in
            let decoder = Self.alertDecoder()
            return try Row.fetchAll(database, sql: "SELECT id, payload FROM alert_outbox ORDER BY id ASC").map {
                PendingAlertEvent(id: $0["id"], event: try decoder.decode(AlertEvent.self, from: $0["payload"]))
            }
        }
    }

    /// Removes delivered entries. Unknown or already removed IDs are ignored.
    public func acknowledgeAlertEvents(ids: [Int64]) throws {
        guard !ids.isEmpty else { return }
        try database.write { database in
            for id in ids {
                try database.execute(sql: "DELETE FROM alert_outbox WHERE id = ?", arguments: [id])
            }
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
