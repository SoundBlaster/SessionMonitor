# SM-412 — Root activity account isolation

Root membership previously matched only session ID in the global provenance table.
A session in profile A could therefore be included because another account used
the same session ID under the requested root.

Both canonical usage and operational activity now correlate root provenance with
the row's account scope key. Query-level profile filtering remains unchanged;
All accounts still aggregates selected root sessions while child membership is
resolved independently in each scope, including unmapped roots.

Regression fixtures cover assigned profiles and Unknown/Mixed roots, identical
session IDs with different roots, root mirrors, totals/event counts and removal of
foreign provenance. No new aggregation or account attribution is introduced.

Validation: final cumulative stack MCP builds succeeded; 155 core tests and all
four CLI process smoke suites passed, along with core SwiftLint/FSD/architecture
regression, actionlint/shell syntax and diff checks. [Commands, execution boundaries and initial MCP/disk
failures](SM-409-412-validation.md). GitHub CI/review/merge remain pending.
