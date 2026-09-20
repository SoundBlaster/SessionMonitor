import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    static func registerUsageLimitSnapshotMigration(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("usage-limit-snapshots-v1") { database in
            try database.execute(sql: """
                CREATE TABLE source_usage_limit_snapshots (
                    source TEXT NOT NULL, line INTEGER NOT NULL, event_identity TEXT NOT NULL,
                    timestamp REAL NOT NULL, context_session TEXT, adapter_version INTEGER NOT NULL,
                    source_schema TEXT, state TEXT NOT NULL, scope TEXT NOT NULL, scope_identifier TEXT,
                    limit_id TEXT, limit_name TEXT, plan_type TEXT, slot_key TEXT NOT NULL,
                    window_minutes INTEGER CHECK(window_minutes IS NULL OR window_minutes > 0),
                    used_percent REAL CHECK(used_percent IS NULL OR used_percent >= 0),
                    resets_at REAL,
                    PRIMARY KEY(source, line, slot_key)
                );
                CREATE INDEX usage_limit_snapshot_timestamps
                    ON source_usage_limit_snapshots(timestamp, event_identity, slot_key);
                """)
        }
    }

    static func clearUsageLimitSnapshots(source: String, database: Database) throws {
        try database.execute(sql: "DELETE FROM source_usage_limit_snapshots WHERE source = ?", arguments: [source])
    }

    static func insertUsageLimitSnapshot(
        _ snapshot: UsageLimitSnapshotObservation, source: String, database: Database
    ) throws {
        try insertUsageLimitRow(snapshot, window: nil, slotKey: "__event__", source: source, database: database)
        for window in snapshot.windows {
            try insertUsageLimitRow(
                snapshot, window: window, slotKey: window.slot.rawValue, source: source, database: database
            )
        }
    }

    private static func insertUsageLimitRow(
        _ snapshot: UsageLimitSnapshotObservation, window: UsageLimitWindowObservation?, slotKey: String,
        source: String, database: Database
    ) throws {
        try database.execute(sql: """
            INSERT INTO source_usage_limit_snapshots VALUES (
                ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
            )
            """, arguments: [
                source, snapshot.sourceLine, snapshot.eventIdentity, snapshot.timestamp.timeIntervalSince1970,
                snapshot.sourceContextSessionID, snapshot.adapterVersion, snapshot.sourceSchema,
                snapshot.state.rawValue, snapshot.scope.rawValue, snapshot.scopeIdentifier,
                snapshot.limitID, snapshot.limitName, snapshot.planType, slotKey,
                window?.windowMinutes, window?.usedPercent, window?.resetsAt?.timeIntervalSince1970
            ])
    }
}

extension UsageStore {
    /// Reads imported quota telemetry only; it never requests current values from a network service.
    public func usageLimitSnapshots(
        query: UsageQuery, generatedAt: Date = Date()
    ) throws -> UsageLimitSnapshotReport {
        let snapshots = Self.snapshots(from: try usageLimitRows(query: query))
        return UsageLimitSnapshotReport(query: query, generatedAt: generatedAt, snapshots: snapshots)
    }
}

private extension UsageStore {
    func usageLimitRows(query: UsageQuery) throws -> [Row] {
        let lower = query.since?.timeIntervalSince1970
        let upper = query.until?.timeIntervalSince1970
        return try database.read { database in
            try Row.fetchAll(database, sql: """
                WITH ranked AS (
                    SELECT *,
                           COUNT(*) OVER (PARTITION BY event_identity, slot_key) AS source_count,
                           ROW_NUMBER() OVER (
                               PARTITION BY event_identity, slot_key ORDER BY source ASC, line ASC
                           ) AS duplicate_rank
                    FROM source_usage_limit_snapshots
                    WHERE (? IS NULL OR timestamp >= ?) AND (? IS NULL OR timestamp < ?)
                )
                SELECT * FROM ranked
                WHERE duplicate_rank = 1
                ORDER BY timestamp ASC, event_identity ASC, slot_key ASC
                """, arguments: [lower, lower, upper, upper])
        }
    }

    static func snapshots(from rows: [Row]) -> [UsageLimitSnapshotObservation] {
        var grouped: [String: SnapshotAccumulator] = [:]
        for row in rows {
            let identity: String = row["event_identity"]
            let slotKey: String = row["slot_key"]
            let duplicates = max(0, (row["source_count"] as Int - 1))
            if grouped[identity] == nil {
                grouped[identity] = SnapshotAccumulator(
                    eventIdentity: identity,
                    timestamp: Date(timeIntervalSince1970: row["timestamp"]),
                    sourceLine: row["line"],
                    sourceContextSessionID: row["context_session"],
                    adapterVersion: row["adapter_version"],
                    sourceSchema: row["source_schema"],
                    state: UsageLimitSnapshotState(rawValue: row["state"]) ?? .unsupportedSchema,
                    scope: UsageLimitScope(rawValue: row["scope"]) ?? .unknown,
                    scopeIdentifier: row["scope_identifier"],
                    limitID: row["limit_id"],
                    limitName: row["limit_name"],
                    planType: row["plan_type"],
                    duplicateSourceRecords: duplicates
                )
            }
            guard slotKey != "__event__", let slot = UsageLimitWindowSlot(rawValue: slotKey) else { continue }
            grouped[identity]?.windows.append(UsageLimitWindowObservation(
                slot: slot,
                windowMinutes: row["window_minutes"],
                usedPercent: row["used_percent"],
                resetsAt: (row["resets_at"] as Double?).map(Date.init(timeIntervalSince1970:))
            ))
        }
        return grouped.values.map(\.value).sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.eventIdentity < $1.eventIdentity
        }
    }
}

private struct SnapshotAccumulator {
    let eventIdentity: String
    let timestamp: Date
    let sourceLine: Int
    let sourceContextSessionID: String?
    let adapterVersion: Int
    let sourceSchema: String?
    let state: UsageLimitSnapshotState
    let scope: UsageLimitScope
    let scopeIdentifier: String?
    let limitID: String?
    let limitName: String?
    let planType: String?
    let duplicateSourceRecords: Int
    var windows: [UsageLimitWindowObservation] = []

    var value: UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: eventIdentity, timestamp: timestamp, sourceLine: sourceLine,
            sourceContextSessionID: sourceContextSessionID, adapterVersion: adapterVersion,
            sourceSchema: sourceSchema, state: state, scope: scope, scopeIdentifier: scopeIdentifier,
            limitID: limitID, limitName: limitName, planType: planType,
            windows: windows.sorted { $0.slot.rawValue < $1.slot.rawValue },
            duplicateSourceRecords: duplicateSourceRecords
        )
    }
}
