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

Validation: core SwiftLint and diff check passed. Production usage and event SQL
extracted from the source passed an in-memory SQLite probe: profile A 100 tokens/1
event, profile B 200/1, all accounts 300/2. Xcode MCP build-for-testing succeeded. The resulting test bundle ran directly
without compilation: 148 Swift Testing + 7 XCTest tests passed (155 total), including
all four layers and both assigned/unknown root isolation cases. FSD lint and the
positive/negative architecture regression passed. No user databases were modified. CI/merge pending.
