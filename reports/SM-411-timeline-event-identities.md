# SM-411 — Timeline operational event identities

Timeline previously returned every source event, including exact mirrors, and used
only line/kind for IDs. This duplicated activity evidence and gave events from
different accounts identical SwiftUI identities.

The event query now selects distinct complete event fields plus account scope key.
IDs hash an ordered, nullable serialization of that same logical identity (including
session and scope, excluding source path). Same-scope exact mirrors deduplicate;
different timestamps/tools/turns/evidence and different scopes remain distinct.
Canonical request totals and accounting IDs are unchanged.

Regression coverage includes assigned accounts with byte-identical events, unknown
roots, same-line different tools, exact mirrors and reverse import order. Event
counts are checked against activity rollups, and canonical totals stay unchanged.

Validation: final cumulative stack MCP builds succeeded; 155 core tests and all
four CLI process smoke suites passed, along with core SwiftLint/FSD/architecture
regression, actionlint/shell syntax and diff checks. [Commands, execution boundaries and initial MCP/disk
failures](SM-409-412-validation.md). GitHub CI/review/merge remain pending.
