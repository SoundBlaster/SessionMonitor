# Signed sandbox acceptance — October 26, 2026

SM-706; source commit `65fa957182149330b97261e7696dd9677cbb0581`, delivered in
[PR #147](https://github.com/SoundBlaster/SessionMonitor/pull/147).
This is a bounded local development-build check, not App Store acceptance.

## Build and signing

- Xcode 27.1 (`27A9275`), `MonitorMacStore` / `StoreDebug`, arm64, version 0.1.1 (2).
- Xcode-tools discovered the Store scheme/My Mac and attempted the build; the changed
  `SpecificationCoreMacros` fingerprint blocked it before compilation.
- The owner's existing per-command `-skipMacroValidation` authorization was used with
  `asc xcode archive` through the ASC authentication helper. The existing Keychain API
  profile supplied Xcode signing authentication; temporary key staging was cleaned up.
- The app used the existing Mac Team app development profile; the widget used a Mac Team
  wildcard profile. Both signatures identify the same Apple Development identity/team.
- `codesign --verify --deep --strict` succeeded for app and widget. Both signed entitlement
  sets contain App Sandbox and the existing App Group. The app also contains user-selected
  read/write access and app-scoped bookmarks. Signing alone does not prove runtime access.
- Archive, log, local receipt, synthetic data and protected state backups remain outside
  Git on the verified external build volume. No source code or dependency pins changed.

## Native observations

Computer Use operated one app instance at a time, using real Open/Save Panels and full
quit/relaunch. Only synthetic rollouts and an isolated external index were selected.

| Step | Observed result |
| --- | --- |
| First launch | Connection screen asks the person to choose an index folder |
| Select index populated by external CLI | GUI: 1 request, input 100, output 10, cached 80 |
| Quit and relaunch | Same report; bookmark restored without choosing the folder again |
| CLI append/import while GUI runs | Incremental CLI read; GUI and both charts update to 2 requests |
| GUI Import with separate source-folder grant | 3 requests, input 600, output 60, cached 480 |
| Export via Save Panel to another folder | Valid 873-byte JSON with `format` and `requests`; test session ID absent |
| Second quit/relaunch, then Update | Saved source bookmark works; 4 requests, input 1000, output 100, cached 800 |
| External CLI reads final database | Same 4 requests and token totals, zero duplicate/conflicting-response diagnostics |
| App Group publication | Aggregate snapshot file changes and contains the synthetic request count |

Before testing, the app's preferences and existing widget snapshot were backed up outside
Git with private permissions. After the app exited, prior values were restored, test-only
preference keys removed, and restored data compared with the backup. A subsequent cold
launch returned to the connection screen, confirming that the synthetic index selection
was removed. The test app was then closed; no extra instance was left running.

## Remaining gates

A subsequent automation change in [PR #148](https://github.com/SoundBlaster/SessionMonitor/pull/148)
adds a [dedicated Watching XCUITest command](sandbox-watch-smoke.md). Its current
StoreRelease build, signed StoreDebug `build-for-testing` and deep/strict signature
verification passed, as did 35 targeted unit tests, SwiftLint and positive/negative
FSD checks. The full interactive lifecycle is not yet a passing
result: the latest UI runner could not enable automation mode; another project's
remaining UI runner then prevented an isolated retry. Native index selection and
opening the Watching panel were reached in earlier attempts. These partial steps
do not close the Watching gate below.

- Native Watching start/pause/stop/launch-resume and moved/revoked-grant recovery.
- Actual system widget rendering; app-side publication does not establish extension rendering.
- Optional explicit access to `session_index.jsonl` outside the session folder.
- StoreRelease archive, Mac App Store distribution profiles/export and installer validation.
- Reconcile version 0.1.1 (2) with the existing Store draft 1.0; metadata and upload/processing.

No App Store upload, TestFlight distribution or review submission was performed.
See [Store preparation](mac-app-store-readiness.md) and [ROADMAP](../ROADMAP.md).
