import Foundation
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

struct SourceRecoveryTests {
    @Test func renameRestartAndAppendKeepCanonicalAccounting() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record(), to: fixture.active)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        let before = try await runtime.report()
        let renamed = fixture.url("renamed.jsonl")
        try FileManager.default.moveItem(at: fixture.active, to: renamed)
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        _ = try await restarted.importDirectory(fixture.directory)
        let afterRename = try await restarted.report()
        #expect(afterRename.totals == before.totals)
        #expect(afterRename.diagnostics["duplicateRecords"] == 1)
        let unchanged = try await restarted.importDirectory(fixture.directory)
        #expect(unchanged.ioMetrics.bytesRead == 0)
        #expect(unchanged.ioMetrics.filesSkipped == 1)
        #expect(try await restarted.report() == afterRename)
        try fixture.append(fixture.record(id: "R2"), to: renamed)
        let appended = try await restarted.importDirectory(fixture.directory)
        let final = try await restarted.report()
        #expect(appended.ioMetrics.filesResumed == 1)
        #expect(appended.records == 1)
        #expect(final.totals.requests == 2)
        #expect(final.totals.inputTokens == 200)
        #expect(final.sessions.first?.model == "recovery-model")
        #expect(final.diagnostics["duplicateRecords"] == 1)
    }

    @Test(arguments: ["a-archive.jsonl.1", "z-archive.jsonl.10"])
    func rotationPreservesUnionRegardlessOfPathOrder(archiveName: String) async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record(), to: fixture.active)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        try FileManager.default.moveItem(at: fixture.active, to: fixture.url(archiveName))
        try fixture.write(fixture.native + fixture.record(id: "R2"), to: fixture.active)
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        let imported = try await restarted.importDirectory(fixture.directory)
        let report = try await restarted.report()
        #expect(imported.files == 2)
        #expect(imported.ioMetrics.filesRescanned == 2)
        #expect(report.totals.requests == 2)
        #expect(report.totals.inputTokens == 200)
        #expect(report.totals.cachedInputTokens == 160)
        #expect(report.diagnostics["duplicateRecords"] == 0)
        let unchanged = try await restarted.importDirectory(fixture.directory)
        #expect(unchanged.ioMetrics.bytesRead == 0)
        #expect(unchanged.ioMetrics.filesSkipped == 2)
        #expect(try await restarted.report() == report)
    }

    @Test func copytruncateRetainsArchiveAndAccountsForNewAppend() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record(), to: fixture.active)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        try FileManager.default.copyItem(at: fixture.active, to: fixture.url("archive.jsonl.1"))
        try fixture.truncate(fixture.native, at: fixture.active)
        _ = try await runtime.importDirectory(fixture.directory)
        #expect(try await runtime.report().totals.requests == 1)
        try fixture.append(fixture.record(id: "R2"), to: fixture.active)
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        let imported = try await restarted.importDirectory(fixture.directory)
        let report = try await restarted.report()
        #expect(imported.ioMetrics.filesResumed == 1)
        #expect(imported.ioMetrics.filesSkipped == 1)
        #expect(report.totals.requests == 2)
        #expect(report.totals.inputTokens == 200)
        #expect(report.diagnostics["duplicateRecords"] == 0)
    }

    @Test func discoveryIncludesOnlyVisibleJSONLAndNumericArchives() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let included = ["active.jsonl", "rollout.jsonl.1", "rollout.jsonl.001", "nested/archive.jsonl.42"]
        let excluded = [
            "rollout.jsonl.gz", "rollout.jsonl.1.gz", "rollout.jsonl.bak", "rollout.jsonl.foo",
            "rollout.jsonl.1.bak", "rollout.jsonl.1x", "rollout.jsonl.-1", "rollout.jsonl.١",
            ".hidden.jsonl", ".hidden.jsonl.1", ".private/inside.jsonl", "unrelated.txt"
        ]
        for (index, path) in (included + excluded).enumerated() {
            try fixture.write(fixture.native + fixture.record(id: "R\(index)"), to: fixture.url(path))
        }
        try FileManager.default.createDirectory(at: fixture.url("directory.jsonl.9"),
                                                withIntermediateDirectories: true)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        let imported = try await runtime.importDirectory(fixture.directory)
        #expect(imported.files == included.count)
        #expect(imported.records == included.count)
        #expect(try await runtime.report().totals.requests == Int64(included.count))
        #expect(imported.diagnostics.isEmpty)
    }

    @Test(arguments: [false, true])
    func redeliveryDeduplicatesOrQuarantinesConflictingUsage(conflict: Bool) async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record(), to: fixture.active)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        let before = try await runtime.report()
        let delivered = fixture.record(input: conflict ? "200" : "100")
            .replacingOccurrences(of: "00:01:42Z", with: "00:02:13Z")
        try fixture.write(fixture.native + delivered, to: fixture.url("redelivered.jsonl"))
        _ = try await runtime.importDirectory(fixture.directory)
        let report = try await runtime.report()
        if conflict {
            #expect(report.totals.requests == 0)
            #expect(report.totals.inputTokens == 0)
        } else {
            #expect(report.totals == before.totals)
        }
        #expect(report.diagnostics["conflictingResponseIDs"] == (conflict ? 1 : 0))
        #expect(report.diagnostics["duplicateRecords"] == (conflict ? 0 : 1))
        let early = try await runtime.report(until: Date(timeIntervalSince1970: 103))
        #expect(early.totals.requests == (conflict ? 0 : 1))
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        let unchanged = try await restarted.importDirectory(fixture.directory)
        #expect(unchanged.ioMetrics.bytesRead == 0)
        #expect(unchanged.ioMetrics.filesSkipped == 2)
        #expect(try await restarted.report() == report)
    }

    @Test(arguments: [false, true])
    func replacementAndTruncationResetOwnership(replacement: Bool) async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record(), to: fixture.active)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        if replacement {
            try fixture.write(fixture.record(id: "R2"), to: fixture.active)
        } else {
            try fixture.truncate(fixture.record(id: "R2"), at: fixture.active)
        }
        let recovered = try await runtime.importDirectory(fixture.directory)
        let report = try await runtime.report()
        #expect(recovered.ioMetrics.filesRescanned == 1)
        #expect(report.totals.requests == 0)
        #expect(report.sessions.isEmpty)
        #expect(report.diagnostics["unownedOrUnprovenRecords"] == 1)
        try fixture.append(fixture.native + fixture.record(id: "R3"), to: fixture.active)
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        _ = try await restarted.importDirectory(fixture.directory)
        let fresh = try await restarted.report()
        #expect(fresh.totals.requests == 1)
        #expect(fresh.sessions.first?.model == "recovery-model")
        #expect(fresh.diagnostics["unownedOrUnprovenRecords"] == 1)
    }

    @Test func partialRenameKeepsObservedOldTailWhileCompletingNewPathOnce() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record().dropLast(), to: fixture.active)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        #expect(try await runtime.report().diagnostics["partialTails"] == 1)
        let renamed = fixture.url("renamed.jsonl")
        try FileManager.default.moveItem(at: fixture.active, to: renamed)
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        _ = try await restarted.importDirectory(fixture.directory)
        #expect(try await restarted.report().totals.requests == 0)
        #expect(try await restarted.report().diagnostics["partialTails"] == 2)
        try fixture.append("\n", to: renamed)
        _ = try await restarted.importDirectory(fixture.directory)
        let completed = try await restarted.report()
        #expect(completed.totals.requests == 1)
        #expect(completed.diagnostics["partialTails"] == 1) // The absent old path retains its last observation.
        #expect(completed.diagnostics["duplicateRecords"] == 0)
        let unchanged = try await restarted.importDirectory(fixture.directory)
        #expect(unchanged.ioMetrics.bytesRead == 0)
        #expect(try await restarted.report() == completed)
    }

    @Test func missingSourceIsRetainedButReplacingExistingPathOverwritesItsSnapshot() async throws {
        let fixture = try RecoveryFixture()
        defer { fixture.remove() }
        let removed = fixture.url("removed.jsonl")
        try fixture.write(fixture.native + fixture.record(), to: fixture.active)
        try fixture.write(fixture.native + fixture.record(id: "R2"), to: removed)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        let store = try UsageStore(url: fixture.database)
        let source = removed.resolvingSymlinksInPath().path
        let checkpoint = try #require(try store.checkpoint(source: source))
        try FileManager.default.removeItem(at: removed)
        _ = try await runtime.importDirectory(fixture.directory)
        #expect(try await runtime.report().totals.requests == 2)
        try fixture.write(fixture.native + fixture.record(id: "R3", input: "200"), to: fixture.active)
        _ = try await runtime.importDirectory(fixture.directory)
        let report = try await runtime.report()
        #expect(report.totals.requests == 2)
        #expect(report.totals.inputTokens == 300)
        #expect(try store.checkpoint(source: source) == checkpoint)
    }
}

private struct RecoveryFixture {
    let directory: URL
    var active: URL { url("m-active.jsonl") }
    var database: URL { url("usage.sqlite") }
    // Synthetic JSON preserves the exact framing and ownership evidence under test.
    // swiftlint:disable line_length
    let native = """
    {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"S","timestamp":"1970-01-01T00:01:40Z"}}
    {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"T","started_at":101}}
    {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"T","model":"recovery-model"}}

    """

    func record(id: String = "R", input: String = "100") -> String {
        "{\"timestamp\":\"1970-01-01T00:01:42Z\",\"type\":\"token_usage_record\",\"payload\":{\"thread_id\":\"S\",\"turn_id\":\"T\",\"response_id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":80,\"output_tokens\":10}}}\n"
    }
    // swiftlint:enable line_length

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func url(_ path: String) -> URL { directory.appending(path: path) }

    func write(_ content: String, to file: URL) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(content.utf8).write(to: file, options: .atomic)
    }

    func append(_ content: String, to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(content.utf8))
    }

    func truncate(_ content: String, at file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data(content.utf8))
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
