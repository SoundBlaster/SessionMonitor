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

Validation: core SwiftLint and diff check passed. Local Swift tests not executed for
this layer: Xcode MCP test run for the preceding layer timed out after 300 seconds,
and local disk space remains critically low. Required CI remains the test gate.
