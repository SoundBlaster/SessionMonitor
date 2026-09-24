# SM-308g — quota anomaly assessments

## Result

Added account/window-scoped quota assessments to `codex-monitor doctor`. The policy compares observations only when account scope, quota scope/identifier, limit identity, window slot/duration, and reset interval match. It normalizes changes to percentage points per hour, so irregular polling intervals are comparable.

The first five prior intervals form the minimum robust baseline. A sharp shift requires both an absolute change of at least 10 percentage points/hour and a robust z-score of at least 3. Reset boundaries are surfaced as `reset_discontinuity` and never compared across. A zero-MAD baseline cannot establish a robust score and produces `unknown` when there is a material shift.

Quota outcomes are independent of session findings and use typed `stable_usage`, `sharp_shift`, `reset_discontinuity`, `unknown`, or `not_applicable` states. Missing or unresolved account identity is not applicable; incomplete, unsupported, stale, conflicting, incomplete-identity, or insufficient-history data remains explicitly unknown/not applicable with evidence. Quota evidence never attributes account-level consumption to an individual session; `sourceContextSessionID` is not exposed as session ownership.

`DiagnosticReport` adds `quotaAssessments` while retaining schema version 1 and decoding legacy reports without that field as an empty list. The CLI prints quota assessments in both JSON and text modes.

## Validation

- `make check-core` — passed: CLI build, SwiftLint (0 violations), 139 tests in 20 suites, watch/snapshot/quota CLI smoke, and performance smoke.
- `QuotaAnomalyPolicyTests` — 13 targeted cases passed during implementation; covers robust shifts, irregular intervals, stable use, reset changes, unknown account, incomplete/unsupported/stale/ambiguous data, identity/window separation, no attribution, empty data, and legacy diagnostic decoding.
- `git diff --check` — passed after final code and smoke-test changes.
- GitHub CI has not been inspected or waited on; it runs after PR creation.

## Boundaries

- No canonical accounting or session usage totals changed.
- Quota anomalies are account-level observations only; there is no per-session attribution.
- Insufficient history and robust scoring limitations are represented explicitly instead of inferred as stable use.
- Roadmap completion remains pending PR merge.
