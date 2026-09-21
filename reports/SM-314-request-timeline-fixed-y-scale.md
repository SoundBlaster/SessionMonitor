# SM-314 — Fixed request-timeline Y scale

Implemented in `fix/sm-314-stable-timeline-y-scale`; [PR #36](https://github.com/SoundBlaster/SessionMonitor/pull/36) is open. GitHub CI passed for implementation revision `e5e62a3` (`Native checks`, `Workflow lint`, and `CI`). A follow-up revision corrects the ROADMAP modification date raised in review.

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

## Scroll responsiveness follow-up

After the fixed-scale change, scrolling the dense timeline was reported to drop to
1–2 FPS. The viewport path now prepares a timestamp-sorted point index once per
timeline load, queries only the visible slice with binary search, and uses binary
search for event counts. The Y-axis scale is cached for the unchanged navigation
domain and chart width. The viewport controls and chart are isolated from the
unchanged evidence list, and slider drags no longer update both date-picker states
on every tick.

The synthetic Debug benchmark uses 20,000 points and projects 60 viewport updates
in approximately 86 ms total (about 1.4 ms per projection). A local UI smoke test
dragged the enabled slider on the reported dense-data shape (2,545 requests); the
range and chart updated. This validates the expensive projection path and basic
interaction, but is not a measured FPS result: Instruments/frame-time capture was
not available in this run, and the disk was nearly full, so a Release benchmark was
not completed. The PR's CI run is the next build validation for this follow-up.

## Verification

- Targeted timeline suites: 26 tests passed before the render fixture was added.
- `TimelineYAxisScaleTests`: 4/4 passed, including an off-screen peak, zoom/pan
  invariance, viewport bucket coverage, empty/unknown/zero input, and fit/zoom renders.
- `make lint lint-architecture`: passed; 0 SwiftLint violations and 0 FSD errors/warnings.
- `git diff --check`: passed.
- `RequestTimelineDensityTests` and `TimelineYAxisScaleTests`: 24/24 passed after
  the responsiveness follow-up. The dense 20,000-point/60-update benchmark is
  included in the targeted test suite.
- `make lint lint-architecture`: passed after the responsiveness follow-up; 0
  SwiftLint violations and 0 FSD errors/warnings.
- The production `RequestTimelinePlot` was rendered and visually checked with a
  synthetic session in dark/system and light/monochrome, both fit and zoomed. The Y
  tick labels remain the same. Local `.xcresult` evidence is under
  `.build/quality/20260921T065110-8312964D-0CCC-4B09-B6B5-945B0A5FD28F.xcresult`.

The Xcode MCP server did not authorize this agent, so visual verification used
SwiftUI `ImageRenderer` and tests rather than a manually operated live app window.
The test build also reported an existing duplicate SwiftPM identity warning for
SpecificationCore; it did not fail the build or tests.
