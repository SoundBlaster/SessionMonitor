# SM-409 — Backfill checkpoint safety

Metadata backfill previously promoted a checkpoint to the current file EOF without
importing newly appended canonical records. The normal importer then skipped them.

Backfill now requires the exact previously imported file version and cursor. A
changed source proceeds through normal incremental import (current schema) or a
full replacement (legacy schema/replaced file). Unchanged legacy databases retain
the metadata-only upgrade path without rewriting canonical rows.

Regression cases: schema 2 and 4, append and atomic replacement, full-parse parity,
provenance recovery and an idempotent subsequent import. Existing unchanged-backfill
and partial-tail tests remain part of the validation scope.

Validation: final cumulative stack MCP builds succeeded; 155 core tests and all
four CLI process smoke suites passed, along with core SwiftLint/FSD/architecture
regression, actionlint/shell syntax and diff checks. [Commands, execution boundaries and initial MCP/disk
failures](SM-409-412-validation.md). GitHub CI/review/merge remain pending.
