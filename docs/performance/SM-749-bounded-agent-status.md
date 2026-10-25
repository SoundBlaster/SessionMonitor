# SM-749: compact agent status without full quota-history decoding

Measured October 25, 2026, on the same private corpus as the
[SM-746 baseline](SM-746-cli-baseline.md). The default agent query fell from a
7.145-second median / 724.9 MiB peak RSS to **0.180 seconds / 31.9 MiB**.
An explicit session with a seven-day lookback took **0.680 seconds / 52.3 MiB**,
down from 7.385 seconds / 758.8 MiB. These are local measurements, not a universal SLA.

## Implementation and contract

- `agent status` reads only the selected session's canonical totals and timeline.
  Session selection, totals and watermark share a SQLite read transaction; unrelated
  sessions, provenance, whole-session spans and source storage are not loaded.
- An atomic SQLite projection indexes deduplicated quota event identities, presentation
  series, observation ordering, resets and coverage metadata. Payloads remain in the
  original telemetry table. Imports refresh changed event identities, including mirrors;
  mapping and profile-label changes invalidate affected observations in the same transaction.
  Appending to an unchanged account scope does not rebuild its older history.
- Reads retain every latest-timestamp tie plus the two witnesses of the final reset
  transition per series. Missing resets do not hide an older transition. Account, limit
  and slot identities stay distinct; reset and window duration remain observation evidence.
  The shared `QuotaPresentationSeriesKey` uses the same Unicode equivalence as Swift's
  policy grouping. SpecificationCore still makes the presentation decisions.
- Coverage aggregates the entire query, including historical partial, unsupported and
  windowless snapshots. It is not inferred from the reduced witness set. The corpus has
  124,227 deduplicated snapshots and 98 presentation series; only 167 snapshots are decoded
  for their current presentation. All latest ties remain uncapped.
- `agent status` keeps schema version 1. `quota --json` keeps the complete raw report.
  The explicit `quota --summary --json` contract emits `QuotaPresentationReport` version 1,
  with windows, reset evidence and overall/account coverage, without raw snapshots.
- Time/account-filtered summaries retain filter-before-deduplication semantics through
  the raw query. A pending invalidation from an older writer also uses raw data instead
  of returning a stale projection. The latency budgets below apply to a current,
  all-time/all-account projection, as used by `agent status`.

There is no fixed history-tail limit. `LIMIT 1` selects a precisely ordered first/last
observation; maintenance/parameter batches are fully drained before completion. None
of these operations attributes account-level quota consumption to a session or changes
canonical accounting, alert evaluation or the query watermark.

## Measurement conditions

Release arm64 CLI, source `7f894443ad5caab4d0c5ac5e15ac5ffc889e7c42`, reporting version
0.1.1. SHA-256: `e79ac7648ef29e3697102ac6665a4b5b7c372a028be2b0ce190311472eefa14e`.
Apple M4 Pro, 12 cores, 24 GiB RAM, macOS 27. Build output, copied indexes and private
results stayed on the verified TB5 SSD; installed applications and source logs were untouched.

The original 603,320,320-byte SQLite backup was copied again, including its committed WAL:
85,163 source usage records, 555,026 timeline rows and 319,010 raw quota rows.
The fixed query window remained `[2026-10-17T00:00:00Z, 2026-10-24T11:00:00Z)` in UTC,
with the same explicit session chosen by the baseline harness. Agent queries use the
execution clock for their 24/168-hour lookback, so their recent data can differ from the
earlier run. Fixed-clock parity was checked separately.

The original 13 cases each ran in 11 fresh processes: first call plus ten repeats.
The added quota-summary case used the same migrated copy and another 11 fresh processes.
`/usr/bin/time -l` reports wall time at 0.01-second resolution and RSS in bytes.
p95 is nearest rank over ten samples, therefore the largest repeat; it does not establish
a production tail SLA. OS caches and the desktop workload were not controlled.

The comparison baseline is the published 0.1.1 binary at `ccfb96f`, while this branch also
includes subsequent `main` changes such as source-storage reporting. This is a release
comparison, not an isolated ablation of every intervening change. The table retains
slower results as well as improvements.

