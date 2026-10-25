# Mac App Store preparation

[← SessionMonitor](../README.md) · [Release workflows](releases.md)

Updated October 25, 2026. CLI performance work SM-749 is delivered in PR #145;
the README measurements are delivered in PR #146. SM-706 now implements the first
engineering prerequisite: a separate sandbox configuration and persisted folder grants.
This document records preparation, not a submitted or approved build.

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
only when that operation acquired it. Successful imports remain visible if saving
the grant fails, with a separate explanation rather than claiming the import failed.
Hosted unit tests use a temporary index and disable automatic Watching/widget publication.

Regression tests cover saved-path compatibility outside the Store, missing/invalid/stale
bookmarks, moved folders, failed renewal/creation, Update after lost access, and watch
launch/selection failures. Injected bookmark operations test policy and lifetime handling;
they do **not** demonstrate a real macOS grant or App Store acceptance.

Local verification on October 25 used Xcode 27.1 (`27A9275`) with build outputs and
package caches on the verified external build volume. `StoreDebug` and `StoreRelease`
app/widget compile passed without signing; both StoreRelease executables contain
arm64 and x86_64. The final ordinary Debug targeted run passed **42 XCTest tests and
12 Swift Testing tests**, including the cross-distribution selection regression.
A separate temporary SwiftPM harness compiled unchanged production Foundation sources
and passed eight bookmark-policy tests. SwiftLint and both positive/negative FSD gates
passed. Dependency pins are unchanged.

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
claimed. Repeat this check with the actual signed Store candidate after the index contract
and profiles are resolved.

## Engineering work before an App Store candidate

1. **Signed sandbox acceptance.** Build `MonitorMacStore` and exercise the actual system
   picker, import, export, Update, Watching, quit/relaunch, permission loss, and a moved folder.
   Verify the picker's first-run default against the real Codex location as well: sandbox
   home-directory resolution and pre-grant file-existence checks need an acceptance witness.
   Local inspection found an App Store profile for the app and Developer ID profiles for
   app/widget, but no local App Store/development profile for the widget. Resolve that before
   treating a signed Store candidate as ready. An unsigned successful build only proves compilation.
2. **Optional title index access.** `session_index.jsonl` can be outside the chosen folder:
   obtain explicit access or show unavailable titles, without silently broadening access.
3. **Index ownership and app/CLI parity.** The default index uses Application Support in
   [SessionMonitor.swift](../Sources/MonitorRuntime/SessionMonitor.swift). Sandbox containment
   changes path resolution. Decide how the app and an agent's external CLI access the same
   committed index before changing storage: an explicitly supported shared location or a
   read-only service contract needs verification. Preserve existing history/settings and
   the widget's aggregate-only App Group snapshot; do not promise transparent migration yet.
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
