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

- Actual permission revocation, unidentified source relocation (SM-757), and normal system menu bar navigation.
- Actual system widget rendering; app-side publication does not establish extension rendering.
- Optional explicit access to `session_index.jsonl` outside the session folder.
- StoreRelease archive, Mac App Store distribution profiles/export and installer validation.
- Reconcile version 0.1.1 (2) with the existing Store draft 1.0; metadata and upload/processing.

No App Store upload, TestFlight distribution or review submission was performed.
See [Store preparation](mac-app-store-readiness.md) and [ROADMAP](../ROADMAP.md).

## October 27 follow-up: folder recovery and installed widget

The new native folder-recovery scenario was compiled in development-signed StoreDebug;
`codesign --verify --deep --strict` passed. Both test attempts failed during XCTest
initialization with `Timed out while enabling automation mode`, before any test body.
The Mac reported `IOConsoleLocked = false`, Computer Use read normal app windows, and
no competing Xcode UI runner was present. A user-service kickstart was rejected by SIP;
no security setting was changed or bypassed. Therefore neither moved-folder nor
missing-folder recovery is native acceptance evidence yet.

A fresh targeted hosted run passed **24 tests** (3 XCTest + 21 Swift Testing):
`WatchLaunchSettingsTests`, `SavedFolderAccessTests`, `SharedIndexTests` and
`SandboxWatchFixtureTests`. Injected bookmark failures/reselection are unit evidence,
not a substitute for the native scenario. SwiftLint (306 files) and positive/negative
FSD architecture checks passed.

Read-only installed-widget diagnostics found:

- `/Applications/SessionMonitor.app` is GitHub version 0.1.1 (2), not a sandboxed
  Store host. Its nested widget has the expected WidgetKit extension point and sandbox.
- Both signatures passed deep/strict verification and contain
  `group.ru.egormerkushev.session-monitor` for team `P8T2366K8X`.
- PlugInKit's non-superseded record points to that installed extension. Other records
  exist for development builds; they were not removed or manually re-registered.
- The shared snapshot has schema 1, two usage periods and cache data. Its timestamp is
  October 25, 2026 at 14:31:47 UTC (17:31:47 Europe/Moscow); this proves neither current
  freshness nor rendering.
- Computer Use reached other existing Notification Center widget windows, but could
  not open Control Center (timeout) or interact with the widget window position
  (`windowNotFoundAtPosition`). No SessionMonitor gallery/desktop render was observed.

No app was installed/replaced, no user widget was added/removed, and no personal index,
shared snapshot, clipboard, permission or system widget cache was changed.

Local result bundles under the verified checkout build root on TB5:

- `sm706-recovery-tests/20261026T233938-32746FBF-5345-4D0F-A295-B03BAC93CD1B.xcresult` — initialization failure.
- `sm706-recovery-tests/20261026T234519-F8ED4F9C-3940-4C87-82A8-7E829288E81E.xcresult` — initialization failure.
- `sm706-recovery-unit-tests/20261026T235120-5C2E4564-D013-4061-B80A-C86977236489.xcresult` — 24 targeted tests passed.

Next: restore working XCTest automation and run the native recovery scenario, then
verify the actual system widget from a signed Store candidate. The optional title
index grant and Store packaging/ASC gates remain open.

## October 27 retry after enabling XCTest: native recovery passed

The owner enabled XCTest and requested another run. The initial attempt then reached
test bodies: Watching passed, while the first recovery click was interrupted by an
unrelated Screenshot editor window. The recovery-only retry followed both moved
bookmarks and resumed Watching, but exposed a separate accounting issue: with no
account identity, the renamed source received a new path-based Unknown/Mixed scope.
The report counted the old first response twice: **3 requests / 400 input**, rather
than **2 / 300**. This remains open as **SM-757**; no production accounting code was
changed to obtain a passing sandbox result.

The recovery fixture now declares `creator_account_id: sandbox-smoke-account`, making
its attribution explicit. With that fixture, the complete signed StoreDebug native
suite passed **2 tests, 0 failures, 104.517 seconds**:

- Recovery: 57.937 seconds. Real grants followed both same-volume folder moves after
  normal Quit/relaunch. Two requests remained two; Watching resumed.
- Removing only the original synthetic source produced an explicit error while the
  index remained readable. Selecting its replacement through the native picker
  restored Watching and imported the third request.
- Removing only the original synthetic index returned to the connection gate, without
  creating a replacement/fallback index. Native selection of the backed-up index
  restored the three-request history and Watching.
- The ordinary append/Pause/Resume/Quit/relaunch/Stop scenario passed again in 46.580 seconds.
- Teardown reset only the isolated suite, removed synthetic fixtures and closed the app.

Local passing evidence:
`sm706-recovery-tests/20261027T080749-5AE91FD1-BED8-46AF-801E-8F03528E2269.xcresult`.
The earlier failure/initialization receipts remain historical failure evidence.

The same production importer is exercised by a new focused regression checking two
attributed requests and input/output totals after moving the source directory.
The final fixture suite passed **2 Swift Testing tests**; SwiftLint (306 files) and
positive/negative FSD checks passed. Unit evidence:
`sm706-recovery-unit-tests/20261027T081011-5E4FB87C-453E-4816-A1DA-738A505ED08A.xcresult`.
The prior 24-test run is baseline; 23 unchanged cases were not repeated.

The native result covers **explicitly attributed** synthetic sources and missing
folders, not actual permission revocation, unidentified source-scope relocation or
system menu bar placement. Installed-widget diagnostics above remain read-only;
actual system rendering on a Store candidate and the Store packaging/ASC gates are
still open. Next: SM-757, then the remaining SM-706 gates.
