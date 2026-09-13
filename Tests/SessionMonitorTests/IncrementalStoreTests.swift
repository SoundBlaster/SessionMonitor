@testable import CodexSource
import Foundation
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

struct IncrementalStoreTests {
    @Test(arguments: [false, true])
    func mutationDuringReadRejectsSnapshotAndAllowsRecovery(truncate: Bool) throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let initial = try RolloutDecoder().parseIncrementally(fixture.file)
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: initial, expectedCheckpoint: nil)
        let before = try store.report(since: nil, until: nil)
        let reading = try RolloutFile(url: fixture.file)
        _ = try reading.read(upToCount: 32)
        if truncate {
            try fixture.overwrite(fixture.native)
        } else {
            try fixture.append(fixture.legacy + fixture.record(id: "R2"))
        }
        #expect(throws: RolloutReadError.self) { try reading.validateSnapshot() }
        #expect(try store.checkpoint(source: fixture.source) == initial.checkpoint)
        #expect(try store.report(since: nil, until: nil) == before)
        let recovered = try RolloutDecoder().parseIncrementally(fixture.file, checkpoint: initial.checkpoint)
        try store.apply(source: fixture.source, update: recovered, expectedCheckpoint: initial.checkpoint)
        #expect(try store.report(since: nil, until: nil) == fixture.fullReport())
    }

    @Test func explicitRescanRebuildsAnUnchangedSource() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let before = try await runtime.report()
        let forced = try await runtime.importDirectory(fixture.file, rescan: true)
        #expect(forced.ioMetrics.filesRescanned == 1)
        #expect(forced.ioMetrics.filesSkipped == 0)
        #expect(forced.ioMetrics.bytesRead > 0)
        #expect(try await runtime.report() == before)
    }

    @Test(arguments: [false, true])
    func failedBatchRollsBackRecordsDiagnosticsAndCheckpoint(replacement: Bool) throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let decoder = RolloutDecoder()
        let initial = try decoder.parseIncrementally(fixture.file)
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: initial, expectedCheckpoint: nil)
        let before = try store.report(since: nil, until: nil)
        if replacement {
            try fixture.write(fixture.native + fixture.legacy + fixture.record(id: "R2"))
        } else {
            try fixture.append(fixture.legacy + fixture.record(id: "R2"))
        }
        let update = try decoder.parseIncrementally(fixture.file, checkpoint: initial.checkpoint)
        #expect(update.mode == (replacement ? .replaced : .appended))
        var invalid = update.rollout
        invalid.records.append(try #require(invalid.records.first))
        let failed = SourceImport(rollout: invalid, checkpoint: update.checkpoint,
                                  mode: update.mode, bytesRead: update.bytesRead)
        #expect(throws: (any Error).self) {
            try store.apply(source: fixture.source, update: failed, expectedCheckpoint: initial.checkpoint)
        }
        #expect(try store.checkpoint(source: fixture.source) == initial.checkpoint)
        #expect(try store.report(since: nil, until: nil) == before)
    }

    @Test func staleCheckpointRejectsOtherwiseValidUniqueRows() throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let decoder = RolloutDecoder()
        let first = try decoder.parseIncrementally(fixture.file)
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: first, expectedCheckpoint: nil)
        try fixture.append(fixture.record(id: "R2"))
        let second = try decoder.parseIncrementally(fixture.file, checkpoint: first.checkpoint)
        try store.apply(source: fixture.source, update: second, expectedCheckpoint: first.checkpoint)
        let before = try store.report(since: nil, until: nil)
        try fixture.append(fixture.record(id: "R3"))
        let third = try decoder.parseIncrementally(fixture.file, checkpoint: second.checkpoint)
        #expect(throws: (any Error).self) {
            try store.apply(source: fixture.source, update: third, expectedCheckpoint: first.checkpoint)
        }
        #expect(try store.checkpoint(source: fixture.source) == second.checkpoint)
        #expect(try store.report(since: nil, until: nil) == before)
        try store.apply(source: fixture.source, update: third, expectedCheckpoint: second.checkpoint)
        #expect(try store.report(since: nil, until: nil).totals.requests == 3)
    }

    @Test(arguments: [false, true])
    func invalidStoredCheckpointForcesReplacement(unknownVersion: Bool) async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let initial = try RolloutDecoder().parseIncrementally(fixture.file)
        var object = try #require(JSONSerialization.jsonObject(with: initial.checkpoint) as? [String: Any])
        object["schemaVersion"] = 999
        let invalid = unknownVersion ? try JSONSerialization.data(withJSONObject: object) : Data("invalid".utf8)
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: SourceImport(
            rollout: initial.rollout, checkpoint: invalid, mode: .replaced, bytesRead: initial.bytesRead
        ), expectedCheckpoint: nil)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let result = try await runtime.importDirectory(fixture.file)
        #expect(result.ioMetrics.filesRescanned == 1)
        #expect(try store.checkpoint(source: fixture.source) != invalid)
        #expect(try await runtime.report() == fixture.fullReport())
    }

    @Test func schemaOneCheckpointRescansOnceThenAppendsAfterRestart() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let original = fixture.native + fixture.record()
        try fixture.write(original)
        let initial = try RolloutDecoder().parseIncrementally(fixture.file)
        var object = try #require(JSONSerialization.jsonObject(with: initial.checkpoint) as? [String: Any])
        object["schemaVersion"] = 1
        object["prefixDigest"] = Data(repeating: 0, count: 32).base64EncodedString()
        let legacy = try JSONSerialization.data(withJSONObject: object)
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: SourceImport(
            rollout: initial.rollout, checkpoint: legacy, mode: .replaced, bytesRead: initial.bytesRead
        ), expectedCheckpoint: nil)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let migrated = try await runtime.importDirectory(fixture.file)
        #expect(migrated.ioMetrics.filesRescanned == 1)
        #expect(migrated.ioMetrics.filesSkipped == 0)
        #expect(migrated.ioMetrics.bytesRead == UInt64(original.utf8.count))
        let current = try #require(try store.checkpoint(source: fixture.source))
        let currentObject = try #require(JSONSerialization.jsonObject(with: current) as? [String: Any])
        #expect(currentObject["schemaVersion"] as? Int == 3)
        #expect(currentObject["prefixDigest"] == nil)
        let appended = fixture.record(id: "R2")
        try fixture.append(appended)
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        let update = try await restarted.importDirectory(fixture.file)
        #expect(update.ioMetrics.filesResumed == 1)
        #expect(update.ioMetrics.filesRescanned == 0)
        #expect(update.ioMetrics.bytesRead == UInt64(appended.utf8.count))
        #expect(try await restarted.report() == fixture.fullReport())
    }

    @Test func legacyReplacementClearsCheckpointAndReimportsWithoutDuplicates() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let store = try UsageStore(url: fixture.database)
        let initial = try RolloutDecoder().parseIncrementally(fixture.file)
        try store.apply(source: fixture.source, update: initial, expectedCheckpoint: nil)
        try store.replace(source: fixture.source, rollout: initial.rollout)
        #expect(try store.checkpoint(source: fixture.source) == nil)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let update = try await runtime.importDirectory(fixture.file)
        #expect(update.ioMetrics.filesRescanned == 1)
        #expect(try store.checkpoint(source: fixture.source) != nil)
        let report = try await runtime.report()
        #expect(report.totals.requests == 1)
        #expect(report.diagnostics["duplicateRecords", default: 0] == 0)
    }
}
