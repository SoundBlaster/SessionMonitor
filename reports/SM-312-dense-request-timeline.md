# SM-312 — Dense request timeline

Implemented locally on 2026-09-20; [PR #32](https://github.com/SoundBlaster/SessionMonitor/pull/32) is open. Delivery requires the PR to merge.

## Cause and change

The previous 256-point projection reserved all semantic events before usage. Once
semantic events exhausted that budget, almost all usage requests disappeared.
Every semantic point also carried an overlapping text annotation.

The projection now filters the visible domain before sampling and gives usage an
independent budget (at least 192 points when enough requests exist). Semantic
sampling is balanced by event kind so a tool/unknown flood does not erase rare
compactions or human turns. Usage endpoints and cached/uncached peaks survive.
The full evidence list and canonical accounting are unchanged.

`RequestTimelinePlot` renders fixed-width cached/uncached stacked segments, small
baseline event symbols, and accessible event labels. A wrapping legend outside
the plot reports the full visible event counts. No per-event text overlays remain.

## Validation

- `make lint lint-architecture`: no violations, errors or warnings.
- `make test-macos XCODEBUILD_FLAGS='-skipMacroValidation -only-testing:MonitorMacTests/RequestTimelineAxisTests -only-testing:MonitorMacTests/RequestTimelineDensityTests'`: 17 passed.
- Synthetic fixture: 581 requests, 2,400 tool/unknown events, one rare compaction;
  cached and uncached peaks, endpoints, sparse/empty/unknown/zero cases, event-only
  timelines, and visible-window filtering are covered.
- Production plot ImageRenderer attachments: dark 1000 pt and light 560 pt, visually
  reviewed. Tests attach PNGs to xcresult; the complete view contains native controls
  and scroll containers, so it is validated in the native app separately.
- Native app launched from this worktree: selected the reported real session,
  checked Fit to data and Last events, readable bars, external event legend and
  retained evidence. Native capture was dark; light verification is the plot fixture.
- Read-only inspection of the local database reproduced the starvation; no raw
  session contents or private database exports are included in this repository.
- `git diff --check`: passed. Full `make check` was not repeated for this GUI-only fix.

## Remaining boundaries

The chart is a bounded sample, not an exhaustive per-request visualization or a
bucket-total chart. Close timestamps can still overlap at limited pixel resolution;
Last events provides detail while the evidence list preserves every observation.
The next planned feature is SM-308b.
