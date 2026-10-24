# Data, accounting, and coverage

[← SessionMonitor](../README.md)

## What is counted

SessionMonitor accounts for canonical `token_usage_record` entries only when native turn
ownership and stable identifiers are confirmed. Fork replay and globally repeated response
IDs must not inflate totals. Conflicts and unsupported records appear in diagnostics.
Legacy `token_count` totals are not added to canonical usage because they can mirror it;
legacy-only histories are not fully covered.

Input includes cached input; cached input is not added again. Reasoning, where reported, is
part of output. Missing optional counters remain unknown rather than becoming zero. Aggregate
cache hit is total cached input divided by total input, not an average of request percentages.
The ratio is shown only with complete required cache fields and positive input.

Coverage describes the indexed canonical requests, not proof that the entire source archive
was imported. Stored import diagnostics cover all indexed sources even when the report has
a narrower period. Quota observations have their own account scope, reset interval, coverage,
and freshness. They are not live balances or evidence of a particular session’s account-level
consumption. [Quota ingestion contract](../reports/SM-308a-quota-snapshot-ingestion.md)

## Incremental import contract

Each source path has a persistent checkpoint. An unchanged file requires no body read. If its
identity is unchanged and its size grows, the importer assumes append-only input and reads from
the last completed newline, including after a restart. A partial line is reread with the new
bytes; raw tail contents are not stored in SQLite.

Replacement, truncation, metadata changes without growth, or an unsupported checkpoint force
a full rescan. Rewriting earlier lines while also growing the file is not automatically detected;
after manual edits/restoration, use `import DIRECTORY --rescan`. A v1 checkpoint is rebuilt as v2
on its next update. Import JSON `ioMetrics` reports bytes read and skipped/resumed/rescanned files.

SQLite retains the latest observed snapshot per source path. Missing paths do not delete old
snapshots; replacing a file at the same path rebuilds that path’s snapshot. This is not a history
of every file generation. Rotation/copytruncate retains earlier records when the archive is also
imported. Rename/copy adds source snapshots, while canonical response-ID dedup avoids counting
the same request twice. Old-path diagnostics retain their last observed state.

Records, diagnostics, and checkpoints for a file commit atomically. If an import fails, already
completed files remain saved; the current file keeps its previous checkpoint. A file changing
during a read is retried rather than committed as an inconsistent snapshot. WAL allows readers
while a single importer owns the database.

## Local data and exports

The index contains normalized usage/event metadata, source paths, session identifiers, and
available titles or subagent names. Prompt bodies and tool outputs are not persisted as transcript
content. Account attribution does not require reading authentication files. The source JSONL files
remain on disk unchanged.

`export-session` produces an anonymized diagnostic fixture rather than the original transcript.
Treat the original logs and database as local working data, not as files to attach publicly.
See [Context insights](context-insights.md) for the distinction between observed evidence,
inference, unknown values, and unsupported conclusions.

## Validation and performance references

Current checks and CI scope are documented in [Development](development.md) and
[Contributing](../CONTRIBUTING.md). Historical test counts in early release notes are not the
current suite size. Source-controlled tests exercise ownership, deduplication, checkpoints,
rollback, observation, lifecycle, and policy behavior with synthetic fixtures.

The [September 12 baseline](performance/2026-09-12-append.md) measured 155 files / 1,286,230,037
bytes: median fresh import 6.13 s; unchanged import 0.02 s / 0 body bytes; appending 752 bytes
read exactly 752 bytes (median 0.02 s). These are historical measurements on one archive, not
a performance guarantee. [Method and benchmark instructions](performance/README.md).

An earlier September 5–12 reference audit matched 6,340 requests, 775,583,024 input,
747,037,312 cached input, 3,120,896 output, and 778,703,920 total tokens. The 920,751 known reasoning
tokens were already included in output. Local raw logs and audit artifacts are excluded from Git.
