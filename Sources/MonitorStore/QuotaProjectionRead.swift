import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    static func projectedQuotaEvidence(
        _ database: Database, query: UsageQuery, generatedAt: Date
    ) throws -> QuotaPresentationEvidence {
        let selected = try Row.fetchAll(database, sql: quotaProjectionWitnessSQL)
        let snapshots = try Self.quotaWitnessSnapshots(database, selected: selected)
        let accounts = try Row.fetchAll(database, sql: quotaProjectionCoverageSQL).map { row in
            QuotaAccountCoverage(
                accountScopeID: row["account_scope_id"], accountProfileID: row["account_profile_id"],
                accountProfileLabel: row["account_profile_label"],
                accountScopeState: UsageAccountScopeState(rawValue: row["account_scope_state"]) ?? .unknown,
                coverage: UsageLimitTelemetryCoverage(
                supportedWindowObservations: row["supported_count"], partialSnapshots: row["partial_count"],
                unsupportedSnapshots: row["unsupported_count"], snapshotsWithoutWindowData: row["empty_count"],
                latestObservedAt: (row["latest_observed"] as Double?).map(Date.init(timeIntervalSince1970:))
            ))
        }.sorted { $0.id < $1.id }
        return QuotaPresentationEvidence(
            query: query, generatedAt: generatedAt, snapshots: snapshots,
            coverage: Self.quotaCoverage(accounts), accountCoverages: accounts
        )
    }

    private static func quotaWitnessSnapshots(
        _ database: Database, selected: [Row]
    ) throws -> [UsageLimitSnapshotObservation] {
        let identities = Array(Set(selected.map { $0["event_identity"] as String })).sorted()
        let selectedKeys = Set(selected.map { "\($0["account_scope_id"] as String)|\($0["event_identity"] as String)" })
        var snapshots: [UsageLimitSnapshotObservation] = []
        // Batch parameters for SQLite builds with a small variable limit; every selected identity is read.
        for offset in stride(from: 0, to: identities.count, by: 256) {
            let batch = Array(identities[offset..<min(offset + 256, identities.count)])
            let placeholders = Array(repeating: "?", count: batch.count).joined(separator: ",")
            let sql = Self.usageLimitRowsCTE(
                eventPredicate: "AND snapshots.event_identity IN (\(placeholders))"
            ) + "SELECT * FROM ranked WHERE duplicate_rank = 1 ORDER BY timestamp, event_identity, slot_key"
            let bounds: StatementArguments = [nil, nil, nil, nil]
            let scope: StatementArguments = ["allAccounts", "allAccounts", nil, "allAccounts"]
            let rows = try Row.fetchAll(database, sql: sql, arguments: bounds + StatementArguments(batch) + scope)
            snapshots += Self.snapshots(from: rows).filter { selectedKeys.contains($0.id) }
        }
        return snapshots.sorted {
            if $0.timestamp != $1.timestamp { return $0.timestamp < $1.timestamp }
            return $0.eventIdentity < $1.eventIdentity
        }
    }

    static func quotaCoverage(_ accounts: [QuotaAccountCoverage]) -> UsageLimitTelemetryCoverage {
        UsageLimitTelemetryCoverage(
            supportedWindowObservations: accounts.reduce(0) { $0 + $1.coverage.supportedWindowObservations },
            partialSnapshots: accounts.reduce(0) { $0 + $1.coverage.partialSnapshots },
            unsupportedSnapshots: accounts.reduce(0) { $0 + $1.coverage.unsupportedSnapshots },
            snapshotsWithoutWindowData: accounts.reduce(0) { $0 + $1.coverage.snapshotsWithoutWindowData },
            latestObservedAt: accounts.compactMap { $0.coverage.latestObservedAt }.max()
        )
    }

    private static let quotaProjectionCoverageSQL = """
        SELECT c.*, first.account_profile_id, first.account_profile_label FROM (
            SELECT account_scope_id, account_scope_state,
                   SUM(window_count) AS supported_count, SUM(state = 'partial') AS partial_count,
                   SUM(state = 'unsupportedSchema') AS unsupported_count,
                   SUM(state = 'noWindowData') AS empty_count, MAX(timestamp) AS latest_observed
            FROM quota_projection_snapshots GROUP BY account_scope_id, account_scope_state
        ) c JOIN quota_projection_snapshots first ON first.rowid = (
            SELECT s.rowid FROM quota_projection_snapshots s
            WHERE s.account_scope_id = c.account_scope_id AND s.account_scope_state = c.account_scope_state
            ORDER BY timestamp, event_identity LIMIT 1
        )
        """

    // LIMIT 1 means the exact first/last observation by policy ordering, never an arbitrary tail cap.
    private static let quotaProjectionWitnessSQL = """
        WITH series AS (
            SELECT DISTINCT series_key FROM quota_projection_windows
        ), heads AS (
            SELECT series_key,
                (SELECT rowid FROM quota_projection_windows w WHERE w.series_key = s.series_key
                 ORDER BY timestamp DESC, line DESC, event_identity DESC LIMIT 1) AS latest_id,
                (SELECT rowid FROM quota_projection_windows w
                 WHERE w.series_key = s.series_key AND resets_at IS NOT NULL
                 ORDER BY timestamp DESC, line DESC, event_identity DESC LIMIT 1) AS reset_id
            FROM series s
        ), previous AS (
            SELECT h.*, (
                SELECT p.rowid FROM quota_projection_windows p
                WHERE p.series_key = h.series_key AND p.resets_at IS NOT NULL AND p.resets_at != r.resets_at
                ORDER BY timestamp DESC, line DESC, event_identity DESC LIMIT 1
            ) AS previous_id
            FROM heads h LEFT JOIN quota_projection_windows r ON r.rowid = h.reset_id
        ), transitions AS (
            SELECT h.*, (
                SELECT c.rowid FROM quota_projection_windows c
                WHERE c.series_key = h.series_key AND c.resets_at IS NOT NULL
                  AND (c.timestamp, c.line, c.event_identity) > (p.timestamp, p.line, p.event_identity)
                ORDER BY timestamp, line, event_identity LIMIT 1
            ) AS current_id
            FROM previous h LEFT JOIN quota_projection_windows p ON p.rowid = h.previous_id
        ), selected_events AS (
            SELECT w.account_scope_id, w.event_identity FROM heads h
            JOIN quota_projection_windows latest ON latest.rowid = h.latest_id
            JOIN quota_projection_windows w ON w.series_key = h.series_key AND w.timestamp = latest.timestamp
            UNION
            SELECT w.account_scope_id, w.event_identity FROM transitions t
            JOIN quota_projection_windows w ON w.rowid IN (t.previous_id, t.current_id)
        )
        SELECT account_scope_id, event_identity FROM selected_events
        """
}
