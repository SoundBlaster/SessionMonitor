extension UsageStore {
    static let quotaProjectionSchema = """
        CREATE TABLE quota_projection_dirty (event_identity TEXT PRIMARY KEY NOT NULL);
        CREATE INDEX quota_event_sources ON source_usage_limit_snapshots(event_identity, slot_key, source, line);
        CREATE TABLE quota_projection_snapshots (
            account_scope_id TEXT NOT NULL, event_identity TEXT NOT NULL, account_scope_state TEXT NOT NULL,
            timestamp REAL NOT NULL, state TEXT NOT NULL, window_count INTEGER NOT NULL,
            account_profile_id TEXT, account_profile_label TEXT,
            PRIMARY KEY(account_scope_id, event_identity)
        );
        CREATE INDEX quota_projection_coverage
            ON quota_projection_snapshots(account_scope_id, account_scope_state, state, window_count, timestamp);
        CREATE INDEX quota_projection_first
            ON quota_projection_snapshots(account_scope_id, account_scope_state, timestamp, event_identity);
        CREATE INDEX quota_projection_snapshot_events ON quota_projection_snapshots(event_identity);
        CREATE TABLE quota_projection_windows (
            series_key TEXT NOT NULL, account_scope_id TEXT NOT NULL, event_identity TEXT NOT NULL,
            slot_key TEXT NOT NULL, timestamp REAL NOT NULL, line INTEGER NOT NULL, resets_at REAL,
            PRIMARY KEY(account_scope_id, event_identity, slot_key)
        );
        CREATE INDEX quota_projection_latest
            ON quota_projection_windows(series_key, timestamp, line, event_identity);
        CREATE INDEX quota_projection_window_events ON quota_projection_windows(event_identity);
        CREATE INDEX quota_projection_resets
            ON quota_projection_windows(series_key, timestamp, line, event_identity, resets_at)
            WHERE resets_at IS NOT NULL;
        """
}
