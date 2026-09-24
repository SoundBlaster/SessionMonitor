# SM-308f — multi-account UI and quota presentation

## Pull request

[PR #60](https://github.com/SoundBlaster/SessionMonitor/pull/60) — open; local validation passed, GitHub checks remain pending/unverified.

## Outcome

This change adds one persisted account scope shared by Session Explorer and the menu bar: `All accounts`, a mapped profile, or `Unknown/Mixed`. The existing `UsageQuery.accountScope` remains the report filter. Profile roots sharing an ID collapse into one catalog option; all-mixed profiles remain visible but unavailable, and a profile that becomes mixed while selected stays selected with an explanation and a direct switch to `Unknown/Mixed`. Invalid persisted values restore to `All accounts`.

The Session Explorer sidebar cache-hit chart now uses the same account scope as the session report. All-account activity keeps cross-account session-ID aggregation and labels the scope explicitly. Quota is presented in separate profile groups plus `Unknown/Mixed`; values are never combined across profiles. Unknown scopes remain separate by their privacy-safe scope identifiers and display scope state without exposing account/model identity. Per-scope coverage includes partial, unsupported, and no-window snapshots while the existing aggregate coverage field remains available and legacy serialized reports still decode.

## Changes

- Added persisted shared account selection, runtime profile catalog refresh, profile deduplication, unavailable-profile state, and an accessible vertically arranged selector.
- Connected Session Explorer report/list/sidebar chart and menu bar summary to the shared selection.
- Added account-scoped quota coverage and grouped quota rows; retained freshness and reset-discontinuity presentation within each quota group.
- Added regression coverage for persistence/restoration, duplicate profile roots, all-mixed selected profiles, empty catalogs, account-filtered cache widget observations, equal quota events across profiles, per-scope partial/unsupported/no-window coverage, and old Codable payload compatibility.
- Updated `ROADMAP.md` to record SM-308f in progress and added this report.

## Validation

- [x] Relevant local checks passed; commands and results are listed below.
- [ ] Required GitHub check `CI` passed for the current PR revision.
- [x] ROADMAP status and evidence are updated; incomplete work remains unchecked.
- [ ] User-facing documentation reflects changed behavior or workflow.

- `make check SWIFTLINT=/opt/homebrew/bin/swiftlint FSD=/opt/homebrew/bin/fsd-ios XCODEGEN=/opt/homebrew/bin/xcodegen XCODEBUILD_FLAGS=-skipMacroValidation` — passed; CLI, performance smoke, 126 core tests, and 102 macOS tests.
- SwiftLint strict — passed with 0 violations; FSD architecture lint and boundary checks passed as part of `make check`.
- `git diff --check` — passed after the final source and documentation edits.
- Fresh Debug app launch — light appearance; accessibility tree confirms the selected account scope in the window title and sidebar, and the cache widget remains visible.
- The current local database has no assigned account profiles, so profile-specific visual interaction could not be inspected against real profiles. Dark appearance was not manually inspected; fixture and GUI tests cover the relevant data states.

## Boundaries and follow-ups

Canonical accounting and public usage totals are unchanged. Profile creation and source assignment remain CLI operations. Account identity and model identity are not added to UI quota labels. CI is intentionally not polled after PR creation per project instructions; its status is left unchecked here.
