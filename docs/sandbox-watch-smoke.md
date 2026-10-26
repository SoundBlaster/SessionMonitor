# Signed sandbox Watching smoke test

This local XCUITest exercises the `MonitorMacStore` / `StoreDebug` app with real
system folder pickers and security-scoped bookmarks. It uses synthetic rollouts
and a new empty index, never a personal session archive or index.

## Run

Use an unlocked macOS desktop with Xcode UI automation enabled. Quit SessionMonitor
first, and finish other Xcode test runs: UI tests share the desktop, keyboard and
pointer. The Make target refuses to start when an app instance or another Xcode
test process is already running. Do not interact with the desktop during the run.
The standard ABC keyboard input source must be installed. The test selects it for
typing paths, then restores the previously selected input source in teardown.
It can also reveal the system's collapsed status area before opening Watching.

Configure local Apple Development signing as described in [Development](development.md).
The app and widget must retain their Store sandbox and App Group entitlements.
An ad-hoc signature or disabled sandbox cannot establish this acceptance result;
the test checks the app's signature, sandbox, bookmark and team entitlements.

```sh
rtk proxy make generate
rtk proxy make test-sandbox-watch \
  DERIVED_DATA=/absolute/build-volume/SessionMonitor/DerivedData \
  BUILD_ROOT=/absolute/build-volume/SessionMonitor/test-results
```

Use this checkout's configured build/cache locations and dependency flags. Existing
Make overrides, including `XCODEBUILD_FLAGS` and signing configuration, still apply.
The default macro-validation setting follows the existing repository build workflow;
it does not change global Xcode trust settings.

## What it checks

1. Choose an empty index folder through the native picker.
2. Start Watching through the menu bar and select a synthetic rollout folder.
3. Observe the first request, append another request, and observe the updated GUI count.
4. Pause, append a third request, verify that the paused report stays unchanged,
   then Resume and observe the third request.
5. Quit while Watching, append while the app is closed, then relaunch and verify
   saved grants, automatic Watching resume, and the fourth request.
6. Stop Watching, append a fifth request, and verify that the GUI stays at four.

The two unchanged-report assertions have a bounded two-second observation interval.
They do not establish that no update could ever occur after an arbitrary delay.

## Isolation and results

Only Debug builds recognize `SESSIONMONITOR_UI_TEST_SUITE`. Each run uses a unique
`SessionMonitor.UITests.<UUID>` preference suite across launches. Runtime loading,
account scope, imported-folder and Watching settings use that same suite. Widget
publication and notification delivery are disabled for this test; sandbox, SQLite,
file watching and bookmark operations remain the normal implementations.

The sandboxed UI runner creates the small synthetic fixture in its own writable
temporary directory. Build products, caches and `.xcresult` bundles use the supplied
build-volume locations. Teardown terminates the test app, clears only that run's
preference suite through an isolated reset launch, and removes its fixture. An
interrupted or killed runner may require cleanup of that run's temporary fixture
and preference suite; it must not trigger a reset of ordinary app preferences.

The Make target preserves a unique `.xcresult` under `BUILD_ROOT`, including test
failures and captured screenshots. Keep these local: desktop screenshots can include
other windows. A passing ordinary CI run does not imply this development-signed,
interactive smoke passed. The test is intentionally separate from the regular
ad-hoc `MonitorMac` CI suite.

This smoke does not cover moved/revoked grants, actual system widget rendering,
StoreRelease packaging, App Store Connect processing, TestFlight or review.
See [sandbox acceptance](sandbox-acceptance-2026-10-26.md) for recorded evidence
and [ROADMAP](../ROADMAP.md) for outstanding gates.
