# SM-746: Release CLI query baseline

The compact agent path has since been optimized in SM-749. See the
[repeat measurements and compatibility checks](SM-749-bounded-agent-status.md);
this document preserves the original baseline.

Measured October 24, 2026. The compact agent status is the main performance issue:
**7.145–7.385 s median and 724.9–758.8 MiB peak RSS**, despite a response of about 13.2 KiB.
Ordinary reports, session lists and snapshots take about 0.5 s on the same index.
This is a baseline and diagnosis, not an optimization result or a GUI responsiveness test.

## Scope and method

- Published universal CLI **0.1.1**, executed natively on arm64, source
  `ccfb96f4b59549643933ef49ec02187ed3559564`.
- Binary SHA-256: `4defa2bd129bf3b02d7f776c612fd5ae8994fac1f18a6ef6d4bdd4fe6149ac41`.
- Apple M4 Pro, 12 physical/logical cores, 24 GiB RAM; macOS 27.0.
- Consistent SQLite backup: **603,320,320 bytes**, containing 85,163 source usage rows,
  555,026 timeline rows and 319,010 quota observations. Row counts are storage counts,
  not a claim that all source rows are distinct canonical requests.
- Fixed query period: `[2026-10-17T00:00:00Z, 2026-10-24T11:00:00Z)`; UTC presentation,
  All accounts. Session cases use the session with most stored request rows in that period.
  Agent status uses its real execution-time 24h/168h lookback; it has no fixed `--until` option.
- **13 cases, one first invocation and 10 repeats each: 143 measured processes.** Every
  sample starts a fresh CLI process. First invocation is separate from the repeated summary.
- OS/disk caches are uncontrolled, and backup/pilot reads preceded the measurements.
  These are **not cold-boot or cold-disk measurements**, nor measurements of a persistent warm process.
- Existing `measure.py` uses Apple `time -l`: child elapsed/CPU resolution is 0.01 s,
  peak RSS is bytes. Table times below 0.01 s are below resolution, not instantaneous.
  Nearest-rank p95 over ten repeats is descriptive (the maximum), not an established tail SLA.
- Runs were serial on a normal desktop. The harness started no GUI builds or competing benchmarks;
  unrelated desktop activity was not controlled.
  Timing includes process startup, database reads and serialization to a file on the build volume;
  it excludes a receiving agent's parsing/tokenization and the harness's later JSON validation.
- Original user logs/index were not imported or modified. CLI commands used a private copied index,
  and its query watermark stayed unchanged. Raw JSON, IDs, paths and sample trace stay outside Git.

## Results

Times are seconds; memory is maximum RSS across repeats, output is maximum stdout size.
`window` means the fixed period above; `quota-all` intentionally requests raw all-time observations.

| Case | First | Repeat median | Repeat p95 | RSS MiB | Output KiB |
| --- | ---: | ---: | ---: | ---: | ---: |
| `version` | <0.01 | <0.01 | <0.01 | 7.6 | 0.0 |
| `report-all` | 0.510 | 0.510 | 0.530 | 41.2 | 202.8 |
| `report-window` | 0.460 | 0.485 | 0.500 | 40.7 | 31.5 |
| `sessions-window` | 0.490 | 0.500 | 0.510 | 41.0 | 37.5 |
| `snapshot-window` | 0.490 | 0.490 | 0.530 | 40.9 | 49.5 |
| `activity-session-window` | 0.190 | 0.200 | 0.210 | 33.0 | 70.1 |
| `quota-window` | 0.890 | 0.860 | 0.890 | 165.1 | 13898.0 |
| `quota-all` | 7.420 | 7.390 | 7.690 | 1172.3 | 109200.1 |
| `agent-latest-24h` | 7.130 | 7.145 | 7.230 | 724.9 | 13.2 |
| `agent-session-168h` | 7.440 | 7.385 | 7.490 | 758.8 | 13.2 |
| `inspect-session-window` | 0.930 | 0.930 | 0.960 | 63.1 | 335.9 |
| `doctor-window` | 10.810 | 10.780 | 10.850 | 203.3 | 14603.1 |
| `alerts-list` | <0.01 | <0.01 | <0.01 | 10.0 | 0.0 |

