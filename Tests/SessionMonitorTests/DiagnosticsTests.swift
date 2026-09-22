import Foundation
import MonitorCore
import MonitorStore
import Testing

struct DiagnosticsTests {
    @Test func sessionsSortsAndFiltersWithoutChangingCanonicalTotals() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "small", rollout: fixture.rollout(
            records: [fixture.record(session: "small", id: "S1", input: 10, cached: 5, model: "alpha")]
        ))
        try store.replace(source: "large", rollout: fixture.rollout(
            records: [fixture.record(session: "large", id: "L1", input: 20, cached: 10, model: "beta")]
        ))
        let before = try #require(try store.snapshot(query: UsageQuery()))

        let sorted = try store.listSessions(query: UsageQuery(), sort: .input, descending: true)
        #expect(sorted.sessions.map(\.id) == ["large", "small"])
        let filtered = try store.listSessions(
            query: UsageQuery(), sort: .id, descending: false, model: "alpha", idPrefix: "sm"
        )
        #expect(filtered.sessions.map(\.id) == ["small"])
        #expect(filtered.sessions[0].totals.inputTokens == 10)
        #expect(try store.snapshot(query: UsageQuery())?.report.totals == before.report.totals)
    }

    @Test func inspectSeparatesKnownAndUnknownCacheCoverage() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        var rollout = fixture.rollout(records: [
            fixture.record(session: "S", id: "R1", turn: "T", input: 100, cached: 80, line: 1),
            fixture.record(session: "S", id: "R2", turn: "T", timestamp: 101, input: 50, cached: nil, line: 2)
        ], provenance: fixture.provenance("S", effort: "medium", clientVersion: "1.2"))
        rollout.timelineEvents = [
            fixture.event(session: "S", line: 1, timestamp: 100, kind: .humanTurn, evidence: "human_turn_started")
        ]
        try store.replace(source: "source", rollout: rollout)

        let inspected = try #require(try store.inspect(sessionID: "S", query: UsageQuery()))
        #expect(inspected.totals.requests == 2)
        #expect(inspected.cache.status == .partial)
        #expect(inspected.cache.knownRequests == 1)
        #expect(inspected.cache.unknownRequests == 1)
        #expect(inspected.cache.hitRatio == nil)
        #expect(inspected.timeline.usageRequests == 2)
        #expect(inspected.model == "fixture")
        #expect(inspected.evidence.observed.map(\.source).contains("source_provenance"))
        #expect(inspected.evidence.unknown.contains { $0.detail.contains("unknown cached") })
    }

    @Test func normalWaitFirstRequestAndCompactionAreNotFindings() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        var rollout = fixture.rollout(records: [
            fixture.record(session: "normal", id: "N1", turn: "T1", input: 100, cached: 80, line: 1),
            fixture.record(session: "normal", id: "N2", turn: "T2", timestamp: 120, input: 100, cached: 80, line: 2),
            fixture.record(session: "normal", id: "N3", turn: "T3", timestamp: 240, input: 100, cached: 80, line: 3)
        ])
        rollout.timelineEvents = [
            fixture.event(session: "normal", line: 1, timestamp: 101, kind: .wait, evidence: "wait_started"),
            fixture.event(session: "normal", line: 2, timestamp: 102, kind: .compaction, evidence: "compacted")
        ]
        try store.replace(source: "normal", rollout: rollout)
        try store.replace(source: "first", rollout: fixture.rollout(
            records: [fixture.record(session: "first", id: "F1", input: 10, cached: 10)]
        ))
        let findings = try store.doctor(query: UsageQuery()).findings.map(\.id)
        #expect(!findings.contains("repetitive_polling"))
        #expect(!findings.contains("excessive_startup_overhead"))
        #expect(!findings.contains("compaction"))
    }

    @Test func repetitivePollingRequiresRepeatedWaitRequestPairs() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let records = (0..<3).map { index in
            fixture.record(session: "poll", id: "P\(index)", turn: "T\(index)",
                           timestamp: Double(index * 2 + 1), input: 20, cached: 20, line: index + 1)
        }
        let events = (0..<3).map { index in
            fixture.event(session: "poll", line: index + 1, timestamp: Double(index * 2),
                          kind: .wait, evidence: "wait_started")
        }
        try store.replace(source: "poll", rollout: fixture.rollout(records: records, events: events))
        let finding = try #require(try store.doctor(query: UsageQuery()).findings.first {
            $0.id.hasPrefix("repetitive_polling|")
        })
        #expect(finding.affectedSessions == ["poll"])
        #expect(finding.evidence.observed.first?.source == "source_timeline_events")
        #expect(finding.evidence.inference.first?.source == "diagnostic_heuristic")
        #expect(finding.evidence.inference.contains { $0.source == "specification_core_policy" })
    }

    @Test func startupOverheadRequiresRepeatedFirstTurnRequests() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "startup", rollout: fixture.rollout(records: [
            fixture.record(session: "startup", id: "S1", turn: "first", input: 1_000, cached: 900, line: 1),
            fixture.record(
                session: "startup", id: "S2", turn: "first", timestamp: 1,
                input: 1_000, cached: 900, line: 2
            ),
            fixture.record(session: "startup", id: "S3", turn: "later", timestamp: 2, input: 100, cached: 90, line: 3)
        ]))
        let finding = try #require(try store.doctor(query: UsageQuery()).findings.first {
            $0.id.hasPrefix("excessive_startup_overhead|")
        })
        #expect(finding.affectedSessions == ["startup"])
        #expect(finding.evidence.limitations.contains("One first request alone is not classified as startup overhead."))
    }

    @Test func cacheChangeUsesKnownValuesAndDoesNotTreatUnknownAsZero() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "cache", rollout: fixture.rollout(records: [
            fixture.record(session: "cache", id: "C1", turn: "T1", input: 1_000, cached: 1_000, line: 1),
            fixture.record(session: "cache", id: "C2", turn: "T2", timestamp: 1, input: 1_000, cached: 0, line: 2),
            fixture.record(session: "cache", id: "C3", turn: "T3", timestamp: 2, input: 1_000, cached: nil, line: 3)
        ]))
        let finding = try #require(try store.doctor(query: UsageQuery()).findings.first {
            $0.id.hasPrefix("unusual_cache_changes|")
        })
        #expect(finding.evidence.unknown.first?.detail.contains("unknown cache") == true)
        #expect(try store.snapshot(query: UsageQuery())?.report.totals.unknownCacheRequests == 1)
    }

    @Test func doctorDoesNotCompareCacheSamplesAcrossModels() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "models", rollout: fixture.rollout(records: [
            fixture.record(
                session: "models", id: "M1", turn: "T1", input: 1_000,
                cached: 1_000, model: "alpha", line: 1
            ),
            fixture.record(
                session: "models", id: "M2", turn: "T2", timestamp: 1,
                input: 1_000, cached: 0, model: "beta", line: 2
            ),
            fixture.record(
                session: "models", id: "M3", turn: "T3", timestamp: 2,
                input: 1_000, cached: 0, model: "beta", line: 3
            )
        ]))

        let findings = try store.doctor(query: UsageQuery()).findings
        #expect(!findings.contains { $0.id.hasPrefix("unusual_cache_changes|") })
    }

    @Test func missingProvenanceAndRelationshipStatesAreExplicit() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "missing", rollout: fixture.rollout(
            records: [fixture.record(session: "missing", id: "M1")]
        ))
        try store.replace(source: "parent", rollout: fixture.rollout(
            records: [fixture.record(session: "parent", id: "P1")],
            provenance: fixture.provenance("parent", root: "parent")
        ))
        try store.replace(source: "conflict", rollout: fixture.rollout(
            records: [fixture.record(session: "conflict", id: "C1")],
            provenance: fixture.provenance("conflict", parent: "parent", root: "other")
        ))
        try store.replace(source: "orphan", rollout: fixture.rollout(
            records: [fixture.record(session: "orphan", id: "O1")],
            provenance: fixture.provenance("orphan", parent: "absent")
        ))
        try store.replace(source: "cycle-a", rollout: fixture.rollout(
            records: [fixture.record(session: "cycle-a", id: "A1")],
            provenance: fixture.provenance("cycle-a", parent: "cycle-b")
        ))
        try store.replace(source: "cycle-b", rollout: fixture.rollout(
            records: [fixture.record(session: "cycle-b", id: "B1")],
            provenance: fixture.provenance("cycle-b", parent: "cycle-a")
        ))

        let report = try store.doctor(query: UsageQuery())
        let ids = Set(report.findings.map(\.id))
        #expect(ids.contains("missing_provenance"))
        #expect(ids.contains("relationship_orphan"))
        #expect(ids.contains("relationship_conflict"))
        #expect(ids.contains("relationship_cycle"))
        let sessions = try store.listSessions(query: UsageQuery(), sort: .id, descending: false).sessions
        #expect(sessions.first { $0.id == "missing" }?.provenanceState == .missing)
        #expect(sessions.first { $0.id == "orphan" }?.relationshipState == .orphan)
        #expect(sessions.first { $0.id == "conflict" }?.relationshipState == .conflict)
        #expect(sessions.first { $0.id == "cycle-a" }?.relationshipState == .cycle)
    }

    @Test func malformedAndIncompleteEvidenceBecomeDatabaseWideFindings() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        var rollout = fixture.rollout(records: [fixture.record(session: "S", id: "R")])
        rollout.diagnostics = ["malformedRecords": 2, "partialTails": 1]
        try store.replace(source: "source", rollout: rollout)
        let findings = try store.doctor(query: UsageQuery()).findings
        let malformed = try #require(findings.first { $0.id == "malformed_source_evidence" })
        let incomplete = try #require(findings.first { $0.id == "incomplete_source_evidence" })
        #expect(malformed.affectedSessions.isEmpty)
        #expect(incomplete.affectedSessions.isEmpty)
        #expect(malformed.evidence.observed.first?.source == "source_diagnostics")
        #expect(incomplete.evidence.unknown.first?.detail.contains("not session-scoped") == true)
    }

    @Test func diagnosticJSONIsStableAndRoundTrips() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "source", rollout: fixture.rollout(
            records: [fixture.record(session: "S", id: "R", cached: nil)]
        ))
        let query = try UsageQuery()
        let sessions = try store.listSessions(query: query)
        let inspection = try #require(try store.inspect(sessionID: "S", query: query))
        let doctor = try store.doctor(query: query)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let sessionData = try encoder.encode(sessions)
        let inspectionData = try encoder.encode(inspection)
        let doctorData = try encoder.encode(doctor)
        let secondSessionData = try encoder.encode(sessions)
        #expect(sessionData == secondSessionData)
        #expect(try JSONDecoder().decode(SessionListReport.self, from: sessionData) == sessions)
        #expect(try JSONDecoder().decode(SessionInspection.self, from: inspectionData) == inspection)
        #expect(try JSONDecoder().decode(DiagnosticReport.self, from: doctorData) == doctor)
    }

    @Test func emptyDatabaseHasStableEmptyDiagnostics() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let query = try UsageQuery()
        #expect(try store.listSessions(query: query).sessions.isEmpty)
        #expect(try store.inspect(sessionID: "missing", query: query) == nil)
        #expect(try store.doctor(query: query).findings.isEmpty)
    }

    @Test func canonicalTotalsRemainUnchangedByAllReadOnlyQueries() throws {
        let fixture = try DiagnosticsFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "source", rollout: fixture.rollout(records: [
            fixture.record(session: "S", id: "R1", input: 100, cached: 80, line: 1),
            fixture.record(session: "S", id: "R2", timestamp: 1, input: 40, cached: 0, line: 2)
        ]))
        let before = try #require(try store.snapshot(query: UsageQuery()))
        _ = try store.listSessions(query: UsageQuery(), sort: .output, descending: false)
        _ = try store.inspect(sessionID: "S", query: UsageQuery())
        _ = try store.doctor(query: UsageQuery())
        let after = try #require(try store.snapshot(query: UsageQuery()))
        #expect(after.report.totals == before.report.totals)
        #expect(after.watermark == before.watermark)
    }
}

