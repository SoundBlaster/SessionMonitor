# SM-308b — Activity rollups

## Result

Added a read-only activity rollup API and `codex-monitor activity` command. The report
combines canonical usage totals with model and thread/model breakdowns, plus separately
classified source tool events. Queries support half-open time intervals and either an
exact session or a root session with its known children.

Tool classes use exact observed names (`exec_command`, `wait`, `write_stdin`,
`wait_threads`, and `clock.sleep`/`clock__sleep`). Unknown names and unknown event versions
remain `unknown` with their source evidence. Call and result/output source events remain
separate; their counts are explicitly source-event counts, not inferred invocation counts.

An additive SQLite migration stores event name, model, and activity class, and conservatively
backfills pre-existing tool events as unknown. Activity queries do not mutate canonical
records or totals.

## Validation

- `make check-core` — passed (core tests, SwiftLint, CLI build, and CLI/process smoke checks).
- `make lint-architecture` — passed, 0 warnings/errors.
- `make test-architecture` — passed.
- Manual `activity` CLI smoke checks — human-readable and JSON output passed.
- `git diff --check` — passed.
- Pull request [#41](https://github.com/SoundBlaster/SessionMonitor/pull/41) — open; required
  GitHub CI is pending.

Review follow-up coverage adds preservation of all optional canonical counters, decoding a
nested tool-event turn ID for model attribution, and deduplication of byte-identical mirrored
source events. Updated local checks are recorded on the PR revision after those fixes.

## Scope and limitations

This completes only the SM-308b activity-rollup slice. It does not implement SM-308c anomaly
policies or SM-308d GUI presentation and quota attribution. Event classification is limited
to explicit names observed in the supported source contract; unrecognized evidence remains
unknown rather than being guessed by substring matching.
