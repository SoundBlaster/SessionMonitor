import CodexSource
import Foundation
import MonitorCore
import MonitorPolicies
import MonitorRuntime
import MonitorStore
import Testing

struct AccountingTests {
    @Test func canonicalOwnershipAndWindow() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let report = try await runtime.report()
        #expect(report.totals.requests == 1)
        #expect(report.totals.inputTokens == 100)
        #expect(report.totals.outputTokens == 10)
        #expect(report.totals.cacheHitRatio == 0.8)
        let excluded = try await runtime.report(until: Date(timeIntervalSince1970: 102))
        #expect(excluded.totals.requests == 0)
    }

    @Test func replayCannotSuppressOwner() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let replay = fixture.record(owner: "parent") + fixture.record(turn: "rollout-7")
        try fixture.write(fixture.native + replay + fixture.record())
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let report = try await runtime.report()
        #expect(report.totals.requests == 1)
        #expect(report.diagnostics["unownedOrUnprovenRecords"] == 2)
    }

    @Test func unknownTurnNeverInheritsNativeStatus() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let unknown = """
        {"timestamp":"1970-01-01T00:01:42Z","type":"event_msg","payload":{"type":"task_started","turn_id":"U"}}

        """
        try fixture.write(fixture.native + unknown + fixture.record(turn: "U"))
        #expect(try RolloutDecoder().parse(fixture.file).records.isEmpty)
    }

    @Test func repeatedImportAndConflicts() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let delayed = fixture.record().replacingOccurrences(of: "00:01:42Z", with: "00:02:13Z")
        try fixture.write(fixture.native + fixture.record() + delayed)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        _ = try await runtime.importDirectory(fixture.file)
        let same = try await runtime.report()
        #expect(same.totals.requests == 1)
        #expect(same.diagnostics["duplicateRecords"] == 1)
        try fixture.write(fixture.native + fixture.record() + fixture.record(input: "200"))
        _ = try await runtime.importDirectory(fixture.file)
        let conflict = try await runtime.report()
        #expect(conflict.totals.requests == 0)
        #expect(conflict.diagnostics["conflictingResponseIDs"] == 1)
    }

    @Test func unknownCacheAndLegacyCoverage() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let legacy = """
        {"timestamp":"1970-01-01T00:01:42Z","type":"event_msg","payload":{"type":"token_count"}}

        """
        try fixture.write(fixture.native + legacy + fixture.record(cache: "null"))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let report = try await runtime.report()
        #expect(report.totals.requests == 1)
        #expect(report.totals.unknownCacheRequests == 1)
        #expect(report.totals.cacheHitRatio == nil)
        #expect(!HasCompleteCacheCoverageSpec().isSatisfiedBy(report.totals))
        #expect(report.diagnostics["legacySnapshotsNotCounted"] == 1)
    }

    @Test(arguments: ["-1", "1.5", "\"100\"", "9223372036854775808"])
    func invalidCountsAreNotCoerced(input: String) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record(input: input))
        let result = try RolloutDecoder().parse(fixture.file)
        #expect(result.records.isEmpty)
        #expect(!result.diagnostics.isEmpty)
    }

    @Test func partialTailAndRestart() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record().dropLast())
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let pending = try await runtime.report()
        #expect(pending.totals.requests == 0)
        #expect(pending.diagnostics["partialTails"] == 1)
        try fixture.write(fixture.native + fixture.record())
        let restarted = try SessionMonitor(databaseURL: fixture.database)
        _ = try await restarted.importDirectory(fixture.file)
        #expect(try await restarted.report().totals.requests == 1)
    }

    @Test func aggregateOverflowFailsExplicitly() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record(input: "9223372036854775807", cache: "0")
                          + fixture.record(id: "R2", input: "1", cache: "0"))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        await #expect(throws: (any Error).self) { try await runtime.report() }
    }

    @Test func failedSnapshotReplacementRollsBack() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record())
        var parsed = try RolloutDecoder().parse(fixture.file)
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "source", rollout: parsed)
        parsed.records.append(try #require(parsed.records.first)) // duplicate source-line primary key
        #expect(throws: (any Error).self) { try store.replace(source: "source", rollout: parsed) }
        #expect(try store.report(since: nil, until: nil).totals.requests == 1)
    }

    @Test func malformedMetadataInvalidatesOwnership() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let corrupt = """
        {"timestamp":"1970-01-01T00:01:42Z","type":"session_meta","payload":{"id":"U","timestamp":"bad"}}

        """
        try fixture.write(fixture.native + corrupt + fixture.record(owner: "U"))
        let parsed = try RolloutDecoder().parse(fixture.file)
        #expect(parsed.records.isEmpty)
        #expect(parsed.diagnostics["malformedRecords"] == 1)
    }

    @Test func additionalCountersAndFutureVariants() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let extra = fixture.record().replacingOccurrences(
            of: "\"output_tokens\":10", with: "\"output_tokens\":10,\"reasoning_output_tokens\":7,\"total_tokens\":110"
        )
        let future = "{\"type\":\"token_usage_record_v2\"}\n"
        try fixture.write(fixture.native + extra + future)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        let report = try await runtime.report()
        #expect(report.totals.reasoningOutputTokens == 7)
        #expect(report.totals.totalTokens == 110)
        #expect(report.totals.cacheWriteInputTokens == nil)
        #expect(report.diagnostics["unknownRecordTypes"] == 1)
    }
}

private struct Fixture {
    let directory: URL
    var file: URL { directory.appending(path: "rollout.jsonl") }
    var database: URL { directory.appending(path: "usage.sqlite") }
    // Raw JSON lines intentionally preserve the on-disk framing being tested.
    // swiftlint:disable line_length
    let native = """
    {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"S","timestamp":"1970-01-01T00:01:40Z"}}
    {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"T","started_at":101}}
    {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"T","model":"fixture"}}

    """

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func record(id: String = "R", owner: String = "S", turn: String = "T",
                input: String = "100", cache: String = "80") -> String {
        """
        {"timestamp":"1970-01-01T00:01:42Z","type":"token_usage_record","payload":{"thread_id":"\(owner)","turn_id":"\(turn)","response_id":"\(id)","usage":{"input_tokens":\(input),"cached_input_tokens":\(cache),"output_tokens":10}}}

        """
    }
    // swiftlint:enable line_length

    func write(_ content: String) throws { try content.write(to: file, atomically: true, encoding: .utf8) }
    func remove() { try? FileManager.default.removeItem(at: directory) }
}
