# SM-723: context-anatomy hover

## Cause and change

The chart stored every fractional pointer x coordinate in its root `@State`.
Even movement within one request invalidated that view. Time Profiler showed
the context and token-flow marks being rebuilt during hover, along with the
whole-session overview and accessibility summary work.

`ContextAnatomyInspection` now stores only the inspected request index. It
publishes a change only when that index changes. The chart owns this state,
while focused overlay views observe it: the vertical rule, snapshot, accessible
snapshot and lane highlight update independently of the chart's marks.
Keyboard/VoiceOver stepping moves the viewport only when necessary. Live data
shrinkage clamps the inspected index, and the overlay reads new anatomy inputs
directly. There is no global memoization cache or per-pointer asynchronous task.

## Measurement

Measured on 2026-10-18, MacBook Pro (24 GB), macOS 27, Xcode 27, optimized Release
(`-O`) through Xcode-tools. The local measurement build enables testability.
Two unrelated suites that refer to Debug-only widget fixtures were excluded
only in the local Release measurement build; the regular Debug GUI gate includes
them. Project settings and the user scheme used for measurement are not committed.

The deterministic fixture has 7,196 requests, context ramps with a drop every
200 requests, cached/new input and output/reasoning. The hosting window is
900 × 380 points. Each of three rounds delivers 240 events inside one request
and 240 events crossing requests. A calibration step uses the chart's actual
mapping to keep the first path inside one request. Assertions verify at most one
selection transition in that scenario and more than 200 in the second.

Baseline: `63f7e51` chart/lane code, instrumented only to expose the inspected
index to these assertions. This probe has no view subscribers in the baseline;
the original fractional root-state update still runs on every event.

Times include the `mouseMoved` callback, a 1 ms run-loop interval, layout,
`displayIfNeeded` and `CATransaction.flush`. They are event-to-layout replay
measurements, **not physical display latency or FPS**. The table shows the median
of the three round-level percentile measurements, in milliseconds:

| Pointer path | Before p50 | After p50 | Before p95 | After p95 |
| --- | ---: | ---: | ---: | ---: |
| Inside one request | 12.77 | 1.19 | 13.31 | 1.26 |
| Across requests | 24.70 | 5.53 | 25.60 | 16.52 |

The 1 ms run-loop interval is a measurement floor. Scheduler/rendering spikes
still occur; these measurements do not establish a universal frame-time bound.
The unchanged-request path's p95 across rounds was 13.28–13.67 ms before and
1.19–1.42 ms after; the changing-request path was 25.35–26.26 ms before and
16.45–16.67 ms after.

Time Profiler captures were taken alongside replay. Before the change, hover
backtraces included `ContextAnatomyChart.sizeChart`, `zoneColumns`,
`ContextAnatomyLane.columnMarks` and overview preparation. After the change,
sampled hover backtraces centered on inspection overlays and snapshot formatting;
the mark-building and overview paths no longer appeared there. This is sampled
trace evidence, not an instrumented invocation count. Trace durations cover
different numbers of completed events, so total sampled CPU times are not used
as a speedup ratio.

Raw traces, console logs and xcresults stay local on the build volume. They can
contain paths and process environment data and must not be published as artifacts.

## Reproduce

1. Follow the checkout's build-location preflight and discover the open workspace,
   `MonitorMac` scheme and My Mac destination using Xcode-tools.
2. Make an untracked local copy of the scheme with Run/Test configuration Release.
   Enable testability for the app and exclude `CacheAnalyticsTests.swift` and
   `CacheHitRateWidgetFixtureTests.swift` from that local measurement build because
   their fixtures are compiled only under `DEBUG`. Keep the normal GUI gate intact.
3. Set launch environment `SM723_HOVER_BENCHMARK=1`. Optionally set
   `SM723_VISUAL_PAUSE=30` to keep the one temporary benchmark window available
   briefly after the measurement. The window closes when the test finishes.
4. Run `MonitorMacTests/ContextAnatomyHoverPerformanceTests/testHoverReplay()`
   through Xcode-tools. The test prints `SM723 round=...` metrics and additionally
   checks pan/zoom mapping, dark/light appearance updates and live shrinkage.
5. For a trace, attach Time Profiler to the running test host, without launching
   another app instance, for example:

   ```sh
   rtk proxy xcrun xctrace record --template 'Time Profiler' --attach <PID> \
     --time-limit 15s --output <local-output>/hover.trace
   ```

6. Restore the normal `MonitorMac` scheme and remove the local source exclusions
   before running the complete GUI suite. Without the opt-in environment variable,
   the replay benchmark is skipped; deterministic selection regression tests run
   normally.

## Verification

The Release replay and five selection regression tests passed. The replay also
exercises zoom/pan followed by hover, both native appearances and replacement of
7,196 requests with 200 requests. It verifies selection follows the new viewport
and clamps on live shrinkage.

Computer Use checked the existing local session with 7,196 requests and 86
compactions in the app. The chart/card rendered, and the separate Request snapshot
accessibility element advanced from request 1 to request 2 with updated values.
The original report period was restored after this read-only smoke check.

The normal Debug scheme through Xcode-tools ran 237 GUI unit tests successfully
and skipped the opt-in replay. The remaining XCUITest did not initialize: its
runner reported `Timed out while enabling automation mode`; it has no test
result and is not counted as passed. The local UI smoke above uses Computer Use
independently of that runner. `make lint`, `make lint-architecture` and
`make test-architecture` passed. Core accounting, storage and import semantics
are outside this change; `make check-core` and full `make check` were not rerun.
