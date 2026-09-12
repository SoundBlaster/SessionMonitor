@testable import CodexSource
import Foundation
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

struct IncrementalImportTests {
    @Test(arguments: [false, true])
    func unchangedFilesSkipBodyAfterRestart(partialTail: Bool) async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let tail = partialTail ? "{\"private\":\"unfinished-marker" : ""
        try fixture.write(fixture.native + fixture.record() + tail)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let first = try await runtime.importDirectory(fixture.file)
        let before = try await runtime.report()
        #expect(first.ioMetrics.bytesRead > 0)
        let store = try UsageStore(url: fixture.database)
        let checkpoint = try #require(try store.checkpoint(source: fixture.source))
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        let skipped = try await restarted.importDirectory(fixture.file)
        #expect(skipped.files == 1)
        #expect(skipped.records == 0)
        #expect(skipped.ioMetrics.bytesRead == 0)
        #expect(skipped.ioMetrics.filesSkipped == 1)
        #expect(skipped.ioMetrics.filesResumed == 0)
        #expect(skipped.ioMetrics.filesRescanned == 0)
        #expect(try await restarted.report() == before)
        #expect(try store.checkpoint(source: fixture.source) == checkpoint)
    }

    @Test func realAppendPreservesOwnershipModelsAndAccountingAfterRestart() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.legacy + fixture.record(cache: "null"))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let appended = fixture.record(id: "R2")
        try fixture.append(appended)
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        let update = try await restarted.importDirectory(fixture.file)
        let report = try await restarted.report()
        #expect(update.records == 1)
        #expect(update.ioMetrics.filesResumed == 1)
        #expect(update.ioMetrics.bytesRead >= UInt64(appended.utf8.count))
        #expect(report.totals.requests == 2)
        #expect(report.totals.unknownCacheRequests == 1)
        #expect(report.sessions.first?.model == "fixture-model")
        #expect(report.diagnostics["legacySnapshotsNotCounted"] == 1)
        #expect(report == (try fixture.fullReport()))
        try fixture.append(fixture.record(id: "R2") + fixture.record(id: "R2", input: "200"))
        _ = try await restarted.importDirectory(fixture.file)
        let conflict = try await restarted.report()
        #expect(conflict.totals.requests == 1)
        #expect(conflict.diagnostics["duplicateRecords"] == 1)
        #expect(conflict.diagnostics["conflictingResponseIDs"] == 1)
        #expect(conflict == (try fixture.fullReport()))
    }

    @Test func partialUTF8RequiresNewlineAndDoesNotPersistRawTail() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let marker = "private-prompt-marker-🌒"
        let record = fixture.record().replacingOccurrences(of: "\"usage\":", with: "\"note\":\"\(marker)\",\"usage\":")
        let bytes = Data(record.utf8)
        let split = try #require(bytes.firstIndex(of: 0xF0)) + 2
        try fixture.write(fixture.native)
        try fixture.append(Data(bytes.prefix(split)))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let store = try UsageStore(url: fixture.database)
        let checkpoint = try #require(try store.checkpoint(source: fixture.source))
        let checkpointText = try #require(String(data: checkpoint, encoding: .utf8))
        #expect(!checkpointText.contains("private-prompt-marker"))
        #expect(!checkpointText.contains(Data(bytes.prefix(split)).base64EncodedString()))
        #expect(try await runtime.report().totals.requests == 0)
        try fixture.append(Data(bytes.dropFirst(split).dropLast()))
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        _ = try await restarted.importDirectory(fixture.file)
        #expect(try await restarted.report().totals.requests == 0)
        #expect(try await restarted.report().diagnostics["partialTails"] == 1)
        try fixture.append("\n")
        let completed = try RolloutDecoder().parseIncrementally(
            fixture.file, checkpoint: store.checkpoint(source: fixture.source)
        )
        #expect(completed.mode == .appended)
        #expect(completed.rollout.records.first?.sourceLine == 4)
        _ = try await restarted.importDirectory(fixture.file)
        let report = try await restarted.report()
        #expect(report.totals.requests == 1)
        #expect(report.diagnostics["partialTails", default: 0] == 0)
        #expect(report == (try fixture.fullReport()))
    }

    @Test func oversizedPartialLineIsCountedOnceWhenCompleted() throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + String(repeating: "x", count: 16 * 1_024 * 1_024 + 1))
        let decoder = RolloutDecoder()
        let initial = try decoder.parseIncrementally(fixture.file)
        #expect(initial.rollout.diagnostics["partialTails"] == 1)
        #expect(initial.rollout.diagnostics["oversizedLines", default: 0] == 0)
        try fixture.append("\n" + fixture.record())
        let completed = try decoder.parseIncrementally(fixture.file, checkpoint: initial.checkpoint)
        #expect(completed.mode == .appended)
        #expect(completed.rollout.records.first?.sourceLine == 5)
        #expect(completed.rollout.diagnostics["oversizedLines"] == 1)
        let unchanged = try decoder.parseIncrementally(fixture.file, checkpoint: completed.checkpoint)
        #expect(unchanged.mode == .unchanged)
        #expect(unchanged.bytesRead == 0)
    }

    @Test func ignoredAndMalformedLinesKeepAbsoluteSourcePositions() throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let skipped = "broken\n{\"type\":\"future_record\"}\n{\"type\":\"response_item\"}\n"
        try fixture.write(fixture.native + skipped)
        let decoder = RolloutDecoder()
        let initial = try decoder.parseIncrementally(fixture.file)
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: initial, expectedCheckpoint: nil)
        try fixture.append("\n" + fixture.record())
        let update = try decoder.parseIncrementally(fixture.file, checkpoint: initial.checkpoint)
        #expect(update.rollout.records.first?.sourceLine == 8)
        try store.apply(source: fixture.source, update: update, expectedCheckpoint: initial.checkpoint)
        let report = try store.report(since: nil, until: nil)
        #expect(report.diagnostics["malformedRecords"] == 2)
        #expect(report.diagnostics["unknownRecordTypes"] == 1)
        #expect(report == (try fixture.fullReport()))
    }

    @Test(arguments: [false, true])
    func checkpointOnlyChangesInvalidateOwnership(malformedMetadata: Bool) async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        try fixture.append(malformedMetadata ? fixture.malformedMetadata : fixture.unprovenStart)
        let changed = try await runtime.importDirectory(fixture.file)
        #expect(changed.records == 0)
        #expect(changed.ioMetrics.filesResumed == 1)
        try fixture.append(fixture.record())
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        _ = try await restarted.importDirectory(fixture.file)
        let report = try await restarted.report()
        #expect(report.totals.requests == 0)
        #expect(report.diagnostics["unownedOrUnprovenRecords"] == 1)
        #expect(report.diagnostics["malformedRecords", default: 0] == (malformedMetadata ? 1 : 0))
        #expect(report == (try fixture.fullReport()))
    }

    @Test(arguments: RecoveryChange.allCases)
    func changedSourcesRescanAndMatchFullParse(change: RecoveryChange) async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let original = fixture.native + fixture.record() + fixture.record(id: "R2")
        try fixture.write(original)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let modified = original.replacingOccurrences(of: "\"input_tokens\":100", with: "\"input_tokens\":200")
        switch change {
        case .identity: try fixture.write(modified)
        case .shrink: try fixture.overwrite(fixture.native + fixture.record(input: "200"))
        case .sameSize: try fixture.overwrite(modified)
        case .rewriteAndGrowth: try fixture.overwrite(modified + fixture.record(id: "R3"))
        }
        let update = try await runtime.importDirectory(fixture.file)
        #expect(update.ioMetrics.filesRescanned == 1)
        #expect(update.ioMetrics.filesResumed == 0)
        #expect(try await runtime.report() == fixture.fullReport())
    }
}

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

