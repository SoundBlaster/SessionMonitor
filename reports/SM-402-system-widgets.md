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

## Gallery registration investigation

After the user reported that a macOS restart did not make the widgets appear,
the built products were compared with XcodeMini. Both projects embed a WidgetKit
extension with a unique bundle ID, a `com.apple.widgetkit-extension` point, a
`WidgetBundle`, and the App Group entitlement. The important difference was the
extension sandbox: XcodeMini's signed `.appex` contains
`com.apple.security.app-sandbox = true`; SessionMonitor's did not, because the
extension's effective `ENABLE_APP_SANDBOX` was `NO`.

Set `ENABLE_APP_SANDBOX: YES` on the SessionMonitor widget-extension target only.
The host app remains non-sandboxed. After project regeneration and an Xcode MCP
build, the signed extension contains both the sandbox and App Group entitlements,
the containing app passes `codesign --verify --deep --strict`, and PlugInKit now
lists exactly one registration at the current DerivedData app's
`Contents/PlugIns/SessionMonitorWidgetExtension.appex`. Before this change,
PlugInKit returned no registration for SessionMonitor while listing XcodeMini.

The system Widget Gallery has not yet been inspected directly. Reopen the Gallery
after this build and check for **Usage Summary** and **Cache Hit Rate**; the
extension is now registered without another reboot.

## Pending system check

The Widget Gallery and rendered desktop/Notification Center appearance have not
been confirmed directly. Xcode MCP `RenderPreview` cannot
render WidgetKit content for this macOS destination: it returned
`UnknownProcessType` and reported that no `widgetExtension` preview launcher is
registered. PlugInKit now confirms that the freshly built extension is registered;
checking that both display names appear in the system picker and inspecting the
rendered widgets is the remaining SM-402 acceptance check.
