# SM-409–SM-412 — Cumulative validation

Validated source revision: `a18d414`, the fourth layer of the native GitHub stack.
Later commits update only delivery/validation documentation. All regression evidence
below was executed on this cumulative source tree; isolated full suites for each
intermediate layer are not claimed.

## Builds

Only `xcode-tools` MCP was used to compile: the existing MonitorMac workspace tab,
My Mac destination, discovered schemes `SessionMonitorTests` (build-for-testing)
and `codex-monitor` (CLI). Both final builds succeeded. The original `MonitorMac`
scheme was restored afterwards; the app was not launched and no app windows added.

## Tests

Native MCP RunSomeTests timed out twice after 300 seconds, including a retry with
exact discovered test IDs. Headless package destination resolution also timed out.
The actual runtime cause was not established; these attempts are not passing evidence.
Disk exhaustion separately interrupted builds before cleanup of this project's caches.

The successfully MCP-built `SessionMonitorTests.xctest` bundle was then executed
with the Xcode `xctest` runner directly, with no compiler or rebuild:

```sh
rtk proxy env -i PATH=/usr/bin:/bin \
  /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Xcode/Agents/xctest \
  /Users/egor/Library/Developer/Xcode/DerivedData/MonitorMac-gyqedzvdndkxhgenwfksqnrobssn/Build/Products/Debug/SessionMonitorTests.xctest
```

Exit 0: **148 Swift Testing + 7 XCTest tests passed** (155 total). All new cases
passed, including four backfill parameter combinations and both mapped/unmapped
root membership combinations. Existing incremental import, ownership, migration,
quota, diagnostics, activity, watch and cache-rate suites also passed.

## CLI and quality gates

The following harnesses ran against the MCP-built Debug `codex-monitor` binary:

- `scripts/tests/watch-cli-smoke.py`: pause/resume, accounting, signals, blocked stdout.
- `scripts/tests/snapshot-cli-smoke.py`: external commits, migration, leases, kill recovery.
- `scripts/tests/quota-cli-smoke.py`: production sharp-shift detection and evidence boundaries.
- `scripts/tests/performance-smoke.py`: independent synthetic copy, native metrics,
  audit parity, append/full parity and delta-only reads. Its initial free-space guard
  failed; after freeing project build intermediates it passed without bypassing the guard.

`make lint-core`, `make lint-architecture`, `make test-architecture` and
`git diff --check` passed. `make lint-ci ACTIONLINT=.build/ci-tools/bin/actionlint`
passed using the repository-pinned actionlint 1.7.12 release/checksum; workflow YAML
and shell syntax were validated. The deliberate invalid FSD fixture was correctly rejected.
This covers the core quality scope equivalent to `make check-core` without invoking
shell compilation. No GUI source changed; full app/UI tests were not rerun.

Production root usage/event SQL also passed a separate in-memory SQLite probe.
No user SQLite databases or raw archive sources were changed. Build intermediates
and index caches were removed only from this project's DerivedData to relieve disk
exhaustion; resulting test/CLI binaries and dependency checkouts were retained.

## Delivery

Native stack: #74 → #75 → #77 → #78. CI pull_request base filtering was removed
in #75 so all layers run the existing gates. GitHub CI, review and merge remain
separate gates; CI is not actively polled. All tasks remain unchecked until delivery.
