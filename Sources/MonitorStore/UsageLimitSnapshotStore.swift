import Foundation
import CryptoKit
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
        migrator.registerMigration("usage-limit-account-identity-v1") { database in
            try database.execute(sql: "ALTER TABLE source_usage_limit_snapshots ADD COLUMN account_id TEXT")
            try database.execute(sql: "ALTER TABLE source_usage_limit_snapshots ADD COLUMN user_id TEXT")
        }
        migrator.registerMigration("usage-limit-account-scope-v1") { database in
            try database.execute(sql: """
                UPDATE source_usage_limit_snapshots
                SET scope = 'account'
                WHERE scope = 'unknown'
                  AND source_schema = 'codex.event_msg.token_count.rate_limits'
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
            INSERT INTO source_usage_limit_snapshots (
                source, line, event_identity, timestamp, context_session, adapter_version, source_schema,
                state, scope, scope_identifier, limit_id, limit_name, plan_type, slot_key,
                window_minutes, used_percent, resets_at, account_id, user_id
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """, arguments: [
                source, snapshot.sourceLine, snapshot.eventIdentity, snapshot.timestamp.timeIntervalSince1970,
                snapshot.sourceContextSessionID, snapshot.adapterVersion, snapshot.sourceSchema,
                snapshot.state.rawValue, snapshot.scope.rawValue, snapshot.scopeIdentifier,
                snapshot.limitID, snapshot.limitName, snapshot.planType, slotKey,
                window?.windowMinutes, window?.usedPercent, window?.resetsAt?.timeIntervalSince1970,
                snapshot.accountIdentity?.accountID, snapshot.accountIdentity?.userID
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
    // swiftlint:disable:next function_body_length
    func usageLimitRows(query: UsageQuery) throws -> [Row] {
        let lower = query.since?.timeIntervalSince1970
        let upper = query.until?.timeIntervalSince1970
        return try database.read { database in
            try Row.fetchAll(database, sql: """
                WITH scoped AS (
                    SELECT snapshots.*, scope.scope_key AS resolved_scope_key,
                           CASE WHEN scope.state = 'assigned'
                                      AND (snapshots.account_id IS NULL OR scope.account_id IS NULL
                                           OR snapshots.account_id = scope.account_id)
                                      AND (snapshots.user_id IS NULL OR scope.user_id IS NULL
                                           OR snapshots.user_id = scope.user_id)
                                THEN 'profile:' || scope.profile_id
                                WHEN snapshots.account_id IS NOT NULL OR snapshots.user_id IS NOT NULL
                                THEN 'identity:' || COALESCE(snapshots.account_id, scope.account_id, '')
                                     || char(31) || COALESCE(snapshots.user_id, scope.user_id, '')
                                ELSE scope.scope_key END AS dedup_scope_key,
                           CASE WHEN scope.state = 'mixed'
                                  OR (snapshots.account_id IS NOT NULL AND scope.account_id IS NOT NULL
                                      AND snapshots.account_id != scope.account_id)
                                  OR (snapshots.user_id IS NOT NULL AND scope.user_id IS NOT NULL
                                      AND snapshots.user_id != scope.user_id)
                                THEN NULL ELSE scope.profile_id END AS resolved_profile_id,
                           CASE WHEN scope.state = 'mixed'
                                  OR (snapshots.account_id IS NOT NULL AND scope.account_id IS NOT NULL
                                      AND snapshots.account_id != scope.account_id)
                                  OR (snapshots.user_id IS NOT NULL AND scope.user_id IS NOT NULL
                                      AND snapshots.user_id != scope.user_id)
                                THEN 'mixed'
                                WHEN scope.profile_id IS NOT NULL THEN 'assigned'
                                WHEN snapshots.account_id IS NOT NULL OR snapshots.user_id IS NOT NULL
                                  OR scope.account_id IS NOT NULL OR scope.user_id IS NOT NULL
                                THEN 'explicitIdentity'
                                ELSE scope.state END AS resolved_scope_state,
                           CASE WHEN scope.state = 'assigned'
                                      AND (snapshots.account_id IS NULL OR scope.account_id IS NULL
                                           OR snapshots.account_id = scope.account_id)
                                      AND (snapshots.user_id IS NULL OR scope.user_id IS NULL
                                           OR snapshots.user_id = scope.user_id)
                                THEN profiles.label END AS profile_label,
                           COALESCE(snapshots.account_id, scope.account_id) AS resolved_account_id,
                           COALESCE(snapshots.user_id, scope.user_id) AS resolved_user_id
                    FROM source_usage_limit_snapshots AS snapshots
                    JOIN source_account_scope AS scope ON scope.source = snapshots.source
                    LEFT JOIN account_profiles AS profiles ON profiles.profile_id = scope.profile_id
                    WHERE (? IS NULL OR snapshots.timestamp >= ?) AND (? IS NULL OR snapshots.timestamp < ?)
                ), ranked AS (
                    SELECT scoped.*, resolved_profile_id AS account_profile_id,
                           COUNT(*) OVER (PARTITION BY dedup_scope_key, event_identity, slot_key) AS source_count,
                           ROW_NUMBER() OVER (
                               PARTITION BY dedup_scope_key, event_identity, slot_key ORDER BY source ASC, line ASC
                           ) AS duplicate_rank
                    FROM scoped
                    WHERE (? = 'allAccounts'
                           OR (? = 'profile' AND resolved_profile_id = ?)
                           OR (? = 'unknownOrMixed' AND resolved_profile_id IS NULL))
                )
                SELECT * FROM ranked
                WHERE duplicate_rank = 1
                ORDER BY timestamp ASC, event_identity ASC, slot_key ASC
                """, arguments: [lower, lower, upper, upper,
                                  query.accountScope.kind.rawValue, query.accountScope.kind.rawValue,
                                  query.accountScope.profileID, query.accountScope.kind.rawValue])
        }
    }

    static func snapshots(from rows: [Row]) -> [UsageLimitSnapshotObservation] {
        var grouped: [String: SnapshotAccumulator] = [:]
        for row in rows {
            let identity: String = row["event_identity"]
            let scopeKey: String = row["dedup_scope_key"]
            let slotKey: String = row["slot_key"]
            let duplicates = max(0, (row["source_count"] as Int - 1))
            let groupKey = "\(scopeKey)\u{1f}\(identity)"
            if grouped[groupKey] == nil {
                grouped[groupKey] = SnapshotAccumulator(
                    eventIdentity: identity,
                    accountScopeID: Self.scopeIdentifier(scopeKey),
                    accountProfileID: row["account_profile_id"],
                    accountProfileLabel: row["profile_label"],
                    accountScopeState: UsageAccountScopeState(rawValue: row["resolved_scope_state"]) ?? .unknown,
                    accountIdentity: SourceAccountIdentity(
                        accountID: row["resolved_account_id"], userID: row["resolved_user_id"]
                    ),
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
            grouped[groupKey]?.windows.append(UsageLimitWindowObservation(
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

    static func scopeIdentifier(_ key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return digest
    }
}

private struct SnapshotAccumulator {
    let eventIdentity: String
    let accountScopeID: String
    let accountProfileID: String?
    let accountProfileLabel: String?
    let accountScopeState: UsageAccountScopeState
    let accountIdentity: SourceAccountIdentity?
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
            limitID: limitID, limitName: limitName, planType: planType, accountIdentity: accountIdentity,
            accountScopeID: accountScopeID, accountProfileID: accountProfileID,
            accountProfileLabel: accountProfileLabel, accountScopeState: accountScopeState,
            windows: windows.sorted { $0.slot.rawValue < $1.slot.rawValue },
            duplicateSourceRecords: duplicateSourceRecords
        )
    }
}
