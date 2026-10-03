# SM-413 — Cache Hit Rate analytics window

Branch: `feat/sm-413-cache-analytics-window`; draft PR #79.
Independent of the pending core audit stack.

## Behavior

- Sidebar click focuses/reuses a singleton analytics scene with the same report, scope and palette.
- Sliders and bucket dropdown replaced by plot drag/scroll panning and pointer-anchored pinch zoom.
- Click pins a bucket; hover and pointer exit do not change selection. Pan, zoom and reset retain it.
- Selected interval statistics are prominent above the plot: weighted average, P10–P90 or min–max fallback, outliers and samples.
- Compact zoom/reset and previous/next buttons provide keyboard alternatives, including empty calendar slots.
- Full-report Y domain remains fixed. Visible marks and selection line stay inside the viewport.
- Independent accessibility slots expose Select bucket actions and stable identifiers.
- Shared renderer and privacy-safe report preserve accounting; no session/model identities or new database aggregation.
- The opening explorer owns updates; query changes clear old data before publishing a replacement.

## Validation — 2026-10-03

- Xcode-tools MCP BuildProject (including test targets): passed.
- Xcode-tools MCP RunSomeTests: 10/10 CacheAnalyticsTests passed, including pan bounds, pointer anchoring, invalid events, empty slots, persistent selection, source ownership, scope clearing and light/dark chart rendering.
- Project generation, strict SwiftLint, FSD lint, architecture negative regression: passed.
- The architecture negative probe intentionally emits an invalid-dependency error and exits successfully.
- Native Computer Use on a real 30-day report: Sidebar opening, accessibility selection, zoom buttons, drag pan, fixed Y scale and viewport clipping confirmed. The selected interval remains pinned above the chart after panning.
- Native accessibility tree exposes individual slot IDs and Select bucket actions.
- No command-line app build; no active CI polling after push.

## Remaining verification

Physical trackpad pinch and scroll-wheel feel require manual verification; Computer Use cannot synthesize pinch, and its horizontal-scroll command did not visibly move the plot. Pinch viewport arithmetic is unit-tested. Native dark/narrow-window interaction is not confirmed; light/dark render coverage is automated. Full make check was not run.

The analytics report remains the last source-window snapshot if its explorer closes; reopening from another explorer transfers ownership. No duplicate background query was introduced.

Next: manual trackpad/design review, then PR review and merge; SM-403 runtime accessibility audit remains the next roadmap task.