The all-time quota command emits about **106.6 MiB of JSON**. A raw observation export is
not an appropriate routine input for an agent; this does not make the raw-data API incorrect.
The week-scoped `doctor` emits about 14.3 MiB and takes 10.78 s median; reserve comprehensive
diagnostics for explicit inspection rather than invoking them in every hook.

## Profile-backed diagnosis

A separate five-second `sample` capture of `agent status` completed successfully. The sampled
execution path is dominated by:

```text
MonitorCommand.AgentStatusCommand.run
  SessionMonitor.agentStatus
    UsageStore.usageLimitSnapshots
      UsageStore.usageLimitRows
        Row.fetchAll
          sqlite3_step
```

In the observed GRDB thread segment, 1,629 of 2,072 `AgentStatusCommand.run` stack samples
include quota loading. This is a selected five-second window, **not a percentage of the entire
command's wall time or all-process CPU**. Other sampled work includes the usage snapshot.

Source explains the unbounded read: [AgentStatus.swift](../../Sources/MonitorRuntime/AgentStatus.swift)
asks for `quotaPresentation(query: UsageQuery(), generatedAt: now)` even for one session.
[SessionMonitor.swift](../../Sources/MonitorRuntime/SessionMonitor.swift) loads a full snapshot
report before projecting it, and [UsageLimitSnapshotStore.swift](../../Sources/MonitorStore/UsageLimitSnapshotStore.swift)
materializes all matching observation rows through dedup/ranking SQL. This is work proportional
to accumulated history in the compact agent path. RAM memoization inside a short-lived CLI
process alone would not remove that read on the next invocation.

## Correctness and contract checks

- Every successful measured analytic output parsed as one JSON document; 143 processes succeeded.
- Report and snapshot `report` payloads match for the same fixed query (14,743 canonical requests).
- Fixed report/session/snapshot/activity/inspect/alert cases emitted byte-identical output across
  the first run and all repeats. Agent/diagnostic/quota timestamps are not treated as stable bytes.
- Invalid period, conflicting account scope flags and inconsistent agent windows returned exit
  **64**, wrote no stdout and supplied diagnostics on stderr.
- Three harness tests cover a live WAL backup with an uncommitted writer transaction, refusal to
  overwrite existing evidence, and descriptive statistics. `test-cli` now includes these checks.
- Full CLI schema/backward-compatibility audit, other platforms, App Store sandbox behavior,
  GUI frame latency and fresh-machine disk-cache conditions are outside this baseline.

## Next bounded change: SM-749

Make the compact agent path independent of the complete quota history. Define a bounded
latest-window projection or an atomically maintained summary, reusing existing domain rules.
Preserve account scope, limit/window/reset identity, coverage, unknown, freshness and reset
transition evidence. An arbitrary `LIMIT` or silently discarding old observations is not a fix.
Avoid constructing an all-session report when a known session only needs its own summary.

Retain raw quota/doctor commands for explicit deep inspection. Add a bounded summary interface
where needed without breaking existing JSON contracts. Verify projection parity on reset changes,
mixed accounts, partial observations and stable input, then rerun this same baseline. Choose
and document the latency/output budget from the measured intended agent workload before
claiming that the CLI is fast enough.

## Reproduction

Use the same Release executable and a local index. The harness backs up the index through
SQLite; it never benchmarks against the live database. Choose a new **private** output directory
on the configured build volume. The directory contains sensitive metadata and must not be committed.

```sh
rtk proxy env PYTHONDONTWRITEBYTECODE=1 python3 scripts/performance/cli_queries.py \
  --binary /path/to/codex-monitor \
  --source-revision ccfb96f4b59549643933ef49ec02187ed3559564 \
  --database /path/to/usage.sqlite \
  --output /private/build-volume/cli-baseline \
  --since 2026-10-17T00:00:00Z --until 2026-10-24T11:00:00Z \
  --repetitions 10 --timeout 45

rtk proxy env PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover \
  -s scripts/tests -p test_cli_queries.py -v
```

Local evidence directory: `measurements/sm746-cli` under this checkout's configured build root.
`baseline/results.json` contains timings; raw command outputs, the SQLite backup,
`agent-status.sample.txt` and App Store Connect readiness output remain private.
App Store preparation is tracked separately in [the readiness assessment](../mac-app-store-readiness.md).
