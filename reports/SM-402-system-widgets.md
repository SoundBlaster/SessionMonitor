# SM-402 — Native Usage and Cache Hit Rate widgets

## Result

Extended the SM-401 WidgetKit extension with two system widgets backed only by the
existing App Group snapshot:

- **Usage Summary** presents today and last-seven-days totals in small, medium,
  and large families. It exposes aggregate requests, input, cached input, output,
  partial cache coverage, and no-activity states.
- **Cache Hit Rate** presents the weighted period rate and comparison delta with
  a P10–P90 range chart, weighted average marker, anonymous outliers, axis labels,
  and session count. It supports small, medium, and large families, with compact
  weekday labels at small size.

Components and geometry/colors/spacing values are separated into extension files;
fonts use SwiftUI text styles, and combined accessibility descriptions avoid
exposing session or model identities. Values outside the fixed 75–100% chart
range use edge indicators. Empty, partial, not-applicable, missing-snapshot, and
stale states are visible.

Tapping either widget opens the matching aggregate report using the registered
`sessionmonitor://` URL scheme. Usage links select Today or Last 7 Days; Cache Hit
Rate selects the seven-day cache report. Widget links carry no account, session,
or model identity.

The extension reads the shared JSON snapshot only. Snapshot publication reloads
all registered widgets; a low-frequency timeline policy provides a fallback and
does not promise second-level freshness.

## Validation

- Xcode MCP `BuildProject`: passed for app and widget extension.
- Xcode MCP `RunSomeTests`: 7/7 passed for deep-link routing, malformed links,
  snapshot validation, privacy, runtime projection, and atomic round-trip.
- `make lint`: passed with 0 SwiftLint violations.
- `make lint-architecture`: passed with 0 errors and 0 warnings.
- `make generate`: passed; the generated app Info.plist registers the URL scheme.
- `git diff --check`: passed.

## Pending system check

The Widget Gallery and rendered desktop/Notification Center appearance have not
been confirmed in the installed application. Xcode MCP `RenderPreview` cannot
render WidgetKit content for this macOS destination: it returned
`UnknownProcessType` and reported that no `widgetExtension` preview launcher is
registered. The user plans to restart macOS and check that both widgets appear in
the system picker. This is the remaining SM-402 acceptance check; building the
extension alone does not prove LaunchServices has registered the installed copy.
