# Mac App Store preparation

[← SessionMonitor](../README.md) · [Release workflows](releases.md)

Updated October 26, 2026. CLI performance work SM-749 is delivered in PR #145;
the README measurements are delivered in PR #146. SM-706 now implements the first
engineering prerequisites: a separate sandbox configuration, persisted folder grants,
and an explicit shared app/CLI index connection.
This document records preparation, not a submitted or approved build.
The engineering foundation is delivered in [PR #147](https://github.com/SoundBlaster/SessionMonitor/pull/147),
squash `65fa957`. A signed StoreDebug archive and the first native sandbox checks passed
on October 26; see the [bounded acceptance report](sandbox-acceptance-2026-10-26.md).
The remaining acceptance/release gates are listed below.
Watching also has a dedicated [local signed UI smoke command](sandbox-watch-smoke.md);
its interactive result is tracked separately from ordinary CI and the manual baseline.

## Current App Store Connect state

- Existing app: **Agent Session Monitor**, ID `6812366729`.
- Bundle ID: `ru.egormerkushev.session-monitor`; primary locale: `en-US`.
- macOS version **1.0**, ID `0788d563-cff6-479b-9a02-f5fa327b619e`, is in
  `PREPARE_FOR_SUBMISSION`. No macOS builds were returned by the build lookup.
- `asc validate --app 6812366729 --version-id 0788d563-cff6-479b-9a02-f5fa327b619e
  --platform MAC_OS --deep --output json` returned **34 errors and 3 warnings**.
  These include 24 unanswered age-rating fields, rather than 34 independent engineering defects.
- Missing listing/review setup includes description, keywords, support URL, review contact,
  primary category, content-rights declaration, attached build, availability, screenshots,
  and copyright. Subtitle and privacy-policy URL are warnings.
- The October 24 check found the cached Apple web session expired. API access still works
  on October 25, with the existing Keychain profile. App Privacy publication
  and agreements were not established by the deep check. Renew the web session when that
  stage is reached; do not create another app or replace API credentials merely for this warning.

The October 25 read-only checks confirm the same app, draft version, no macOS builds,
and **34 errors / 3 warnings**. No remote metadata, signing, upload, submission, or
agreement state was changed.

## Implemented engineering foundation

`MonitorMacStore` uses `StoreDebug` to run and `StoreRelease` to archive. The app's
[Store entitlements](../Apps/MonitorMac/Config/Store.entitlements) enable App Sandbox,
the existing App Group, user-selected read/write access (including JSON export), and
app-scoped bookmarks. The existing `Debug` and `Release` configurations keep their
previous signing and file-access behavior. Unit tests remain on `MonitorMac`; they
are not a substitute for a signed Store build's acceptance run.

[SavedFolderAccess](../Apps/MonitorMac/Sources/shared/lib/SavedFolderAccess.swift)
persists **read-only security-scoped bookmarks** for selected session folders in
Store builds. Import/Update and Watching use the resolved URL, not a reconstructed
path. Stale bookmarks are renewed while access is active; failed restoration asks
the person to choose the folder again. A legacy path alone never creates a new grant.
Failed bookmark creation preserves the previously saved folder and bookmark.

Import retains access through the complete operation, including stopping an active
watch. Watching retains its own access until stop/failure/shutdown. Access is released
for explicit acquisitions; panel grants are released separately after the selected operation. Successful imports remain visible if saving
the grant fails, with a separate explanation rather than claiming the import failed.
Hosted unit tests use a temporary index and disable automatic Watching/widget publication.

Regression tests cover saved-path compatibility outside the Store, missing/invalid/stale
bookmarks, moved folders, failed renewal/creation, Update after lost access, and watch
launch/selection failures. Injected bookmark operations test policy and lifetime handling;
they do **not** demonstrate a real macOS grant or App Store acceptance.

Local verification on October 25 used Xcode 27.1 (`27A9275`) with build outputs and
package caches on the verified external build volume. The current Debug targeted run
passed **23 XCTest tests and 21 Swift Testing tests**, including shared-index integration,
grant ownership and synthetic light/dark UI snapshots inspected after rendering.
`make check-core` passed **277 core tests**, CLI process smoke checks and the synthetic
performance harness (audit and append/full-rebuild parity). Strict SwiftLint passed on
300 files, positive/negative FSD gates passed, and dependency pins are unchanged.
The CI retry-watch test now waits for its recovery event with a whole-test time limit,
instead of imposing a three-second polling deadline.

Earlier in this PR, unsigned `StoreDebug` and `StoreRelease` app/widget builds passed;
both StoreRelease executables contained arm64 and x86_64. The current shared-index
StoreRelease app/widget build also passed unsigned; both executables contain arm64/x86_64. A temporary SwiftPM
harness from the first stage passed eight bookmark-policy tests; this is baseline evidence.

The Xcode-tools attempt discovered the intended `MonitorMac` scheme, My Mac destination,
and tests, but was stopped by the changed `SpecificationCoreMacros` trust fingerprint.
Console validation used the owner's existing per-command `-skipMacroValidation` approval.
Local ad-hoc hosted tests cleared App Group entitlements for the test build only after
Xcode required provisioning profiles; this does not validate Store signing or App Groups.
The optional full GUI unit run was interrupted while an existing timeline performance
test was inside XCTest/CoreSymbolication. That attempt is not reported as a successful
full suite or an assertion failure; the final affected suites were rerun successfully.

A separate helper signed with the installed Apple Development identity attempted a real
sandbox folder-picker/bookmark check using only a synthetic file. Computer Use could not
attach to its picker. The helper was stopped; no successful real-grant/relaunch result is
claimed for that earlier helper attempt. The October 26 checks now exercised the actual
signed StoreDebug app and verified index/source bookmark recovery, Import/Update/export
and app-side App Group publication; remaining acceptance gates are listed below.

## Shared index connection in Store builds

On first launch, choose **Connect Your Session Index → Choose Index Folder**. Select the
folder containing the existing `usage.sqlite`, normally
`~/Library/Application Support/SessionMonitor`. The app opens the database **in place**;
it does not copy history or silently create a separate container index. Selecting an
empty folder explicitly creates a new index there. Session source folders are chosen
separately for import and Watching.

The Store app stores a **read/write security-scoped bookmark** for the index folder,
including SQLite WAL and lock files. It retains access for the lifetime of the opened
runtime. Missing or revoked access returns to the connection screen; it never falls
back to an empty private index. A bookmark or initial database-open failure leaves
previous saved settings unchanged.

In **Settings → Shared Index**, **Copy CLI Command** produces, for example:

```sh
codex-monitor report --database '/Users/you/Library/Application Support/SessionMonitor/usage.sqlite'
```

Use the same `--database` option with other CLI commands. The CLI's existing default
and `SESSIONMONITOR_DATABASE` override remain unchanged. A GUI bookmark does not grant
permission to the external CLI; that process needs its own normal filesystem access.
Widgets continue to receive only the aggregate App Group snapshot, not the index.

**Change Folder** saves the next selection and applies it after restart. Reports,
Watching, and the copied CLI command keep using the currently open index until then.
The pending path is shown explicitly. Cancelling the picker leaves the connection as is.

Open/save panel grants and explicitly started grants have separate balanced lifetimes.
The sessions picker suggests the login user's current-year Codex folder without trying
to prove external-folder access before the system picker grants it.

Regression tests open a populated database through a separate core connection and the
Store loader, compare canonical reports, profiles and database watermark, then verify
that an unchanged source still uses its incremental checkpoint. Additional tests cover
first-launch refusal to create a fallback, revoked access/reselection, failed bookmark
and database opening, pending restart, shell quoting, and implicit/explicit grant balance.
These injected tests and synthetic UI previews do not establish signed sandbox acceptance.

## Engineering work before an App Store candidate

1. **Complete signed sandbox acceptance.** The October 26 StoreDebug check passed real
   Open/Save Panels, shared index, GUI/CLI updates, import/export and bookmark restoration
   after full quit/relaunch. Development signing and app-side App Group publication work.
   Native Watching start/append/Pause/Resume/quit/relaunch/Stop passed in #148.
   On October 27, native moved/missing-folder recovery passed for an explicitly
   attributed synthetic account (2 native tests, zero failures). Actual permission
   TCC/bookmark revocation, picker first-run defaults and system widget rendering remain open.
   On October 28, native POSIX-denial recovery passed for both source and index: 1 test,
   zero failures, 55.551 seconds. History survives, permission errors remain explicit, and
   Stop/reselection restores Watching; an inaccessible index never opens a fallback database.
   This is filesystem-permission evidence, not a TCC reset or bookmark revocation.
   Unidentified source relocation exposed SM-757, delivered separately in PR #151; see the
   [dated evidence](sandbox-acceptance-2026-10-26.md). This does not establish App Store
   distribution-profile suitability or TestFlight/App Store behavior.
2. **Optional title index access.** `session_index.jsonl` can be outside the chosen folder:
   obtain explicit access or show unavailable titles, without silently broadening access.
3. **Shared index acceptance.** The explicit folder contract above is implemented in #147.
   The signed StoreDebug app and external CLI passed the synthetic existing-index and
   quit/relaunch checks. Moved/missing-folder recovery passed with explicit synthetic attribution;
   actual TCC/bookmark revocation remains open. Unknown source relocation (SM-757) is delivered
   in PR #151 (`244ca7f`); native index/source POSIX-denial recovery also passed on October 28. Existing history is
   opened in place; no automatic relocation or container-to-external migration is claimed.
4. **App Store archive/export.** Verify app/widget sandbox entitlements, App Group profiles,
   App Store distribution identities, installer signature, and package validation. Reconcile
   the existing Store draft `1.0` with GitHub/app version `0.1.1` and choose the next build
   number before archiving. Developer ID notarization and the GitHub DMG are separate evidence.
   Wire `StoreRelease` into [release-local.sh](../scripts/release-local.sh), which still
   defaults to the original Release configuration. Review its current toolchain flags and
   external build/cache routing before running it; its historical successful export is not
   proof that today's candidate is ready.

Apple references: [App Sandbox requirement](https://developer.apple.com/documentation/security/protecting-user-data-with-app-sandbox),
[user-selected files and persistent bookmarks](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).

## Store preparation and acceptance

Prepare English metadata, public support/privacy URLs, real screenshots, category,
review instructions/contact, age rating, content rights, and availability in the existing app.
Review privacy declarations against actual local processing and optional exports/hooks.
Build encryption declarations are checked once an actual build exists.

Before review submission, verify a sandboxed candidate through the intended App Store/TestFlight
route: first import, incremental Update, Watching, quit/relaunch and resume, old-data migration,
agent CLI access, app/widget parity, and system widgets. Keep CLI latency/output-size findings
visible; a successful archive alone does not establish these behaviors.

Re-run the canonical `asc validate` gate on the selected version with its processed build attached.
Submission is a separate, explicitly authorized step after these results are reviewable.
