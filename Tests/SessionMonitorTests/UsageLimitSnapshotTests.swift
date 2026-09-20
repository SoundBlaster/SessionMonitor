import CodexSource
import Foundation
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

struct UsageLimitSnapshotTests {
    @Test func decodesObservedPrimaryWindowWithoutClaimingScope() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.event(timestamp: "2026-09-20T10:00:00Z", used: 82))

        let parsed = try RolloutDecoder().parse(fixture.file)
        let snapshot = try #require(parsed.usageLimitSnapshots.first)
        let window = try #require(snapshot.windows.first)
        #expect(parsed.usageLimitSnapshots.count == 1)
        #expect(snapshot.adapterVersion == 1)
        #expect(snapshot.sourceSchema == "codex.event_msg.token_count.rate_limits")
        #expect(snapshot.state == .observed)
        #expect(snapshot.scope == .unknown)
        #expect(snapshot.limitID == "fixture-limit")
        #expect(window.slot == .primary)
        #expect(window.windowKind == .fiveHour)
        #expect(window.usedPercent == 82)
        #expect(window.remainingPercentDerived == 18)
        #expect(window.resetsAt == Date(timeIntervalSince1970: 1_790_422_316))
        #expect(parsed.diagnostics["unsupportedUsageLimitSchemas"] == nil)
    }

    @Test func missingSnapshotsRemainUnknownAndUnsupportedSchemasAreRecorded() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let missing = """
        {"timestamp":"2026-09-20T10:00:00Z","type":"event_msg","payload":{"type":"token_count"}}
        """
        try fixture.write(missing + "\n" + fixture.unsupportedEvent + "\n")

        let parsed = try RolloutDecoder().parse(fixture.file)
        #expect(parsed.usageLimitSnapshots.count == 1)
        #expect(parsed.usageLimitSnapshots[0].state == .unsupportedSchema)
        #expect(parsed.diagnostics["unsupportedUsageLimitSchemas"] == 1)
        let report = UsageLimitSnapshotReport(
            query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 1_800_000_000),
            snapshots: parsed.usageLimitSnapshots
        )
        #expect(report.coverage.state == .unknown)
        #expect(report.coverage.unknownReason == .unsupportedSchema)
        #expect(report.coverage.supportedWindowObservations == 0)
        #expect(report.coverage.unsupportedSnapshots == 1)
        let absent = UsageLimitSnapshotReport(
            query: try UsageQuery(), generatedAt: Date(timeIntervalSince1970: 1_800_000_000), snapshots: []
        )
        #expect(absent.coverage.unknownReason == .noSnapshotInPeriod)
    }

    @Test func decodesAllReportedSlotsAndKeepsMissingFieldsUnknown() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.completeWindowSlotsEvent)
        let parsed = try RolloutDecoder().parse(fixture.file)
        let snapshot = try #require(parsed.usageLimitSnapshots.first)
        #expect(snapshot.state == .observed)
        #expect(snapshot.windows.map(\.slot) == [.primary, .secondary, .individualLimit])
        #expect(snapshot.windows.map(\.windowKind) == [.fiveHour, .weekly, .fiveHour])

        try fixture.write(fixture.partialWindowEvent)
        let partial = try #require(try RolloutDecoder().parse(fixture.file).usageLimitSnapshots.first)
        let unknownUsed = try #require(partial.windows.first)
        #expect(partial.state == .partial)
        #expect(unknownUsed.usedPercent == nil)
        #expect(unknownUsed.remainingPercentDerived == nil)
    }

    @Test func malformedSlotKeepsOtherValidWindowAndMarksSnapshotPartial() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let event = try fixture.jsonlEvent(timestamp: "2026-09-20T10:00:00Z", rateLimits: [
            "primary": ["used_percent": 82, "resets_at": 1_790_422_316, "window_minutes": 300],
            "secondary": "future-window-shape",
            "individual_limit": NSNull()
        ])
        try fixture.write(event)

        let parsed = try RolloutDecoder().parse(fixture.file)
        let snapshot = try #require(parsed.usageLimitSnapshots.first)
        let primary = try #require(snapshot.windows.first)

        #expect(snapshot.state == .partial)
        #expect(snapshot.windows.count == 1)
        #expect(primary.slot == .primary)
        #expect(primary.usedPercent == 82)
        #expect(parsed.diagnostics["partialUsageLimitSnapshots"] == 1)
        #expect(parsed.diagnostics["unsupportedUsageLimitSchemas"] == nil)
    }

    @Test func importsDeduplicateMirroredEventsAndKeepResetEpochsSeparate() async throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let first = try RolloutDecoder().parse(fixture.writeAndReturn(
            fixture.event(timestamp: "2026-09-20T10:00:00Z", used: 82)
        ))
        let firstSnapshot = try #require(first.usageLimitSnapshots.first)
        let mirrored = mirroredSnapshot(from: firstSnapshot)
        let next = nextResetSnapshot()
        var canonical = ParsedRollout()
        canonical.records = [canonicalRecord()]
        canonical.usageLimitSnapshots = [firstSnapshot]
        var mirroredRollout = ParsedRollout()
        mirroredRollout.usageLimitSnapshots = [mirrored]
        var nextRollout = ParsedRollout()
        nextRollout.usageLimitSnapshots = [next]

        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "a", rollout: canonical)
        try store.replace(source: "b", rollout: mirroredRollout)
        try store.replace(source: "c", rollout: nextRollout)
        let since = Date(timeIntervalSince1970: 1_789_898_300)
        let until = Date(timeIntervalSince1970: 1_789_898_700)
        let query = try UsageQuery(since: since, until: until)
        let generatedAt = Date(timeIntervalSince1970: 1_789_899_000)
        let report = try store.usageLimitSnapshots(query: query, generatedAt: generatedAt)

        #expect(report.snapshots.count == 2)
        let storedFirstSnapshot = try #require(report.snapshots.first)
        let secondSnapshot = try #require(report.snapshots.last)
        #expect(storedFirstSnapshot.duplicateSourceRecords == 1)
        #expect(report.snapshots.compactMap { $0.windows.first?.usedPercent } == [82, 89])
        #expect(storedFirstSnapshot.windows[0].resetsAt != secondSnapshot.windows[0].resetsAt)
        #expect(report.coverage.state == .observed)
        #expect(try store.report(since: nil, until: nil).totals.inputTokens == 100)
        let encoded = try JSONEncoder().encode(report)
        #expect(try JSONDecoder().decode(UsageLimitSnapshotReport.self, from: encoded) == report)
    }

    private func mirroredSnapshot(from snapshot: UsageLimitSnapshotObservation) -> UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: snapshot.eventIdentity, timestamp: snapshot.timestamp, sourceLine: 1,
            sourceContextSessionID: "another-rollout-context", sourceSchema: snapshot.sourceSchema,
            state: snapshot.state, limitID: snapshot.limitID, limitName: snapshot.limitName,
            planType: snapshot.planType, windows: snapshot.windows
        )
    }

    private func nextResetSnapshot() -> UsageLimitSnapshotObservation {
        UsageLimitSnapshotObservation(
            eventIdentity: "next-reset-epoch", timestamp: Date(timeIntervalSince1970: 1_789_898_500),
            sourceLine: 2, sourceContextSessionID: nil, sourceSchema: "codex.event_msg.token_count.rate_limits",
            state: .observed, limitID: "fixture-limit", limitName: nil, planType: "fixture",
            windows: [UsageLimitWindowObservation(
                slot: .primary, windowMinutes: 300, usedPercent: 89,
                resetsAt: Date(timeIntervalSince1970: 1_790_500_000)
            )]
        )
    }

    private func canonicalRecord() -> UsageRecord {
        UsageRecord(
            responseID: "response", sessionID: "session", turnID: "turn",
            timestamp: Date(timeIntervalSince1970: 1_790_000_000), model: "fixture",
            inputTokens: 100, cachedInputTokens: 90, outputTokens: 10, sourceLine: 1
        )
    }

    @Test func repeatedImportIsIdempotentAndAbsentTelemetryDoesNotInventZero() async throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.event(timestamp: "2026-09-20T10:00:00Z", used: 82))
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.file)
        try fixture.append(fixture.event(timestamp: "2026-09-20T10:01:00Z", used: 89))
        _ = try await runtime.importDirectory(fixture.file)
        _ = try await runtime.importDirectory(fixture.file)
        let report = try await runtime.usageLimitSnapshots(query: UsageQuery())
        #expect(report.snapshots.count == 2)
        #expect(report.snapshots[0].windows[0].usedPercent == 82)
        #expect(report.snapshots[1].windows[0].usedPercent == 89)
        #expect(report.snapshots[0].windows[0].remainingPercentDerived == 18)
        #expect(try await runtime.report().totals.requests == 0)
    }
}

