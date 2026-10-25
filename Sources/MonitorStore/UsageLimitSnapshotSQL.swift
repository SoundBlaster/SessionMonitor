// Shared resolution and source deduplication for raw telemetry and presentation evidence.
extension UsageStore {
    static var usageLimitRowsCTE: String { usageLimitRowsCTE(onlyProjectionBatch: false) }

    static func usageLimitRowsCTE(onlyProjectionBatch: Bool) -> String {
        let batch = onlyProjectionBatch
            ? "AND snapshots.event_identity IN (SELECT event_identity FROM quota_projection_batch)" : ""
        return usageLimitRowsCTE(eventPredicate: batch)
    }

    static func usageLimitRowsCTE(eventPredicate: String) -> String {
        usageLimitRowsTemplate.replacingOccurrences(of: "/* projection batch */", with: eventPredicate)
    }

    private static let usageLimitRowsTemplate = """
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
                /* projection batch */
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
        """
}
