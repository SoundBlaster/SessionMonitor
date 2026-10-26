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

The automation in [PR #148](https://github.com/SoundBlaster/SessionMonitor/pull/148)
adds a [dedicated Watching XCUITest command](sandbox-watch-smoke.md). On the same
Xcode 27.1/macOS 27 development environment, the signed StoreDebug test passed:
**1 test, 0 failures, 53.025 seconds**, including teardown.

- Native index and source pickers created real sandbox grants.
- Initial import and append refreshed the chart from one request to two.
- Pause held at two; Resume imported the third request.
- Normal Quit, append while closed and relaunch restored grants/Watching and the fourth request.
- Stop held at four after appending a fifth request (bounded two-second observation).
- Teardown cleared only the run's unique preference suite, removed its synthetic data,
  and closed the test app. Personal sessions/preferences and widget data were not selected.

The production `AppMenuHost` controls run in a Debug-only test pane; this proves
controller/runtime/grant behavior, **not opening or placement of the system menu bar item**.
Picker suggestions are Debug-only and still require native confirmation. No clipboard
or keyboard-layout changes are needed. A separate four-test unit run passed preference
isolation, picker-suggestion guards and fixture accounting through the real importer.
The earlier 35-test baseline predates the final harness changes; 33 of those tests
were unchanged, while the preference tests were rerun and expanded.

The final signed StoreRelease app/widget build also passed, as did SwiftLint
(305 files, zero violations) and positive/negative FSD architecture checks. Existing
cache-chart compiler warnings remain outside this automation change.

Local evidence, outside Git on the verified build volume:

- `sm706-watch-tests/20261026T192255-C8716CD6-7D67-4CFF-9FBA-DAF2C2FFB8B3.xcresult`
- `sm706-unit-tests/20261026T191334-43B8CCC3-316F-45A7-B830-2FAED2EA4BB7.xcresult`

Earlier locked-desktop/automation-service failures are not passing evidence. The Make
command now rejects a locked console before starting XCTest; the successful run above
used an unlocked desktop without competing UI tests.

- Moved/revoked-grant recovery and normal system menu bar navigation.
- Actual system widget rendering; app-side publication does not establish extension rendering.
- Optional explicit access to `session_index.jsonl` outside the session folder.
- StoreRelease archive, Mac App Store distribution profiles/export and installer validation.
- Reconcile version 0.1.1 (2) with the existing Store draft 1.0; metadata and upload/processing.

No App Store upload, TestFlight distribution or review submission was performed.
See [Store preparation](mac-app-store-readiness.md) and [ROADMAP](../ROADMAP.md).