enum RecoveryChange: CaseIterable, Sendable {
    case identity, shrink, sameSize, rewriteAndGrowth
}

private struct IncrementalFixture {
    let directory: URL
    var file: URL { directory.appending(path: "rollout.jsonl") }
    var database: URL { directory.appending(path: "usage.sqlite") }
    var source: String { file.resolvingSymlinksInPath().path }
    // Raw synthetic JSON keeps byte framing and invalid records explicit.
    // swiftlint:disable line_length
    let native = """
    {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"S","timestamp":"1970-01-01T00:01:40Z"}}
    {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"T","started_at":101}}
    {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"T","model":"fixture-model"}}

    """
    let legacy = "{\"timestamp\":\"1970-01-01T00:01:42Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\"}}\n"
    let malformedMetadata = "{\"timestamp\":\"1970-01-01T00:01:42Z\",\"type\":\"session_meta\",\"payload\":{\"id\":\"S\",\"timestamp\":\"bad\"}}\n"
    let unprovenStart = "{\"timestamp\":\"1970-01-01T00:01:42Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"T\"}}\n"

    func record(id: String = "R", input: String = "100", cache: String = "80") -> String {
        "{\"timestamp\":\"1970-01-01T00:01:42Z\",\"type\":\"token_usage_record\",\"payload\":{\"thread_id\":\"S\",\"turn_id\":\"T\",\"response_id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":\(cache),\"output_tokens\":10}}}\n"
    }
    // swiftlint:enable line_length

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ content: String) throws { try Data(content.utf8).write(to: file, options: .atomic) }

    func append(_ content: String) throws { try append(Data(content.utf8)) }

    func append(_ data: Data) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: data)
    }

    func overwrite(_ content: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        let bytes = Data(content.utf8)
        try handle.write(contentsOf: bytes)
        try handle.truncate(atOffset: UInt64(bytes.count))
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 200)],
                                              ofItemAtPath: file.path)
    }

    func fullReport() throws -> UsageReport {
        let store = try UsageStore(url: directory.appending(path: "full-parse.sqlite"))
        try store.replace(source: source, rollout: RolloutDecoder().parse(file))
        return try store.report(since: nil, until: nil)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
