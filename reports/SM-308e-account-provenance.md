# SM-308e — account profile provenance

## Outcome

This change adds an account scope to imported canonical usage and quota telemetry. It keeps
account provenance separate from session ownership, and never reads credentials. Explicit
`creator_account_id` / `creator_user_id` rollout metadata is retained as non-secret source evidence;
users can map a homogeneous source root to a local profile ID and display label.

Sources without identity remain isolated as unknown. If a mapped root contains more than one
explicit identity, or later imports introduce a conflicting identity, the root becomes mixed and
its sources are no longer attributed to that profile. Response and quota event/window dedup now
include account scope: mirror records within a mapped profile collapse, while matching IDs across
profiles remain separate. Account-scoped reports, activity, timelines, and quota queries support
`--profile ID`; `--unknown-or-mixed` selects unmapped and mixed sources. Unfiltered reports carry
an explicit `All accounts` scope.

## CLI

```sh
codex-monitor profiles map-root --root PATH --id work --label Work
codex-monitor profiles list
codex-monitor report --profile work
codex-monitor activity --profile work --since 2026-09-20T00:00:00Z
codex-monitor quota --unknown-or-mixed --json
```

Only map a root known to contain one account. A mixed root is reported as mixed rather than
arbitrarily assigned. Session metadata remains independent from account profile identity.

## Validation

- `swift test --filter AccountProfileTests` — 6 tests passed.
- `swift test` — 122 tests across 19 suites passed.
- `make check-core` — passed, including SwiftLint and CLI smoke checks.
- `make build-macos` — passed.
- `make lint-architecture test-architecture` — passed; strict FSD lint reported 0 errors and 0 warnings.
- `git diff --check` — passed.
- GitHub CI — pending for [PR #58](https://github.com/SoundBlaster/SessionMonitor/pull/58).

## Boundaries

SM-308e provides storage, import, query, and CLI account scope. It does not add profile selection
or per-profile quota rows to the GUI; that remains SM-308f. Usage totals remain canonical-only.
