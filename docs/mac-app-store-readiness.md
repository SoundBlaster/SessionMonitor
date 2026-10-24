# Mac App Store preparation

[← SessionMonitor](../README.md) · [Release workflows](releases.md)

Read-only assessment on October 24, 2026. The owner's sequence is CLI performance
verification (SM-746), then Mac App Store preparation (SM-706). This document is a
preparation plan, not evidence of a submitted or approved build.

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
- The cached Apple web session is expired. API access works, but App Privacy publication
  and agreements were not established by the deep check. Renew the web session when that
  stage is reached; do not create another app or replace API credentials merely for this warning.

No remote metadata, signing, upload, submission, or agreement state was changed.

## Engineering work before an App Store candidate

1. **Distribution configuration and sandbox access.** The app target currently sets
   `ENABLE_APP_SANDBOX: NO` in [project.yml](../Apps/MonitorMac/project.yml), while the
   widget is sandboxed. Apple requires App Sandbox for App Store distribution.
   Establish a separate App Store configuration so the Developer ID release remains usable.
   Define the minimum user-selected-file and bookmark entitlements for import/watch and export.
2. **Persistent folder access.** [WatchLaunchSettings](../Apps/MonitorMac/Sources/shared/lib/WatchLaunchSettings.swift)
   currently persists a plain path. Add security-scoped bookmark persistence/restoration and
   balanced access lifetime for import, Update, Watching, and launch-resume. Test revoked/stale
   bookmarks and moved/missing folders. Optional `session_index.jsonl` can be outside the chosen
   folder: obtain explicit access or show unavailable titles, without silently broadening access.
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
   Review [release-local.sh](../scripts/release-local.sh) for current toolchain flags and
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
