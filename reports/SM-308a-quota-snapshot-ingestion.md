# SM-308a — quota snapshot ingestion

**Status:** partial deliverable for SM-308; [PR #30](https://github.com/SoundBlaster/SessionMonitor/pull/30)
is open. The parent SM-308 remains
unchecked; activity rollups, anomaly policies, attribution, and GUI presentation are still open.

## Result

- Added a versioned adapter for observed Codex `event_msg/token_count.rate_limits` events.
- Persisted normalized snapshots in a separate SQLite table with source line, event identity,
  timestamp, schema/adapter version, scope, limit metadata, window slot, duration, observed
  `used_percent`, and `resets_at`.
- Deduplicated identical event/window observations across mirrored source files while keeping
  separate reset epochs as separate observations.
- Added `codex-monitor quota` for imported data only. JSON and text output report coverage,
  freshness, observed used percentage, and remaining percentage explicitly derived from used.
- Kept quota observations outside canonical usage records and totals. Rollout thread context is
  retained as provenance and never treated as quota ownership.
- Missing quota events, missing window fields, and unsupported schema shapes remain unknown or
  partial; they are never converted to zero. No network polling was added.
- Added a synthetic CLI process smoke test and README usage documentation. No raw rollout data
  or personal identifiers were added to the repository.

## Validation

- `make check-core` — passed: CLI build, SwiftLint (0 violations), 89 core tests, watch/snapshot/
  quota/performance CLI smoke tests.
- `git diff --check` — passed.
- Quota-specific tests cover supported and unsupported schemas, missing fields, the primary,
  secondary and individual-limit slots, mirrored-event deduplication, reset boundaries,
  repeated/append imports, JSON round-trip, and unchanged canonical totals.

## Boundaries

- The source adapter currently recognizes primary, secondary, and individual-limit slots, but
  observed source evidence does not yet establish the ownership scope for these limits. Scope
  therefore remains `unknown` unless a future source format provides explicit evidence.
- No inference of account or model-pool usage from thread/session token totals is made.
- Activity breakdowns, anomaly findings, attribution, API-equivalent/subscription estimates, and
  GUI presentation remain in SM-308b–SM-308d.
