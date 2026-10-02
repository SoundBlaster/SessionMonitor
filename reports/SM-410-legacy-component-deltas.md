# SM-410 — Legacy component delta uncertainty

Valid cumulative totals can still produce invalid component deltas, e.g. input
100 → 110 and cached 0 → 100. Previously the inferred cached delta 100 violated
the SQLite constraint for input delta 10 and rolled back the entire source import.

Cached/reasoning deltas now require a nonnegative difference bounded by their
input/output delta. Otherwise the component stays nil with an explicit diagnostic:
`legacyUnknownCacheDeltas` or `legacyUnknownReasoningDeltas`. Reliable parent deltas
remain available; canonical records are still counted separately. The cumulative
baseline advances so later comparable samples can resume after restart.

The regression fixture covers both invalid components, persisted unknown values,
canonical import success, subsequent valid deltas after restart and skipped reimport.

Validation: final cumulative stack MCP builds succeeded; 155 core tests and all
four CLI process smoke suites passed, along with core SwiftLint/FSD/architecture
regression, actionlint/shell syntax and diff checks. [Commands, execution boundaries and initial MCP/disk
failures](SM-409-412-validation.md). GitHub CI/review/merge remain pending.

CI pull_request base filtering is removed so every dependent stack layer runs the
existing required gates. Push triggers and gate jobs stay unchanged.
