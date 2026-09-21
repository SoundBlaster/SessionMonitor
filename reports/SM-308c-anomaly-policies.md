# SM-308c — SpecificationCore anomaly policies

## Scope

This slice moves the existing polling, startup-overhead and cache-change rules into
`MonitorPolicies/AnomalyPolicyEngine`. Each rule is a concrete `Specification` plus a
typed `DecisionSpec`; the engine evaluates every independent decision so co-occurring
signals are retained.

`AnomalyFinding` is a machine-readable policy result with `AnomalyKind`, reason,
confidence, evidence and `AnomalyCoverage`. `UsageStore.doctor()` adapts these results
to the existing `DiagnosticFinding`/CLI contract. Canonical accounting is unchanged.

## SpecificationCore usage

`RepetitivePollingSpec` composes request-sample and polling-pair specifications with
`and`. `UnusualCacheChangeSpec` composes known-sample and cache-change specifications.
The runtime `doctor` path calls `AnomalyPolicyEngine`, whose heterogeneous decisions
are stored as `AnyDecisionSpec` and evaluated without first-match short-circuiting.

## Validation

- `swift test --filter AnomalyPolicyTests --filter DiagnosticsTests` — 14 tests passed.
- `make check-core` — passed (build, SwiftLint, full core tests and CLI smoke checks).
- `make lint-architecture` — passed with 0 errors and 0 warnings.
- `git diff --check` — passed.
- The runtime diagnostics regression asserts `specification_core_policy` evidence.
- Negative fixtures cover normal process waits/clock sleep and unknown cache values.
- JSON round-trip covers machine-readable partial coverage.

## Remaining scope

High absolute spend, dominant-thread concentration, uncached bursts and quota-aware
rules still require additional evidence models and baselines. They remain outside this
bounded policy migration and must not use the captured daily sample as a hard-coded
threshold.
