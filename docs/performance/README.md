# Performance baseline

SM-105 measures the production Swift CLI on an independent copy of a real archive.
The harness uses Python 3.9+ standard library, Apple's `/usr/bin/time -lp` and `/bin/ps`;
no additional benchmark framework or runtime dependency is required.

## Reproduce

```sh
rtk proxy make benchmark \
  BENCHMARK_SOURCE=/path/to/rollout-corpus \
  BENCHMARK_SINCE=2026-09-05T05:27:20Z \
  BENCHMARK_UNTIL=2026-09-12T05:27:20Z \
  BENCHMARK_OUTPUT=.build/performance/my-run
```

The output directory must be new and located under the repository's ignored `.build`.
The explicit source is read-only. The harness copies visible `*.jsonl` files, checks
size/identity/modification metadata around each copy, and retries unstable files up
to three times. It creates independent files, never symlinks or hard links. The
harness requires corpus size plus 1 GiB of free working space before copying. The
snapshot is stable per file; it is not an atomic snapshot of an entire live archive.
Compressed and numeric rotated archives are outside this harness's corpus contract:
use an explicit JSONL export for those (the production importer supports numeric rotation).

`make benchmark` builds release CLI first. `SWIFT_FLAGS` applies equally to the build
and binary-path lookup. The default is three repetitions and two 30-second idle
samples; change `BENCHMARK_REPETITIONS` / `BENCHMARK_IDLE_SECONDS` explicitly when needed.
Compilation, copying, audit, and setup are outside measured CLI command intervals.
Run without competing builds to reduce scheduler and I/O interference.

## Measurements

1. **Fresh index:** independent new database for each repetition, same copied corpus.
   Fresh index does not mean cold disk: OS cache is uncontrolled and the corpus was
   just copied. Report minimum, median and maximum, not one favorable run.
2. **Unchanged:** reopen each database and import the same corpus. Require all files
   skipped and zero application source bytes read.
3. **Append:** append one synthetic owned request outside the audit period to the
   largest copied file ending in a newline. Each already-imported database processes
   the same delta. Other files must be skipped. Record delta size and actual bytes
   read separately, including old-prefix SHA256 verification.
4. **Parity:** run the existing `audit_codex.py` on the same private corpus and period.
   Compare request count and all six token totals. Unknown cache/optional totals
   cannot be silently converted to zero to claim parity. The window report must be
   unchanged after append, and every full-report field must match a fresh rebuild.
5. **Idle:** wait for an unchanged watch import and one second of settling, then
   measure watch alone and watch plus one snapshot observer. CPU is process CPU-time
   delta, expressed as percent of one core, not system-wide CPU. Verify no JSON
   updates occur during the sample; signals stop and join the spawned processes.
6. **Database size:** sum database/WAL/SHM logical byte sizes after measured writers
   exit. This is not allocated disk blocks, peak WAL size or original archive size.

`time` reports wall time, user+system CPU, and maximum resident set size (bytes on
macOS). Time/CPU values have centisecond resolution. Idle `ps time` also has 0.01 s
resolution: a zero delta means below measurement resolution, not proof of zero work.
Raw native time logs retain additional OS metrics, including peak memory footprint
when available; RSS and footprint are different quantities.

`baseline.json` records the binary SHA256, build configuration, toolchain, hardware,
corpus content fingerprint and individual samples. `private-manifest.json` contains
local source pointers; full audit outputs remain private in `.build`. The independent
corpus copy is removed after a successful run unless `--keep-corpus` is supplied directly
to the harness; failed runs retain their partial output for diagnosis. Only a reviewed aggregate summary belongs in Git. Do not upload the corpus
or detailed audit as CI artifacts.

## Quality gate

`make test-cli` runs `scripts/tests/performance-smoke.py` against a tiny synthetic
corpus. It executes the same harness, validates native measurements, audit and
incremental/full parity, and verifies the original input is unchanged. Its short
idle window is a correctness smoke test, not a performance result. The smoke runs
the harness with optimized Python and verifies that intentionally corrupted I/O metrics
are rejected without publishing a successful baseline. Runtime checks remain active under `-O`. Real archive
measurements are explicit local runs and never an automatic CI input.

## Current correctness boundary

The existing decoder rereads a changed file's old committed prefix to validate its
SHA256. Therefore unchanged import is zero-body-read, but append is **not** delta-only
I/O. The benchmark explicitly records `append.reads_only_delta`; a false result must
remain visible in ROADMAP. Replacing verification with an assumption that file growth
means append-only would miss rewrite-plus-growth and violate accounting recovery.

## Recorded runs

- [2026-09-12 — 155-file release baseline](2026-09-12.md)
