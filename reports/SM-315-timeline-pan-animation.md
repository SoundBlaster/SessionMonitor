# SM-315 — Request timeline pan animation

## Problem

While scrubbing the timeline viewport, bars shifted and changed heights together.
The aggregation used bucket IDs relative to the visible range (`0...N`), so Swift
Charts reused each mark identity for a different absolute time interval on every
viewport update.

## Change

- Align buckets to an absolute time grid and use the absolute bucket index as the
  mark identity. Same-zoom pan keeps stable bucket IDs and values.
- Clamp edge bucket plot timestamps to the visible range so partially visible
  buckets remain represented.
- Disable implicit animation in the request chart transaction during viewport
  updates, so interactive scrubbing does not interpolate marks between ranges.
- Keep a single aggregate bucket when the available width only allows one mark.
- Preserve request/event counts and token totals.

## Validation

- `xcodebuild -skipMacroValidation -project Apps/MonitorMac/MonitorMac.xcodeproj -scheme MonitorMac -configuration Debug -destination 'platform=macOS' -derivedDataPath .build/xcode -only-testing:MonitorMacTests/RequestTimelineDensityTests test` — 9/9 passed.
- `make lint` — passed, 0 SwiftLint violations.
- `make lint-architecture` — passed, 0 errors/warnings.
- `git diff --check` — passed.
- `RequestTimelineDensityTests` renders the production chart in light/dark and narrow/wide configurations.
- After merge, the user tested interactive scrolling in the app and confirmed the
  bars remain visually stable and the chart animation is acceptable.
