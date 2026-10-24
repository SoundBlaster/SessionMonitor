# Watching and import troubleshooting

[← SessionMonitor](../README.md) · [CLI guide](cli.md)

## Start, pause, resume, stop

```sh
codex-monitor watch ~/.codex/sessions
codex-monitor watch ~/.codex/sessions --alerts --debounce-milliseconds 250
```

On macOS, Watch registers FSEvents before its first import. It coalesces changes in a bounded
250 ms window (configurable from 1–60,000 ms); continuous writes do not postpone reconciliation
forever. Each pass reconciles the directory using incremental checkpoints. Changes arriving
during an import schedule another pass. Dropped/coalesced events trigger reconciliation too.
Linux uses directory polling every two seconds instead of FSEvents.

The CLI emits JSON status lines with `phase`, `completedImports`, `lastImport`, and recovery errors.
`SIGUSR1` pauses after the current import; wait for `paused` before assuming no new import will
start. `SIGUSR2` resumes with a directory reconciliation. Ctrl-C / SIGINT or SIGTERM cancels the
import, waits for cleanup, and closes the stream. On stdout backpressure, shutdown waits at
most 250 ms for output; the last status lines can be dropped.

The root must exist at startup. Watching its parent detects deletion, rename, and recreation.
An unavailable root or a file changing during a read enters recovery with exponential backoff
from 1 to 30 seconds. The database remains accessible if sources move. Database/WAL/SHM and
import/setup locks are excluded from discovery and ordinary events, even if the database is
named `usage.jsonl`. Hidden entries and unsupported files do not trigger ordinary refreshes.

## “Database in use” / “Another importer is using this database”

Only one importer can own a database. Watch holds that ownership even while paused or recovering.

Manual **Import Folder**, **Update**, and **Retry Import** stop this app’s Watch, wait for cleanup,
and serialize imports across its windows. Watch stays stopped until you explicitly restart it.
If the database is still busy:

1. Stop Watch in any other running SessionMonitor instance, or stop `codex-monitor watch` with Ctrl-C.
2. Allow an import already in progress to finish. **Pause Watch does not release the lock.**
3. Use **Retry Import** for the same folder.

The message cannot identify the lock owner. Do not delete the SQLite database or `.import-lock`
file to fix it. The operating system releases ownership after a crash or SIGKILL; symlinks to
the same database do not create independent ownership. Normal readers remain available.
A failed attempt to start an import preserves the previous report and successful source folder.

## A session changed during import

Codex may append to a log while SessionMonitor reads it. The importer keeps earlier completed
files and does not advance the changing file’s checkpoint. Retry the same folder when writes
settle; the next attempt resumes from saved checkpoints. Stopping an import also preserves
completed files. An incomplete final JSONL line is processed once its newline arrives.

## Data seems stale

- **Refresh** only rereads the index. Use **Update** or Watch to import source changes.
- Confirm the selected folder includes older session files: an old session can receive new requests.
- Confirm the account and period filters, including a temporary cache-chart interval filter.
- Compare app and CLI results using the same database, account, and interval.
- An index commit time describes the index, not the freshness of every log file.

## Swift API lifecycle

`try await monitor.watch(directory)` returns a `SessionWatch` with `updates` (a single consumer,
latest status), `status`, `pause()`, `resume()`, and `stop()`. The owner must call `await stop()`
or await `waitUntilStopped()` in a task whose cancellation stops the watcher. Ownership is
released only after the importer finishes cleanup; lock files are not deleted on release.
