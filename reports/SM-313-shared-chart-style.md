# SM-313 — Shared chart style

Date: 2026-09-20
Status: locally implemented and verified; PR not yet created.

## Result

Added a shared `UsageChartPalette` in `Sources/shared/lib`. The cache-hit chart and
request timeline resolve their accent, neutral, average, warning, event, axis-label,
and grid colors from the same semantic roles. Each feature still owns its chart marks,
layout, labels, and accounting semantics.

Added one persisted **Analytics chart colors** setting with System colors and
Monochrome options. The in-app sidebar and session detail read the same UserDefaults
selection, so changing it restyles both charts consistently. Monochrome keeps red for
semantic warnings. The cache widget lab can still inject palettes directly for fixture
review.

## Verification

- `make build-macos` — passed.
- `make lint lint-architecture test-architecture` — passed; SwiftLint reported zero
  violations, FSD reported zero errors/warnings, and the architecture negative fixture
  rejected an upward dependency as expected.
- Targeted GUI tests — 23 passed, including palette-role consistency and light/dark,
  narrow-width renders for System and Monochrome palettes.
- `git diff --check` — passed.
- Render images are attached to the local ignored xcresult under `.build/quality/`.

## Limitations

The Xcode MCP request to open this separate worktree was recorded as awaiting approval,
so validation used the repository's `make` targets with `xcodebuild`. The Settings
picker was compiler-checked and its shared storage key is covered by unit tests; an
interactive native Settings-window walkthrough was not performed.
