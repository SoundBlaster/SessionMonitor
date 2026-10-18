# Context anatomy insights (SM-718)

The Context anatomy card annotates the **observed request timeline**, not account quota or billing.
Expand **Context insights** below the chart for zone totals and the last inspected request's evidence.
Hover a request, or use the existing keyboard/VoiceOver stepping. The last inspected request remains
available in the evidence panel after the pointer leaves the plot.

Triangles show representative insight requests. On a dense viewport one representative is drawn per
absolute request bin, preferring critical entry, compaction, cache drop, context drop, growth, then cold
start. Every signal remains available in the request snapshot/evidence, including signals omitted from
the density-limited markers. Marker IDs identify the source request, never its viewport slot.

## Rules

`ContextInsightPolicy` in `MonitorPolicies` evaluates typed `DecisionSpec` rules from SpecificationCore
1.1.0. Context-change eligibility composes `ComparableContextRequestsSpec` and
`SignificantContextChangeSpec` with `.and`. Independent rules all run: a later signal does not replace
an earlier finding, and compaction does not suppress context growth/drop.

| Signal | Default criteria | Meaning and boundaries |
| --- | --- | --- |
| Context jump/drop | At least 8,000 tokens **and** 25% of previous input | Adjacent requests with a known, nonempty, equal model and nonnegative elapsed time. A drop alone does not establish reset/compaction. |
| Compaction observed | Explicit compaction event(s) before a request | Direct source evidence, independent of input change. Trailing events without a following request are counted in limitations. |
| Cold-start candidate | First observed request, input ≥ 1,000, cache share ≤ 10% | Hypothesis only. A bounded query can omit the actual session start. An earlier request with unknown input prevents labeling a later request as the first. |
| Cache drop after pause | Cache share falls ≥ 50 percentage points after ≥ 300 seconds; both inputs ≥ 1,000 | Adjacent comparable requests, valid known cache counters and the same reported model. Timing does not establish expiry or its cause. |
| Entered critical context zone | Crosses 90% of two equal, explicitly reported usable windows | Requires comparable adjacent requests. Suppressed for inferred windows, changed windows and the session-peak fallback. Remaining in critical does not emit another entry. |

All thresholds live in `ContextInsightConfiguration`, not UI conditionals. Cache ratios require
positive input and `0 ≤ cached ≤ input`. An unknown-input request breaks pair comparison; missing
cache/model evidence is never silently converted into zero or an assumed model match.

## Zone and phase summary

A phase is a contiguous run in one fill zone, split when the model/window changes or an unknown-input
request interrupts the run. The expandable summary groups these phases by zone and shows phase count,
request count, input and output request volume. Unknown output makes that aggregate unknown; overflow
also produces unknown rather than a wrapped/clamped exact-looking count. Unknown-input requests are
excluded and counted explicitly in limitations.

Input includes cached input; these sums are **request volume**, not unique context content or saved
money. Zone colors use the existing anatomy basis: usable model window when reported, otherwise the
session's own peak. Peak-relative critical rows do not mean the model is near capacity.

## Update and accessibility contract

The feature computes anatomy, policy report and UI projection once per timeline snapshot in a detached
task. Cancellation prevents an obsolete result being installed, and a report from a different query is
not displayed under the new query. Inspection is separately observed by leaf overlays and the evidence
panel; pointer movement does not rerun policies, phase summaries or static chart marks. Dictionaries
index signals by request for snapshot lookup.

The chart keeps its existing viewport/keyboard/VoiceOver controls. Representative markers expose their
request and signal titles; the adjustable Request snapshot exposes all selected signals and their
explanations. The evidence panel uses standard disclosures and text selection. Zone summaries adapt
from a grid to stacked rows when needed. Colors come from the existing shared chart palette. The plot
has internal Y-range padding for marker clearance without changing its data domain.

## Validation and remaining evidence

- Xcode-tools `BuildProject(buildForTesting: true)` succeeded.
- Targeted GUI/model run: 41/41 passed; complete `MonitorMacTests` run: 243 passed,
  1 normal opt-in hover-benchmark skip, 0 failures. After the final scope guard, the affected suites
  passed 11/11. The UI-test target was not run.
- Six new presentation tests cover 7,196-request marker density, stable IDs, signal priority,
  zone totals, retained evidence after pointer exit, and native light/dark/narrow rendering.
- Native `NSHostingView` fixture captures are attached to the test result. Swift Charts did not render
  faithfully through `ImageRenderer`, so these captures use the native view hierarchy instead.
- `make lint`, `make lint-architecture`, `make test-architecture` and `git diff --check` passed.
- Fourteen new `ContextInsightPolicyTests` cover positive/negative rules, threshold boundaries,
  missing input/cache/model, model/window changes, chronology, zero input, overflow, foreign sessions,
  trailing compaction, source preservation and deterministic IDs. On **2026-10-19**, after MCP approval,
  Xcode-tools built the core test bundle. MCP test actions then reported no results because their runner
  could not locate the bundle executable. Running that same built bundle directly with `xcrun xctest`
  succeeded: **249 Swift Testing tests in 41 suites plus 9 XCTest tests, all 258 passed**, including the
  14 new policy tests. This is successful test-runtime evidence, not a successful MCP test-action result;
  no command-line compilation or replacement build was used.
- Real-app Computer Use verification passed on **2026-10-19** in the Debug app launched through
  Xcode-tools: session `01a0ce3d-0bbd-76d2-9109-3d2fec0b3e45` with **7,196 requests, 86 compactions,
  178 insight signals**. Verified chart markers, the expanded four-zone summary, the adjustable request
  snapshot, and expanded cold-start evidence for request 1 (34,257 input, 0 cached, explicit window
  258,400). The explanation states that session start/cache expiry are not established. Evidence remained
  accessible outside the plot. This real-data smoke used dark appearance; light/dark/narrow rendering is
  covered separately by native deterministic fixtures.
- Restored the original report scope **Unknown/Mixed · Today · Local Europe/Moscow**, stopped the
  task-created app through Xcode-tools and restored the GUI scheme to **MonitorMac / My Mac**.
- No new Release latency/FPS measurement is claimed. The SM-723 selection-invalidation regressions pass.
- Full `make check`/`make check-core` were not run locally; builds/tests used Xcode-tools as requested.
  Required GitHub CI must run on this PR's current revision before merge.
