import Foundation
import GRDB
import MonitorCore
import MonitorPolicies
import MonitorRuntime
import MonitorStore
import Testing

struct QuotaSummaryTests {
    @Test func reducesLongHistoryWithoutLosingCoverageOrResetWitnesses() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        var snapshots = (1...2_000).map { index in
            snapshot("event-\(index)", at: Double(index), line: index,
                     reset: index < 1_000 ? 5_000 : 6_000)
        }
        snapshots.insert(snapshot("old-partial", at: 0, line: 0, state: .partial, windows: []), at: 0)
        snapshots.append(snapshot("latest-unknown-reset", at: 2_001, line: 2_001, reset: nil, state: .partial))
        snapshots.append(snapshot("unsupported", at: 2_002, line: 2_002, state: .unsupportedSchema, windows: []))
        try replace(store, source: fixture.source, snapshots: snapshots)

        let result = try parity(store)
        #expect(result.evidence.snapshots.count == 3)
        #expect(result.report.coverage.supportedWindowObservations == 2_001)
        #expect(result.report.coverage.partialSnapshots == 2)
        #expect(result.report.coverage.unsupportedSnapshots == 1)
        #expect(result.report.coverage.latestObservedAt == Date(timeIntervalSince1970: 2_002))
        let window = try #require(result.report.windows.first)
        #expect(window.resetsAt == nil)
        #expect(window.resetDiscontinuity?.previousObservedAt == Date(timeIntervalSince1970: 999))
        #expect(window.resetDiscontinuity?.currentObservedAt == Date(timeIntervalSince1970: 1_000))
    }

    @Test func keepsEveryLatestTieAndAllSeriesIdentities() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        var observations = [snapshot("before", at: 1, line: 1, reset: 300)]
        observations += (2...60).map { index in
            snapshot("tie-\(index)", at: 2, line: index, used: Double(index), reset: 500)
        }
        observations += [
            snapshot("named", at: 3, line: 61, name: "name:literal"),
            snapshot("id", at: 4, line: 62, limit: "name:name:literal"),
            snapshot("unicode-before", at: 5, line: 63, reset: 300, name: "caf\u{00e9}"),
            snapshot("unicode-after", at: 6, line: 64, reset: 500, name: "cafe\u{0301}"),
            snapshot("weekly", at: 7, line: 65, windows: [
                UsageLimitWindowObservation(slot: .secondary, windowMinutes: 10_080, usedPercent: nil, resetsAt: nil)
            ])
        ]
        try replace(store, source: fixture.source, snapshots: observations)
        let result = try parity(store)
        #expect(result.report.windows.count == 5)
        let primary = try #require(result.report.windows.first { $0.limitID == "limit" && $0.slot == .primary })
        #expect(primary.isAmbiguous)
        #expect(primary.remainingPercent == nil)
        #expect(primary.resetDiscontinuity == nil)
        #expect(result.evidence.snapshots.filter { $0.timestamp == Date(timeIntervalSince1970: 2) }.count == 59)
    }

    @Test func refreshesMirrorsReplacementsAndProfileMappingAtomically() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let sourceA = fixture.directory.appending(path: "home/a.jsonl").path
        let sourceB = fixture.directory.appending(path: "home/b.jsonl").path
        let sourceC = fixture.directory.appending(path: "work/c.jsonl").path
        let identityA = SourceAccountIdentity(accountID: "A", userID: nil)
        let identityB = SourceAccountIdentity(accountID: "B", userID: nil)
        let observations = [snapshot("same-event", at: 1, line: 1), snapshot("later", at: 2, line: 2)]
        try replace(store, source: sourceA, snapshots: observations, identity: identityA)
        try replace(store, source: sourceB, snapshots: observations, identity: identityA)
        try replace(store, source: sourceC, snapshots: observations, identity: identityB)
        #expect(try parity(store).report.windows.count == 2)
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "home"),
                                           profileID: "home", label: "Home")
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "work"),
                                           profileID: "work", label: "Work")
        #expect(try parity(store).report.accountCoverages.count == 2)
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "home"),
                                           profileID: "home", label: "Renamed")
        #expect(try parity(store).report.windows.contains { $0.accountProfileLabel == "Renamed" })

        // Removing the lexical winner must recover its surviving mirror, then remove the emptied series.
        try replace(store, source: sourceA, snapshots: [], identity: identityA)
        #expect(try parity(store).report.windows.count == 2)
        try replace(store, source: sourceB, snapshots: [], identity: identityA)
        #expect(try parity(store).report.windows.count == 1)
        try replace(store, source: sourceA, snapshots: observations, identity: identityB)
        _ = try parity(store)
        try replace(store, source: sourceB, snapshots: observations, identity: identityA)
        let mixed = try parity(store).report
        #expect(mixed.windows.filter { $0.accountScopeState == .mixed }.allSatisfy { $0.accountProfileID == nil })
        #expect(mixed.accountCoverages.contains { $0.accountScopeState == .mixed })
        _ = try parity(store, query: UsageQuery(accountScope: UsageAccountScope(profileID: "work")))
        _ = try parity(store, query: UsageQuery(accountScope: .unknownOrMixed))
    }

    @Test func appendAndUnchangedImportsKeepProjectionCurrent() async throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.event(timestamp: "2026-09-20T10:00:00Z", used: 82))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        try fixture.append(fixture.event(timestamp: "2026-09-20T10:01:00Z", used: 89))
        for _ in 0..<2 {
            _ = try await runtime.importDirectory(fixture.file)
            let now = Date(timeIntervalSince1970: 100)
            let summary = try await runtime.quotaSummary(query: UsageQuery(), generatedAt: now)
            let full = try await runtime.quotaPresentation(query: UsageQuery(), generatedAt: now)
            #expect(summary == full)
            #expect(summary.coverage.supportedWindowObservations == 2)
            #expect(summary.windows.first?.usedPercent == 89)
        }
    }

    @Test func olderWriterCannotLeaveAStaleSummaryAndFilteredDedupStaysExact() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try replace(store, source: "a", snapshots: [snapshot("mirror", at: 1, line: 1)])
        try replace(store, source: "b", snapshots: [snapshot("mirror", at: 2, line: 2, used: 80)])
        _ = try parity(store, query: UsageQuery(since: Date(timeIntervalSince1970: 2)))
        let writer = try DatabaseQueue(path: fixture.database.path)
        try writer.write { database in
            try database.execute(sql: """
                UPDATE source_usage_limit_snapshots SET used_percent = 99 WHERE slot_key = 'primary'
                """)
        }
        #expect(try parity(store).report.windows.first?.usedPercent == 99)
        try replace(store, source: "a", snapshots: [])
        #expect(try parity(store).report.windows.first?.usedPercent == 99)
    }

    @Test func projectionFailureRollsBackRawRowsAndWatermark() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try replace(store, source: fixture.source, snapshots: [snapshot("original", at: 1, line: 1)])
        let before = try parity(store)
        let watermark = try store.snapshot(query: UsageQuery())?.watermark
        let writer = try DatabaseQueue(path: fixture.database.path)
        try writer.write { database in
            try database.execute(sql: """
                CREATE TRIGGER fail_projection BEFORE INSERT ON quota_projection_windows
                BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END
                """)
        }
        #expect(throws: (any Error).self) {
            try replace(store, source: fixture.source, snapshots: [snapshot("replacement", at: 2, line: 2)])
        }
        #expect(try parity(store).report == before.report)
        #expect(try store.snapshot(query: UsageQuery())?.watermark == watermark)
    }

    @Test func emptyAndWindowlessCoverageRemainUnknown() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        #expect(try parity(store).report.coverage.unknownReason == .noSnapshotInPeriod)
        try replace(store, source: fixture.source, snapshots: [snapshot("empty", at: 1, line: 1,
                                                                     state: .noWindowData, windows: [])])
        let result = try parity(store)
        #expect(result.evidence.snapshots.isEmpty)
        #expect(result.report.coverage.unknownReason == .noWindowData)
        #expect(result.report.accountCoverages.count == 1)
    }

    @Test func migrationBackfillsExistingHistoryWithoutChangingCanonicalData() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try replace(store, source: fixture.source, snapshots: [
            snapshot("before", at: 1, line: 1, reset: 300),
            snapshot("after", at: 2, line: 2, reset: 500)
        ])
        let before = try store.usageLimitSnapshots(query: UsageQuery(), generatedAt: Date(timeIntervalSince1970: 2_000))
        let watermark = try store.snapshot(query: UsageQuery())?.watermark
        let writer = try DatabaseQueue(path: fixture.database.path)
        try writer.write { database in
            let triggers = try String.fetchAll(database, sql: """
                SELECT name FROM sqlite_master WHERE type = 'trigger' AND name LIKE 'quota_projection_%'
                """)
            for trigger in triggers { try database.execute(sql: "DROP TRIGGER \(trigger.quotedDatabaseIdentifier)") }
            try database.execute(sql: """
                DROP TABLE quota_projection_windows;
                DROP TABLE quota_projection_snapshots;
                DROP TABLE quota_projection_dirty;
                DROP INDEX quota_event_sources;
                DELETE FROM grdb_migrations WHERE identifier = 'quota-presentation-projection-v1';
                """)
        }
        let migrated = try UsageStore(url: fixture.database)
        _ = try parity(migrated)
        #expect(try migrated.usageLimitSnapshots(query: UsageQuery(), generatedAt: before.generatedAt) == before)
        #expect(try migrated.snapshot(query: UsageQuery())?.watermark == watermark)
    }

    func parity(
        _ store: UsageStore, query: UsageQuery? = nil
    ) throws -> (report: QuotaPresentationReport, evidence: QuotaPresentationEvidence) {
        let query = try query ?? UsageQuery()
        let now = Date(timeIntervalSince1970: 2_000)
        let evidence = try store.quotaPresentationEvidence(query: query, generatedAt: now)
        let full = try store.usageLimitSnapshots(query: query, generatedAt: now)
        let decision = QuotaPresentationDecision()
        let report = decision.presentation(for: evidence)
        #expect(report == decision.presentation(for: QuotaPresentationContext(report: full)))
        return (report, evidence)
    }

    func replace(
        _ store: UsageStore, source: String, snapshots: [UsageLimitSnapshotObservation],
        identity: SourceAccountIdentity? = nil
    ) throws {
        var rollout = ParsedRollout()
        rollout.usageLimitSnapshots = snapshots
        rollout.accountIdentity = identity
        try store.replace(source: source, rollout: rollout)
    }

    func snapshot(
        _ id: String, at time: Double, line: Int, used: Double? = 20, reset: Double? = 3_000,
        limit: String? = nil, name: String? = nil, state: UsageLimitSnapshotState = .observed,
        windows: [UsageLimitWindowObservation]? = nil
    ) -> UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: id, timestamp: Date(timeIntervalSince1970: time), sourceLine: line,
            sourceContextSessionID: "session", sourceSchema: "fixture", state: state, scope: .account,
            limitID: limit ?? (name == nil ? "limit" : nil), limitName: name, planType: "fixture",
            windows: windows ?? [UsageLimitWindowObservation(
                slot: .primary, windowMinutes: 300, usedPercent: used,
                resetsAt: reset.map(Date.init(timeIntervalSince1970:))
            )]
        )
    }
}