struct UsageLimitFixture {
    let directory: URL
    var file: URL { directory.appending(path: "quota.jsonl") }
    var database: URL { directory.appending(path: "usage.sqlite") }
    var source: String { file.resolvingSymlinksInPath().path }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    @discardableResult
    func writeAndReturn(_ content: String) throws -> URL {
        try write(content)
        return file
    }

    func write(_ content: String) throws {
        try Data(content.utf8).write(to: file, options: .atomic)
    }

    func append(_ content: String) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(content.utf8))
    }

    func jsonlEvent(timestamp: String, rateLimits: [String: Any]) throws -> String {
        let payload: [String: Any] = ["type": "token_count", "rate_limits": rateLimits]
        let event: [String: Any] = ["timestamp": timestamp, "type": "event_msg", "payload": payload]
        return try jsonlLine(event)
    }

    func jsonlLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let line = String(bytes: data, encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        return line + "\n"
    }

    // swiftlint:disable line_length
    func event(timestamp: String, used: Int) -> String {
        """
        {"timestamp":"\(timestamp)","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"fixture-limit","limit_name":null,"plan_type":"fixture","primary":{"used_percent":\(used),"resets_at":1790422316,"window_minutes":300},"secondary":null,"individual_limit":null}}}

        """
    }

    var completeWindowSlotsEvent: String {
        """
        {"timestamp":"2026-09-20T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"limit_id":"fixture-limit","plan_type":"fixture","primary":{"used_percent":40,"resets_at":1790422316,"window_minutes":300},"secondary":{"used_percent":70,"resets_at":1791027116,"window_minutes":10080},"individual_limit":{"used_percent":25,"resets_at":1790422316,"window_minutes":300}}}}

        """
    }

    var partialWindowEvent: String {
        """
        {"timestamp":"2026-09-20T10:01:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"resets_at":1790422316,"window_minutes":300}}}}

        """
    }

    var unsupportedEvent: String {
        """
        {"timestamp":"2026-09-20T10:01:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"future_shape":{"value":1}}}}
        """
    }
    // swiftlint:enable line_length

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
