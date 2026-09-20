# SM-312 - Interactive dense request timeline

Implemented and locally verified on 2026-09-20; [PR #32](https://github.com/SoundBlaster/SessionMonitor/pull/32) is open.

## Final behavior

The original 256-point sampler allowed semantic events to evict nearly all usage
requests. The final implementation replaces sampling entirely with temporal buckets
whose count depends on plot width: approximately 14 pt per slot, at most 120 slots.
Every visible request/event contributes once. Empty intervals stay empty.

Bars show sums of known cached and uncached tokens in each interval. The caption
states the interval size, request count and number with unavailable token data.
Requests missing either component are excluded from known sums and counted as
unavailable; observed zero remains known. Events are grouped into baseline markers
with full per-kind counts in the legend. Full source evidence and canonical accounting
are unchanged. Bucket timestamps are presentation centers, not rewritten source dates.

From/To fields use the report timezone and validate ordering and timeline bounds.
Zoom buttons halve/double the viewport, with a one-minute minimum unless the entire
available span is shorter. Earlier/later buttons and a position slider navigate
within bounds. Presets remain available. Refresh preserves a custom range; changing
session or query resets it. No oversized horizontal chart canvas is constructed.

## Validation

- `make lint lint-architecture`: no violations, errors or warnings.
- `make test-macos XCODEBUILD_FLAGS='-skipMacroValidation -only-testing:MonitorMacTests/RequestTimelineAxisTests -only-testing:MonitorMacTests/RequestTimelineDensityTests -only-testing:MonitorMacTests/TimelineViewportTests'`: 22 passed.
- Synthetic tests cover all-request token/count preservation under semantic floods,
  rare event counts, duplicate timestamps, viewport boundaries, empty/unknown/zero
  data, finite width limits, from/to validation, zoom/pan clamps, refresh and reset,
  and accessible labels for matching times on different dates.
- Production plot ImageRenderer attachments: dark 1000 pt and light 560 pt, visually
  reviewed. Attachments are available in xcresult; no private data is checked in.
- Native app on the reported real session: checked overview, zoom in, changed
  aggregation interval and request counts, and moved the position slider. Dates
  visibly match the report timezone. Native capture was dark; light verification
  uses the deterministic plot fixture.
- `git diff --check`: passed. Full `make check` was not repeated for this GUI-only change.
- PR review fix: accessibility event values now include the date for multi-day
  visible domains; targeted checks pass (23 tests).

## Boundaries

Zoom uses buttons and temporal scrolling uses the slider/arrows; gesture zoom and
trackpad horizontal panning are not implemented. From/to model validation is covered
by tests; native date-field typing was not separately automated. Interval token sums
must not be interpreted as individual request context size. Known sums can be partial
when the caption reports unavailable requests. Evidence remains the full query list.
The next planned feature is SM-308b.
