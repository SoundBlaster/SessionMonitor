# CLI guide

[← SessionMonitor](../README.md) · [Install the CLI](getting-started.md#install-the-cli)

Run `codex-monitor --help` for the command list. Examples below assume it is on your `PATH`.

## Import and report

```sh
codex-monitor import ~/.codex/sessions
codex-monitor report
codex-monitor sessions --sort input
codex-monitor doctor
codex-monitor quota
codex-monitor export-session SESSION_ID > session-export.json
```

A directory import recursively discovers `.jsonl` and uncompressed numeric rotations such as
`.jsonl.1`. Hidden entries, `.jsonl.bak`, and compressed `.jsonl.gz` files are not selected.
Import `~/.codex/archived_sessions` separately if needed. Imports are incremental; their summary
counts only this run. An unchanged import can report zero records while the database still
contains your complete previously imported index.

Reports use an absolute half-open interval: `[since, until)`. Timestamps require an explicit
ISO 8601 offset. Timezone affects presentation metadata, not the absolute boundaries.

```sh
codex-monitor report --since 2026-10-01T00:00:00Z --until 2026-11-01T00:00:00Z
codex-monitor report --since 2026-10-01T00:00:00+03:00 --time-zone Europe/Moscow
codex-monitor report --json
codex-monitor doctor --json
codex-monitor quota --json
codex-monitor quota --summary --json
```

`quota` reads imported `event_msg/token_count.rate_limits` observations, not a provider API.
Remaining usage is derived from observed used percentage. Missing events mean unknown,
not zero usage. Reset, freshness, and coverage qualify the result; account-level usage is not
attributed to a session just because its log contains the observation.
See [quota ingestion](../reports/SM-308a-quota-snapshot-ingestion.md).

`quota --json` retains the complete raw snapshot report. For a smaller response, use
`quota --summary --json`: it emits `QuotaPresentationReport` schema version 1 with
`windows`, full-query `coverage`, and `accountCoverages`, without the `snapshots` array.
The text command uses the same summary. Equal-timestamp conflicts remain ambiguous;
the final reset change includes its original before/after evidence, even if newer
observations omit reset information.

The all-time, all-account summary reads a SQLite projection maintained atomically
with imports and account mapping. Time/account-filtered queries retain the raw
filter-before-deduplication rules and can cost more. If an older app or CLI writes
without refreshing the projection, the new reader uses raw observations rather
than serving stale values. The first open of an older database builds the projection
once; this migration is separate from steady-state query latency.

## Compact agent status

```sh
codex-monitor agent status --json
codex-monitor agent status --session SESSION_ID --lookback-hours 168 --json
```

`agent status` schema version 1 keeps its existing JSON contract. It reads only the
chosen session's canonical totals/timeline and the all-account quota summary;
it does not load every session or the complete quota history. Without `--session`,
it selects the session with the latest confirmed request in the lookback interval.
An unknown explicit ID returns no session block. Quota remains account-level,
including its original reset identity and current/stale/future/unknown freshness;
it is never allocated to the selected session. Status reads do not import or
evaluate alerts. Index revisions, canonical totals, and raw observation reports
are unchanged by projection maintenance.

## Account profiles

Map a homogeneous source root to an explicit local profile:

```sh
codex-monitor profiles map-root --root ~/.codex/account-work/sessions --id work --label Work
codex-monitor report --profile work
codex-monitor quota --profile work --json
codex-monitor report --unknown-or-mixed
codex-monitor export-session SESSION_ID --profile work > session-export.json
```

Do not assign a root containing multiple accounts to one profile. Attribution uses explicit
non-secret rollout metadata or your mapping, not credentials, cookies, `auth.json`, or prompt
content. Session ownership and account profiles are separate concepts. Unrestricted reports
are labeled All accounts; quota windows remain separated by account scope.

## Alerts

```sh
codex-monitor watch ~/.codex/sessions --alerts
codex-monitor alerts
codex-monitor alerts --status all --json
codex-monitor alerts evaluate --lookback-hours 6 --json
```

Watch with `--alerts` emits alert JSON lines after imports. Supported signals include session
anomalies, quota shifts and low remaining observations, data diagnostics, and Watch recovery.
Session findings cover repeated polling, expensive startup, cache drops, uncached-input spikes,
unusually large usage, and a session dominating the selected workload. The default evaluation
looks back six hours. Fresh quota observations warn at remaining usage ≤20% and escalate at
≤5%; stale observations retain unknown coverage. A supported usage-rate projection can also
warn when a window may run out before its reset (error if depletion is projected within 30 minutes).
Live rules can use a 14-day personal baseline for unusual input rate, repeated requests without
a human turn, and growing input. Insufficient history or unknown inputs suppress unsupported
conclusions. Baselines are refreshed periodically.

Alert state supports raise/escalate/update/resolve, deduplication, cooldown, severity ordering,
muted kinds, and notification rate limits. A persistent condition does not notify on every
refresh. Low cache hit alone is informational and does not prove wasted spending. The app
provides macOS notifications; the CLI provides structured output.

## Observable snapshots

```sh
codex-monitor snapshot --time-zone Europe/Moscow
codex-monitor snapshot --follow --time-zone Europe/Moscow
```

`snapshot` prints one JSON object; `--follow` prints the initial snapshot and later changes as
JSON lines. Both only read the index. They accept `--since`, `--until`, `--time-zone`, and
`--database`. UTC is the default presentation timezone.

Schema version 1 includes `query`, `report`, `coverage`, and `watermark`. `report --json`
retains its bare UsageReport shape for compatibility; use `snapshot` for the versioned envelope.
The watermark contains a database UUID, monotonic commit revision, and optional commit time.
It advances atomically with changed source snapshots, checkpoints, and diagnostics. Unchanged
imports do not advance it. Migrated databases begin at revision 0 with an unknown commit time.

The stream checks the marker once per second and recalculates the report only after a change,
including commits from another app/CLI process. Reads are transactional, intermediate commits
may be coalesced, and cancelling the consumer ends observation. Source timestamps are not
commit times. Direct SQL writes without a marker are outside the supported write API;
replacing the database file requires reopening the runtime.

## Database selection and recovery

The app and CLI share the [default index](getting-started.md#where-data-lives). Use
`--database PATH` or `SESSIONMONITOR_DATABASE` for an isolated index. Only one importer may
own a database at a time; readers can continue during imports. See [Watch ownership](watching.md).
After editing old log lines or restoring logs, force a rescan:

```sh
codex-monitor import ~/.codex/sessions --rescan
```

See [data and coverage](data-and-coverage.md) for append-only assumptions, deduplication,
partial records, and anonymized export boundaries.

## Session source size

`report --json`, `snapshot --json`, `sessions --json` and `inspect --json` expose an
optional `sourceStorage` per session:

```json
{"knownBytes": 1048576, "fileCount": 2, "unknownSizeFileCount": 0}
```

`knownBytes` is an integer byte count of the whole imported source logs owned by
that session in the selected account scope. When `unknownSizeFileCount` is positive,
it is a **lower bound**, not an exact total. Missing `sourceStorage` means unknown,
not zero. `lastModifiedAt`, when present, is the newest observed source modification
time, using the existing JSON date encoding; it is not a live filesystem check.
The text forms of `sessions` and `inspect` also show bytes (`unknown` or `>=` for
incomplete observations). Older JSON without this additive field still decodes.

The metric is independent of the selected request period: a one-day report for a
long-running session still describes its whole imported source files. It includes
numeric JSONL archives and unfinished tails in successfully imported files. Copies
count separately, hard links and resolved symlinks count once; descendants remain
separate sessions. It is neither bytes read during this import, SQLite/index size,
allocated disk usage, nor a promise of reclaimable space on APFS/cloud storage.

Values are persisted atomically with source checkpoints. Run `import`/Update to
observe changes or backfill an older index; unchanged files need no body reread.
Queries read SQLite and work even while sources are offline or removed. These are
last-import observations of known indexed files, **not** a complete disk inventory;
unimported, externally deleted or inaccessible files are not rediscovered by a report.
Hunter-backed storage management is a separate planned feature (SM-751).

## Using the same index as the Mac App Store app

In the Store app, connect the folder containing `usage.sqlite`. Under **Settings → Shared
Index → Copy CLI Command**, copy a command with the active database's absolute path:

```sh
codex-monitor report --database '/path/to/index/usage.sqlite'
```

Pass `--database` to other commands, too. The CLI keeps its existing default path and
`SESSIONMONITOR_DATABASE` override; the Store app's bookmark is not transferred to the
CLI. Changing the app's index folder takes effect after restart, so the copied command
always identifies the index that the app currently uses. Existing history is opened
in place, without an implicit copy. See [Store preparation](mac-app-store-readiness.md).
