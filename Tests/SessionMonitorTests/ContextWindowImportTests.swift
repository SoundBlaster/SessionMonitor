@testable import CodexSource
import Foundation
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

/// SM-727: the usable context window Codex reports in the `token_count` that follows a usage record.
struct ContextWindowImportTests {
    @Test func attachesTheReportedWindowToTheRequestItFollows() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native
            + fixture.record(id: "R1", input: "100") + tokenCount(window: 258_400, lastInput: 100)
            + fixture.record(id: "R2", input: "120") + tokenCount(window: 475_000, lastInput: 120))

        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)

        #expect(try await windows(runtime) == [258_400, 475_000])
    }

    @Test func leavesTheWindowUnknownWithoutAMatchingTokenCount() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        // A window before any record, a record followed directly by the next record, and a reset snapshot
        // (`last_token_usage` of 0) that does not describe the preceding response.
        try fixture.write(fixture.native + tokenCount(window: 258_400, lastInput: 100)
            + fixture.record(id: "R1", input: "100")
            + fixture.record(id: "R2", input: "120") + tokenCount(window: 258_400, lastInput: 0))

        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)

        #expect(try await windows(runtime) == [nil, nil])
    }

    @Test func pairsAWindowThatArrivesInALaterImport() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.native + fixture.record(id: "R1", input: "100"))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        #expect(try await windows(runtime) == [nil])

        try fixture.append(tokenCount(window: 258_400, lastInput: 100))
        _ = try await runtime.importDirectory(fixture.file)

        #expect(try await windows(runtime) == [258_400])
    }

    @Test func previousDecoderCheckpointRescansOnceToBackfillWindowsWithoutChangingTotals() async throws {
        let fixture = try IncrementalFixture()
        defer { fixture.remove() }
        let source = fixture.native + fixture.record(id: "R1", input: "100")
            + tokenCount(window: 258_400, lastInput: 100)
        try fixture.write(source)
        let parsed = try RolloutDecoder().parseIncrementally(fixture.file)
        var oldCheckpoint = try #require(JSONSerialization.jsonObject(with: parsed.checkpoint) as? [String: Any])
        oldCheckpoint["schemaVersion"] = 4
        var existing = parsed.rollout
        existing.contextWindows = []
        let store = try UsageStore(url: fixture.database)
        try store.apply(source: fixture.source, update: SourceImport(
            rollout: existing, checkpoint: try JSONSerialization.data(withJSONObject: oldCheckpoint),
            mode: .replaced, bytesRead: parsed.bytesRead
        ), expectedCheckpoint: nil)
        let before = try store.report(since: nil, until: nil)

        let runtime = try SessionMonitor(databaseURL: fixture.database)
        #expect(try await windows(runtime) == [nil])
        let imported = try await runtime.importDirectory(fixture.file)

        #expect(imported.ioMetrics.filesRescanned == 1)
        #expect(try await runtime.report() == before)
        #expect(try await windows(runtime) == [258_400])
        let repeated = try await runtime.importDirectory(fixture.file)
        #expect(repeated.ioMetrics.bytesRead == 0)
    }

    private func windows(_ runtime: SessionMonitor) async throws -> [Int64?] {
        try await runtime.timeline(sessionID: "S", query: UsageQuery()).points
            .filter { $0.kind == .usageRequest }
            .map(\.contextWindowTokens)
    }

    private func tokenCount(window: Int64, lastInput: Int64) -> String {
        let usage = "{\"input_tokens\":\(lastInput),\"cached_input_tokens\":0,\"output_tokens\":10,"
            + "\"total_tokens\":\(lastInput + 10)}"
        return "{\"timestamp\":\"1970-01-01T00:01:42Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"token_count\","
            + "\"info\":{\"total_token_usage\":\(usage),\"last_token_usage\":\(usage),"
            + "\"model_context_window\":\(window)}}}\n"
    }
}