| Query | SM-746 median, s | New median, s | New p95, s | Peak RSS, MiB | Output, KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| report, all time | 0.510 | 0.655 | 0.710 | 41.7 | 202.8 |
| report, window | 0.485 | 0.620 | 0.660 | 41.1 | 31.5 |
| sessions, window | 0.500 | 0.625 | 0.640 | 41.4 | 37.5 |
| snapshot, window | 0.490 | 0.615 | 0.640 | 41.2 | 49.5 |
| activity, one session/window | 0.200 | 0.220 | 0.240 | 33.1 | 70.1 |
| raw quota, window | 0.860 | 0.620 | 0.630 | 163.5 | 13,898.0 |
| raw quota, all time | 7.390 | 5.375 | 5.460 | 1,153.2 | 109,200.1 |
| **agent status, latest/24h** | **7.145** | **0.180** | **0.200** | **31.9** | **12.7** |
| **agent status, explicit/168h** | **7.385** | **0.680** | **0.690** | **52.3** | **13.2** |
| inspect, one session/window | 0.930 | 1.105 | 1.140 | 63.5 | 335.9 |
| doctor, window | 10.780 | 12.810 | 13.190 | 199.1 | 14,603.1 |
| alerts list | <0.010 | 0.010 | 0.010 | 10.1 | <0.1 |
| **quota summary, all time** | — | **0.050** | **0.050** | **23.0** | **121.8** |

The database watermark remained unchanged. `doctor` still takes 12.81 seconds on this
corpus; broader contract/performance work remains in SM-746. Raw quota JSON intentionally
remains a complete, relatively large inspection response.

## Local acceptance budgets and upgrade cost

These are measured regression targets for this corpus/hardware, not timed unit-test assertions:

| Workload | Median wall budget | Peak RSS budget | Output budget | Result |
| --- | ---: | ---: | ---: | --- |
| latest session, default 24h | 0.30 s | 48 MiB | 16 KiB | Passed |
| selected large session, 168h | 1.00 s | 64 MiB | 16 KiB | Passed |
| all-account quota summary | 0.10 s | 32 MiB | 256 KiB | Passed |

The first `report-all` process, including the one-time projection migration, took **7.88 s**
and **117.6 MiB** peak RSS. This is separate from steady-state query latency and is not a
standalone migration timer. Migration backfills all identities in bounded batches.
The index grew from 603,320,320 to 915,329,024 bytes, an additional **297.6 MiB** for
derived metadata and indexes. Existing observations remain intact; source logs are not copied.
Very many series or conflicting latest-timestamp ties can increase the summary size.

## Verification and reproduction

`make check-core` passed: 277 Swift Testing tests, existing XCTest tests, SwiftLint and
CLI process smokes. FSD lint and its negative boundary fixture passed. Regression coverage
includes long history, every latest tie, interleaved multi-slot resets, Unicode/name/ID
series, partial/windowless/unsupported coverage, account remapping/mixed roots, mirror
removal, append/idempotency, upgrade backfill and transaction rollback. Session-scoped
totals match the canonical report, including unknown cache and conflicting responses.

A temporary local Swift Testing probe compared complete quota presentation and agent
reports at a fixed clock on the full copied corpus. All fields matched for 24h and 168h
lookbacks. The probe was removed from the repository; its output and personal data remain
private. This verifies data equivalence, not UI behavior or App Store acceptance.

```sh
python3 scripts/performance/cli_queries.py \
  --binary /path/to/release/codex-monitor \
  --source-revision BUILD_SOURCE_SHA \
  --database /private/path/to/unchanged-baseline.sqlite \
  --output /private/path/to/new-results \
  --since 2026-10-17T00:00:00Z --until 2026-10-24T11:00:00Z \
  --repetitions 10 --timeout 90
```

The harness now includes the added quota-summary case. Its JSON results and database copy
contain private metadata and must not be committed. Prepare Mac App Store readiness under
SM-706 after review/merge; publication of broader performance claims remains SM-752.
