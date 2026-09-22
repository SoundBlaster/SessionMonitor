# SM-308c — SpecificationCore anomaly policies

## Scope

This slice moves the existing polling, startup-overhead and cache rules into
`MonitorPolicies/AnomalyPolicyEngine`. Each rule is a concrete `Specification` plus a
typed `DecisionSpec`; the engine evaluates every independent decision so co-occurring
signals are retained.

`AnomalyFinding` is a machine-readable policy result with `AnomalyKind`, reason,
confidence, evidence and `AnomalyCoverage`. `UsageStore.doctor()` adapts these results
to the existing `DiagnosticFinding`/CLI contract, including coverage. Canonical accounting
is unchanged.

## SpecificationCore usage

`RepetitivePollingSpec` composes request-sample and polling-pair specifications with
`and`. `UnusualCacheChangeSpec` composes known-sample and cache-change specifications.
The runtime `doctor` path calls `AnomalyPolicyEngine`, whose heterogeneous decisions
are stored as `AnyDecisionSpec` and evaluated without first-match short-circuiting.

The correction pass validates policy configuration, sorts values before median calculation,
limits polling to one short sequence, scopes points to the selected session, separates
cache degradation from recovery, requires comparable cache samples, and gives findings a
stable scope-aware identity. The engine also exposes configurable absolute-usage,
dominant-session and uncached-burst decisions. Recovery is informational; degradation and
uncached bursts remain warnings.

## Validation

- `swift test --filter AnomalyPolicyTests --filter DiagnosticsTests` — targeted tests passed.
- `make check-core` — passed (build, SwiftLint, full core tests and CLI smoke checks).
- `make lint-architecture` — passed with 0 errors and 0 warnings.
- `git diff --check` — passed.
- The runtime diagnostics regression asserts `specification_core_policy` evidence.
- Negative fixtures cover normal process waits/clock sleep and unknown cache values.
- JSON round-trip covers machine-readable partial coverage.
- Regression fixtures cover unsorted median input, sparse waits, cache recovery, invalid
  configuration, high usage with high cache hit, dominant session share and uncached bursts.

## Remaining scope

Quota-aware rules, explicit insufficient/not-applicable outcomes, retry/progress evidence,
and compaction-aware comparisons still require additional source evidence. Absolute usage,
dominant-session and uncached-burst defaults are conservative policy thresholds and remain
configurable; they must not be presented as provider quota attribution.
