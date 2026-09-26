# SM-401 — Shared snapshot and WidgetKit extension

## Result

Added a privacy-safe, aggregate-only Codable snapshot in the shared core, an
atomic App Group store, and a macOS WidgetKit extension that reads the snapshot
without opening the database or importing rollout files. The extension currently
serves as a small/medium snapshot smoke widget; product layouts and cache/usage
visualizations remain SM-402.

The app publishes on startup, explicit imports and updates, watch imports, and
new observed database revisions. A revision watermark fence retries when an
import overlaps snapshot construction. Explicit refresh also asks WidgetKit to
reload when the database revision stays constant, since the rolling time window
still advances.

## Privacy and consistency

- Snapshot includes aggregate today/last-7-days usage, cache coverage, and an
  identity-free cache distribution. It contains no session IDs, model names,
  source paths, or raw rollout content.
- App and extension share only the `group.ru.egormerkushev.session-monitor`
  container. Writes replace a complete JSON file atomically.
- The extension reads this file only; it has no database or importer dependency.

## Validation

- Xcode MCP `BuildProject` for `MonitorMac`: passed; app and extension targets
  build with signing enabled.
- Xcode MCP `RunSomeTests`: 5/5 passed, covering snapshot validation and
  round-trip, identity exclusion, runtime projection, and watch import callback.
- `make lint lint-architecture`: SwiftLint 0 violations; FSD 0 errors/warnings.
- `git diff --check`: passed.
- Widget Gallery / rendered-system-widget visual inspection was not performed;
  this PR validates the shared snapshot and extension integration, while visual
  product layouts are SM-402.
