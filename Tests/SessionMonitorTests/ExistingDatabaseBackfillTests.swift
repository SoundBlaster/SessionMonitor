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
        try fixture.write(fixture.native + fixture.record())
        let decoder = RolloutDecoder()
        let initial = try decoder.parseIncrementally(fixture.file)
        var checkpointObject = try #require(JSONSerialization.jsonObject(with: initial.checkpoint) as? [String: Any])
        checkpointObject["schemaVersion"] = 2
        let schemaTwoCheckpoint = try JSONSerialization.data(withJSONObject: checkpointObject)
        var existing = initial.rollout
        existing.provenance = nil
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

        #expect(after == before)
        #expect(snapshot.provenance["S"]?.sessionID == "S")
        #expect(backfilled.records == 0)
        #expect(backfilled.ioMetrics.bytesRead == UInt64((fixture.native + fixture.record()).utf8.count))
        #expect(backfilled.ioMetrics.filesRescanned == 0)
        #expect(backfilled.ioMetrics.filesSkipped == 1)
        let current = try #require(try store.checkpoint(source: fixture.source))
        let currentObject = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        #expect(currentObject["schemaVersion"] as? Int == 3)
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
