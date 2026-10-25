import Foundation
import GRDB
import MonitorCore

extension UsageStore {
    /// The all-time/all-account path decodes only latest ties and reset witnesses from the projection.
    /// Filtered queries or an older writer's pending invalidations fall back to the exact raw query.
    /// This is presentation evidence only; anomaly detectors must keep using the raw history API.
    public func quotaPresentationEvidence(
        query: UsageQuery, generatedAt: Date = Date()
    ) throws -> QuotaPresentationEvidence {
        try database.read { database in
            // Period/account filters precede dedup in the raw contract. The all-time, all-account
            // projection is not substituted for those queries, including conflicting mirrored rows.
            let dirty = try Bool.fetchOne(database, sql: "SELECT EXISTS(SELECT 1 FROM quota_projection_dirty)") ?? false
            if query.since == nil, query.until == nil, query.accountScope == .allAccounts, !dirty {
                return try Self.projectedQuotaEvidence(database, query: query, generatedAt: generatedAt)
            }
            // Compatibility path for filtered queries and older writers that only mark events dirty.
            // No stale projection is returned. These cases deliberately retain the raw query semantics.
            let rows = try Row.fetchAll(database, sql: Self.usageLimitRowsCTE + """
                SELECT * FROM ranked WHERE duplicate_rank = 1 ORDER BY timestamp, event_identity, slot_key
                """, arguments: Self.usageLimitArguments(query))
            return QuotaPresentationEvidence(report: UsageLimitSnapshotReport(
                query: query, generatedAt: generatedAt, snapshots: Self.snapshots(from: rows)
            ))
        }
    }
}
