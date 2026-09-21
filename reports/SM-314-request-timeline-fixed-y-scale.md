# SM-314 — Fixed request-timeline Y scale

Implemented in `fix/sm-314-stable-timeline-y-scale`; [PR #36](https://github.com/SoundBlaster/SessionMonitor/pull/36) is open. GitHub CI passed for revision `d2925be` (`Native checks`, `Workflow lint`, and `CI`).

## Behavior

The request timeline now uses an explicit Y domain derived from all known usage
requests in the selected session/query. The reference window is based on the full
navigation span and chart bucket capacity, so it stays unchanged as the visible
window is zoomed or panned. A sliding-window maximum accounts for buckets whose
boundaries shift with the viewport and keeps their token sums inside the domain.
The domain includes 8% headroom and a finite `0...1` fallback for empty, unknown,
or zero-input data.

The chart's X range, temporal aggregation, source timestamps, evidence, and canonical
accounting are unchanged.

## Verification

- Targeted timeline suites: 26 tests passed before the render fixture was added.
- `TimelineYAxisScaleTests`: 4/4 passed, including an off-screen peak, zoom/pan
  invariance, viewport bucket coverage, empty/unknown/zero input, and fit/zoom renders.
- `make lint lint-architecture`: passed; 0 SwiftLint violations and 0 FSD errors/warnings.
- `git diff --check`: passed.
- The production `RequestTimelinePlot` was rendered and visually checked with a
  synthetic session in dark/system and light/monochrome, both fit and zoomed. The Y
  tick labels remain the same. Local `.xcresult` evidence is under
  `.build/quality/20260921T065110-8312964D-0CCC-4B09-B6B5-945B0A5FD28F.xcresult`.

The Xcode MCP server did not authorize this agent, so visual verification used
SwiftUI `ImageRenderer` and tests rather than a manually operated live app window.
The test build also reported an existing duplicate SwiftPM identity warning for
SpecificationCore; it did not fail the build or tests.
