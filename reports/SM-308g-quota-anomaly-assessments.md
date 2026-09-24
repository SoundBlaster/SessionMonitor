# SM-308g — quota anomaly assessments

## Result

Added account/window-scoped quota assessments to `codex-monitor doctor`. The policy compares observations only when account scope, quota scope/identifier, limit identity, window slot/duration, and reset interval match. It normalizes changes to percentage points per hour, so irregular polling intervals are comparable.

The first five prior intervals form the minimum robust baseline. A sharp shift requires both an absolute change of at least 10 percentage points/hour and a robust z-score of at least 3. Reset boundaries are surfaced as `reset_discontinuity` and never compared across. A zero-MAD baseline cannot establish a robust score and produces `unknown` when there is a material shift.

Known `codex.event_msg.token_count.rate_limits` events are imported as account-scoped quotas. An additive database migration backfills that scope for previously imported events with the same recognized source schema. Other or future schemas remain unknown until explicitly supported.

Quota outcomes are independent of session findings and use typed `stable_usage`, `sharp_shift`, `reset_discontinuity`, `unknown`, or `not_applicable` states. Missing or unresolved account identity is not applicable; incomplete, unsupported, stale, conflicting, incomplete-identity, or insufficient-history data remains explicitly unknown/not applicable with evidence. Quota evidence never attributes account-level consumption to an individual session; `sourceContextSessionID` is not exposed as session ownership.

`DiagnosticReport` adds `quotaAssessments` while retaining schema version 1 and decoding legacy reports without that field as an empty list. The CLI prints quota assessments in both JSON and text modes.

## Validation

- Final `make check-core` — passed: SwiftLint (0 violations), 143 tests in 20 suites, all CLI smoke tests, and performance smoke.
- Targeted quota and importer suites — 25 tests passed; includes importer reachability, existing-database scope backfill, historical partial/reset isolation, stable baseline correctness, and unique IDs across reset intervals.
- Quota CLI smoke imports a fresh seven-observation series through the production decoder/store and asserts `sharp_shift` in `doctor` JSON and text, with no session IDs in evidence.
- `git diff --check` — passed after final code and smoke-test changes.
- GitHub `CI`, `Native checks`, and `Workflow lint` passed on the final PR #62 revision.

## Boundaries

- No canonical accounting or session usage totals changed.
- Quota anomalies are account-level observations only; there is no per-session attribution.
- Insufficient history and robust scoring limitations are represented explicitly instead of inferred as stable use.
- Four PR #62 review findings are addressed; threads are resolved after pushing the fix commit.
- Delivered through [PR #62](https://github.com/SoundBlaster/SessionMonitor/pull/62), merge `476e2dd` (2026-09-24); roadmap completion is recorded in PR #63.
