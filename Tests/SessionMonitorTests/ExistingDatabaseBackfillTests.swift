@testable import CodexSource
import Foundation
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

struct ExistingDatabaseBackfillTests {
    @Test func existingSchemaTwoCheckpointBackfillsProvenanceWithoutChangingTotals() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let quotaFixture = try UsageLimitFixture()
        defer { quotaFixture.remove() }
        let quotaEvent = try quotaFixture.jsonlEvent(timestamp: "1970-01-01T00:01:43Z", rateLimits: [
            "limit_id": "fixture-limit",
            "primary": ["used_percent": 82, "resets_at": 200_000, "window_minutes": 300]
        ])
        let source = fixture.native + fixture.record() + quotaEvent
        try fixture.write(source)
        let decoder = RolloutDecoder()
        let initial = try decoder.parseIncrementally(fixture.file)
        var checkpointObject = try #require(JSONSerialization.jsonObject(with: initial.checkpoint) as? [String: Any])
        checkpointObject["schemaVersion"] = 2
        let schemaTwoCheckpoint = try JSONSerialization.data(withJSONObject: checkpointObject)
        var existing = initial.rollout
        existing.provenance = nil
        existing.usageLimitSnapshots = []
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source,
                        update: SourceImport(rollout: existing, checkpoint: schemaTwoCheckpoint,
                                             mode: .replaced, bytesRead: initial.bytesRead),
                        expectedCheckpoint: nil)
        let before = try store.report(since: nil, until: nil)

        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let backfilled = try await runtime.importDirectory(fixture.file)
        let after = try await runtime.report()
        let snapshot = try await runtime.snapshot(query: UsageQuery())
        let quota = try await runtime.usageLimitSnapshots(query: UsageQuery())

        #expect(after == before)
        #expect(snapshot.provenance["S"]?.sessionID == "S")
        #expect(backfilled.records == 0)
        #expect(backfilled.ioMetrics.bytesRead == UInt64(source.utf8.count))
        #expect(backfilled.ioMetrics.filesRescanned == 0)
        #expect(backfilled.ioMetrics.filesSkipped == 1)
        #expect(quota.snapshots.count == 1)
        #expect(quota.snapshots[0].windows[0].usedPercent == 82)
        let current = try #require(try store.checkpoint(source: fixture.source))
        let currentObject = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        #expect(currentObject["schemaVersion"] as? Int == 4)
    }

    @Test func oldCheckpointRescansOnceToBackfillQuotaSnapshotsWithoutChangingTotals() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let quotaFixture = try UsageLimitFixture()
        defer { quotaFixture.remove() }
        let quotaEvent = try quotaFixture.jsonlEvent(timestamp: "1970-01-01T00:01:43Z", rateLimits: [
            "limit_id": "fixture-limit",
            "primary": ["used_percent": 82, "resets_at": 200_000, "window_minutes": 300]
        ])
        let source = fixture.native + fixture.record() + quotaEvent
        try fixture.write(source)
        let parsed = try RolloutDecoder().parseIncrementally(fixture.file)
        #expect(parsed.rollout.usageLimitSnapshots.count == 1)

        var oldCheckpoint = try #require(JSONSerialization.jsonObject(with: parsed.checkpoint) as? [String: Any])
        oldCheckpoint["schemaVersion"] = 3
        var existing = parsed.rollout
        existing.usageLimitSnapshots = []
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: SourceImport(
            rollout: existing,
            checkpoint: try JSONSerialization.data(withJSONObject: oldCheckpoint),
            mode: .replaced,
            bytesRead: parsed.bytesRead
        ), expectedCheckpoint: nil)
        let before = try store.report(since: nil, until: nil)
        #expect(before.totals.requests == 1)

        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let imported = try await runtime.importDirectory(fixture.file)
        let after = try await runtime.report()
        let quota = try await runtime.usageLimitSnapshots(query: UsageQuery())

        #expect(imported.ioMetrics.filesRescanned == 1)
        #expect(imported.ioMetrics.bytesRead == UInt64(source.utf8.count))
        #expect(after == before)
        #expect(quota.snapshots.count == 1)
        #expect(quota.snapshots[0].windows[0].usedPercent == 82)
    }

    @Test func provenanceBackfillIsIdempotent() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let decoder = RolloutDecoder()
        let initial = try decoder.parseIncrementally(fixture.file)
        var existing = initial.rollout
        existing.provenance = nil
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source,
                        update: SourceImport(rollout: existing, checkpoint: initial.checkpoint,
                                             mode: .replaced, bytesRead: initial.bytesRead),
                        expectedCheckpoint: nil)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let checkpoint = try #require(try store.checkpoint(source: fixture.source))
        let first = try await runtime.snapshot(query: UsageQuery())

        let repeated = try await runtime.importDirectory(fixture.file)
        let second = try await runtime.snapshot(query: UsageQuery())

        #expect(repeated.ioMetrics.bytesRead == 0)
        #expect(repeated.ioMetrics.filesSkipped == 1)
        #expect(try store.checkpoint(source: fixture.source) == checkpoint)
        #expect(second == first)
    }

    @Test func missingRolloutLeavesExistingProvenanceAbsentAndSnapshotUsable() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let decoder = RolloutDecoder()
        let initial = try decoder.parseIncrementally(fixture.file)
        var existing = initial.rollout
        existing.provenance = nil
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source,
                        update: SourceImport(rollout: existing, checkpoint: initial.checkpoint,
                                             mode: .replaced, bytesRead: initial.bytesRead),
                        expectedCheckpoint: nil)
        let before = try store.report(since: nil, until: nil)
        try FileManager.default.removeItem(at: fixture.file)

        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let summary = try await runtime.importDirectory(fixture.directory)
        let snapshot = try await runtime.snapshot(query: UsageQuery())

        #expect(summary.files == 0)
        #expect(snapshot.report.totals == before.totals)
        #expect(snapshot.provenance.isEmpty)
    }
}