private struct DiagnosticsFixture {
    let directory: URL
    var database: URL { directory.appending(path: "usage.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func record(
        session: String, id: String, turn: String = "T", timestamp: TimeInterval = 0,
        input: Int64 = 100, cached: Int64? = 80, output: Int64 = 10, model: String = "fixture",
        line: Int = 1
    ) -> UsageRecord {
        UsageRecord(
            responseID: id, sessionID: session, turnID: turn,
            timestamp: Date(timeIntervalSince1970: timestamp), model: model,
            inputTokens: input, cachedInputTokens: cached, outputTokens: output, sourceLine: line
        )
    }

    func event(
        session: String, line: Int, timestamp: TimeInterval, kind: TimelineEventKind, evidence: String
    ) -> TimelineSourceEvent {
        TimelineSourceEvent(
            sessionID: session, timestamp: Date(timeIntervalSince1970: timestamp), sourceLine: line,
            kind: kind, evidence: evidence
        )
    }

    func provenance(
        _ session: String, parent: String? = nil, root: String? = nil,
        effort: String? = nil, clientVersion: String? = nil
    ) -> SessionProvenance {
        SessionProvenance(
            sessionID: session, rootSessionID: root, clientVersion: clientVersion,
            models: ["fixture"], efforts: effort.map { [$0] } ?? [],
            relationship: parent.map { SessionRelationship(kind: .subagent, parentSessionID: $0) }
        )
    }

    func rollout(
        records: [UsageRecord], events: [TimelineSourceEvent] = [], provenance: SessionProvenance? = nil
    ) -> ParsedRollout {
        var result = ParsedRollout()
        result.records = records
        result.timelineEvents = events
        result.provenance = provenance
        return result
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
