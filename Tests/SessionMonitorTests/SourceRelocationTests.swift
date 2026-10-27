import CodexSource
import Foundation
import GRDB
import MonitorCore
import MonitorPolicies
import MonitorRuntime
import MonitorStore
import Testing

struct SourceRelocationTests {
    #if canImport(Darwin)
    @Test(arguments: [false, true])
    func movingUnknownSourceFolderPreservesHistoryAndAppend(missingProvenance: Bool) async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let original = fixture.url("original")
        let file = original.appending(path: "rollout.jsonl")
        try fixture.write(fixture.native + fixture.record(), to: file)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(original)
        let before = try await runtime.report()
        if missingProvenance {
            try await DatabaseQueue(path: fixture.database.path).write { database in
                try database.execute(sql: "DELETE FROM source_provenance")
            }
        }
        let moved = fixture.url("moved")
        try FileManager.default.moveItem(at: original, to: moved)
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        _ = try await restarted.importDirectory(moved)
        #expect(try await restarted.report().totals == before.totals)
        try fixture.append(fixture.record(id: "R2", input: "200"), to: moved.appending(path: "rollout.jsonl"))
        let appended = try await restarted.importDirectory(moved)
        let report = try await restarted.report()
        #expect(report.totals.requests == 2)
        #expect(report.totals.inputTokens == 300)
        #expect(appended.ioMetrics.filesResumed == 1)
        #expect(appended.records == 1)
        #expect(report.sessions.first?.model == "recovery-model")
    }
    #endif

    @Test(arguments: 0...6)
    func requiresEveryRelocationFact(scenario: Int) {
        let input = SourceRelocationInput(
            matchingSources: scenario == 1 ? 2 : 1,
            previousPathIsMissing: scenario != 2,
            previousScopeIsUnknown: scenario != 3,
            hasCheckpoint: scenario != 4,
            destinationIsUnmappedAndUnused: scenario != 5,
            parentDirectoryChanged: scenario != 6
        )
        #expect(SourceRelocationSpecification().isSatisfiedBy(input) == (scenario == 0))
    }

    @Test(arguments: [false, true])
    func copiesAndLiveHardLinksRemainSeparate(hardLink: Bool) async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let original = fixture.url("original/rollout.jsonl")
        let other = fixture.url("other/rollout.jsonl")
        try fixture.write(fixture.native + fixture.record(), to: original)
        try FileManager.default.createDirectory(
            at: other.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(original.deletingLastPathComponent())
        if hardLink {
            try FileManager.default.linkItem(at: original, to: other)
        } else {
            try FileManager.default.copyItem(at: original, to: other)
        }
        _ = try await runtime.importDirectory(other.deletingLastPathComponent())
        #expect(try await runtime.report().totals.requests == 2)
        // Previously imported scopes are not silently merged when the old path later disappears.
        try FileManager.default.removeItem(at: original)
        _ = try await runtime.importDirectory(other.deletingLastPathComponent())
        #expect(try await runtime.report().totals.requests == 2)
    }

    @Test func ambiguousIdentityNeverMergesUnknownRoots() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let original = fixture.url("a/rollout.jsonl")
        let second = fixture.url("b/rollout.jsonl")
        let moved = fixture.url("c/rollout.jsonl")
        try fixture.write(fixture.native + fixture.record(), to: original)
        for file in [second, moved] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try FileManager.default.linkItem(at: original, to: file)
        }
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        for file in [original, second] { _ = try await runtime.importDirectory(file.deletingLastPathComponent()) }
        try FileManager.default.removeItem(at: original)
        try FileManager.default.removeItem(at: second)
        _ = try await runtime.importDirectory(moved.deletingLastPathComponent())
        #expect(try await runtime.report().totals.requests == 3)
    }

    @Test(arguments: [false, true])
    func movingIntoMappedProfileNeverReattributesHistory(sourceAssigned: Bool) async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let original = fixture.url("a")
        let destination = fixture.url("b")
        try fixture.write(fixture.native + fixture.record(), to: original.appending(path: "rollout.jsonl"))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        if sourceAssigned {
            _ = try await runtime.assignAccountProfile(root: original, profileID: "a", label: "A")
        }
        _ = try await runtime.assignAccountProfile(root: destination, profileID: "b", label: "B")
        _ = try await runtime.importDirectory(original)
        try FileManager.default.moveItem(at: original, to: destination)
        _ = try await runtime.importDirectory(destination)
        let priorScope: UsageAccountScope = sourceAssigned ? UsageAccountScope(profileID: "a") : .unknownOrMixed
        for scope in [priorScope, UsageAccountScope(profileID: "b")] {
            let query = try UsageQuery(accountScope: scope)
            #expect(try await runtime.snapshot(query: query).report.totals.requests == 1)
        }
        #expect(try await runtime.report().totals.requests == 2)
    }

    #if canImport(Darwin)
    @Test func relocationPreservesQuotaScopeProjectionAndCurrentSourcePaths() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let original = fixture.url("original")
        let file = original.appending(path: "rollout.jsonl")
        let event: [String: Any] = [
            "timestamp": "1970-01-01T00:01:43Z", "type": "event_msg",
            "payload": ["type": "token_count", "rate_limits": [
                "limit_id": "synthetic", "primary": ["used_percent": 25, "window_minutes": 300, "resets_at": 20_000]
            ]]
        ]
        let quotaData = try JSONSerialization.data(withJSONObject: event)
        let quotaLine = try #require(String(data: quotaData, encoding: .utf8)) + "\n"
        try fixture.write(fixture.native + fixture.record() + quotaLine, to: file)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(original)
        let query = try UsageQuery()
        let before = try await runtime.usageLimitSnapshots(query: query)
        let oldSnapshot = try #require(before.snapshots.first)
        let oldIDs = try await runtime.timeline(sessionID: "S", query: query).points.map(\.id)
        let moved = fixture.url("moved")
        try FileManager.default.moveItem(at: original, to: moved)
        _ = try await runtime.importDirectory(moved)
        let after = try await runtime.usageLimitSnapshots(query: query)
        #expect(after.snapshots.count == 1)
        #expect(after.snapshots.first?.accountScopeID == oldSnapshot.accountScopeID)
        #expect(after.snapshots.first?.eventIdentity == oldSnapshot.eventIdentity)
        #expect(try await runtime.timeline(sessionID: "S", query: query).points.map(\.id) == oldIDs)
        let writer = try DatabaseQueue(path: fixture.database.path)
        try await writer.read { database in
            for table in ["source_records", "source_checkpoints", "source_storage", "source_provenance",
                          "source_account_scope", "source_usage_limit_snapshots", "source_context_windows",
                          "source_timeline_events", "source_diagnostics", "source_legacy_estimates"] {
                #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM \(table) WHERE source = ?",
                                         arguments: [file.path]) == 0)
            }
            let rows = try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM quota_projection_snapshots")
            #expect(rows == 1)
            #expect(try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM quota_projection_dirty") == 0)
        }
    }

    @Test func movedFileWithNewBytesResumesInOneImport() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let original = fixture.url("original")
        try fixture.write(fixture.native + fixture.record(), to: original.appending(path: "rollout.jsonl"))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(original)
        let moved = fixture.url("moved")
        try FileManager.default.moveItem(at: original, to: moved)
        try fixture.append(fixture.record(id: "R2", input: "200"), to: moved.appending(path: "rollout.jsonl"))
        let summary = try await runtime.importDirectory(moved)
        let report = try await runtime.report()
        #expect(report.totals.requests == 2 && report.totals.inputTokens == 300)
        #expect(summary.ioMetrics.filesResumed == 1 && summary.records == 1)
    }

    @Test func failedRelocationRestoresAlreadyUpdatedTables() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let original = fixture.url("original")
        let file = original.appending(path: "rollout.jsonl")
        try fixture.write(fixture.native + fixture.record(), to: file)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(original)
        let before = try await runtime.snapshot(query: UsageQuery())
        let writer = try DatabaseQueue(path: fixture.database.path)
        try await writer.write { database in
            try database.execute(sql: """
                CREATE TRIGGER fail_relocation BEFORE UPDATE OF source ON source_checkpoints
                BEGIN SELECT RAISE(ABORT, 'synthetic relocation failure'); END;
                """)
        }
        let moved = fixture.url("moved")
        try FileManager.default.moveItem(at: original, to: moved)
        await #expect(throws: (any Error).self) { _ = try await runtime.importDirectory(moved) }
        #expect(try await runtime.snapshot(query: UsageQuery()) == before)
        let store = try UsageStore(url: fixture.database)
        #expect(try store.checkpoint(source: file.path) != nil)
        #expect(try store.checkpoint(source: moved.appending(path: "rollout.jsonl").path) == nil)
        try await writer.write { try $0.execute(sql: "DROP TRIGGER fail_relocation") }
        _ = try await runtime.importDirectory(moved)
        #expect(try await runtime.report().totals == before.report.totals)
    }

    @Test func staleRelocationRollsBackEverySourceTable() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let original = fixture.url("original")
        let file = original.appending(path: "rollout.jsonl")
        try fixture.write(fixture.native + fixture.record(), to: file)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(original)
        let store = try UsageStore(url: fixture.database)
        let identity = try #require(try RolloutDecoder().relocationIdentity(file))
        let old = try #require(try store.relocationCandidates(fileIdentity: identity).first)
        try fixture.append(fixture.record(id: "R2"), to: file)
        _ = try await runtime.importDirectory(original)
        let before = try await runtime.report()
        let moved = fixture.url("moved")
        try FileManager.default.moveItem(at: original, to: moved)
        let update = try RolloutDecoder().parseIncrementally(moved.appending(path: "rollout.jsonl"),
                                                           checkpoint: old.checkpoint)
        #expect(throws: CheckpointWriteError.staleCheckpoint) {
            try store.apply(source: moved.appending(path: "rollout.jsonl").path, update: update,
                            expectedCheckpoint: old.checkpoint, relocating: old)
        }
        #expect(try await runtime.report() == before)
        #expect(try store.checkpoint(source: file.path) != nil)
        #expect(try store.checkpoint(source: moved.appending(path: "rollout.jsonl").path) == nil)
        _ = try await runtime.importDirectory(moved)
        #expect(try await runtime.report().totals == before.totals)
    }
    #endif
}
