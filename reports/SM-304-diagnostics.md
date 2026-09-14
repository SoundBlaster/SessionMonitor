# SM-304 — sessions, inspect, doctor

## Schema findings

The doctor --json command emits a stable DiagnosticReport object:

~~~json
{
  "schemaVersion": 1,
  "query": {},
  "findings": [
    {
      "id": "repetitive_polling",
      "severity": "warning",
      "title": "Repetitive polling",
      "explanation": "...",
      "evidence": {
        "observed": [],
        "inference": [],
        "unknown": [],
        "limitations": []
      },
      "confidence": "medium",
      "affectedSessions": ["..."],
      "suggestedNextAction": "..."
    }
  ]
}
~~~

evidence.observed contains persisted facts, evidence.inference contains the
bounded diagnostic heuristic, and evidence.unknown contains facts the source
does not establish. limitations records scope and coverage constraints. Findings
are sorted by stable id; arrays of session/response/source-line references are
sorted before encoding. The encoder uses sorted JSON keys.

Implemented finding IDs:

- repetitive_polling
- excessive_startup_overhead
- unusual_cache_changes
- missing_provenance
- relationship_orphan
- relationship_conflict
- relationship_cycle
- malformed_source_evidence
- incomplete_source_evidence

The sessions --json command emits SessionListReport (schemaVersion: 1) with the
canonical per-session totals, cache status/ratio, provenance state and
relationship state. It supports --sort input|requests|cached|output|id,
--order asc|desc, --model, --id-prefix and --relationship.

The inspect <session-id> --json command emits SessionInspection (schemaVersion: 1)
with totals, explicit cache coverage, timeline counts and bounds, model, effort,
client version, relationship metadata, evidence sources and limitations.

## Evidence sources

The read-only query layer uses only persisted contracts:

- confirmed — deduplicated canonical UsageRecord totals and response IDs;
- source_timeline_events — explicit human/goal/tool/wait/compaction events;
- source_provenance — explicit session metadata and parent/root relationship;
- source_diagnostics — parser/import quality counters;
- session_tree — classification performed by the existing SessionTreeBuilder;
- diagnostic_heuristic — the inference label, never a source of observed data.

No finding uses prompt text, source file names, guessed intent or synthesized
metadata. Diagnostic queries do not import, write, apply configuration, change
watermarks or alter UsageRecord/canonical totals.

Heuristics are intentionally bounded:

- polling requires at least three explicit wait-to-request pairs within 60 seconds;
- startup overhead requires at least two first-turn requests and a first-turn
  average input at least twice the median of later requests;
- cache change requires adjacent known cache ratios to differ by at least 50
  percentage points; unknown cache values are excluded, never treated as zero.

## Negative cases

Covered by targeted tests:

- one normal wait does not become a polling finding;
- one first request does not become startup overhead;
- compaction is preserved as timeline evidence and is not an error finding;
- unknown cache produces partial coverage/unknown evidence, not a low cache hit;
- missing optional effort/client metadata is an explicit limitation, not damaged
  accounting;
- source-wide malformed/incomplete counters keep affectedSessions unknown;
- empty databases return empty sessions and findings.

Relationship findings use the existing orphan/conflict/cycle classification and
do not combine parent and child totals.

## Targeted checks

Passed on 2026-09-13:

- swift test --filter DiagnosticsTests — 11 tests;
- swift test --filter RequestTimelineTests — 5 tests;
- swift test --filter SessionTreeTests — 6 tests;
- swift test --filter QuerySnapshotTests — 7 tests;
- targeted SwiftLint for changed Swift files — 0 violations;
- fsd-ios lint --config .fsd-ios.yml --strict --architecture — 0 errors, 0 warnings;
- git diff --check;
- CLI smoke: sessions --json, doctor --json, inspect --help,
  root help and missing-session validation.

The full make check was intentionally not run.

## Limitations and follow-ups

- Startup overhead and polling are evidence-backed heuristics, not proof of
  waste or user intent; thresholds are currently fixed and should become
  configurable or baseline-derived in SM-308.
- Source diagnostics are database-wide counters and cannot be assigned to a
  session without explicit source evidence.
- Relationship state is evaluated for the sessions in the selected query; a
  parent outside that query can therefore remain an orphan in that presentation.
- No configuration apply or remediation is included.
- GUI integration, additional usage statistics and production-captured auxiliary
  telemetry remain outside SM-304 and belong to later roadmap work.
