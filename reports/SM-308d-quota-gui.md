# SM-308d — quota telemetry in the Session Report Inspector

## Scope

This slice adds a read-only quota telemetry section to the macOS Session Report
Inspector. It consumes the shared `QuotaPresentationReport` projection already used
by the CLI and does not introduce a second quota calculation path.

The section displays coverage, supported windows, observed used/remaining percentages,
freshness, reset time, reset discontinuity, and same-timestamp ambiguity. Unknown,
partial, unsupported, and no-window states remain visible as explanatory UI states.
Quota telemetry is account/report scoped in this slice: the UI does not attribute a
window to a session, model, or token total.

Reset discontinuity is rendered as a compact capsule button. Its popover explains that
the provider changed the reset boundary and compares the previous/current usage,
remaining percentage, reset timestamp, and observation timestamp. A discontinuity is
therefore inspectable without treating the transition as continuous quota consumption.

## Architecture

- `SessionExplorerRuntime` exposes the shared quota projection boundary.
- `SessionExplorerModel` loads the projection for the active `UsageQuery` and reloads
  it when the query or snapshot watermark changes.
- `QuotaPresentationSection` is a composable inspector feature with semantic fonts,
  system colors, stable window IDs, and combined accessibility labels.
- `SessionMonitor` and `SharedReportRuntime` forward the existing projection API;
  canonical accounting and import behavior are unchanged.

## Validation

- `make build-macos` — passed with Apple Development signing.
- Targeted model regression covers query and generated-at propagation.
- `make test-macos` — run before PR publication.
- `make lint` and `make lint-architecture` — run before PR publication.
- `git diff --check` — run before PR publication.

## Boundaries and next slice

This PR intentionally does not add session/model attribution, pricing, network polling,
or a second quota data source. The next SM-308d slice can connect telemetry to explicit
scope selectors once account identity and source provenance are exposed safely.
