import CodexSource
import Foundation
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

struct RequestTimelineTests {
    @Test func readsCachedAndUncachedInputWithoutChangingAccounting() async throws {
        let fixture = try TimelineFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.sourceWithEvidence)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)

        let timeline = try await runtime.timeline(sessionID: "S", query: try UsageQuery())
        let requests = timeline.points.filter { $0.kind == .usageRequest }
        #expect(requests.count == 2)
        #expect(requests[0].cachedInputTokens == 80)
        #expect(requests[0].uncachedInputTokens == 20)
        #expect(requests[1].cachedInputTokens == nil)
        #expect(requests[1].uncachedInputTokens == nil)
        #expect(try await runtime.report().totals.inputTokens == 150)
    }

    @Test func readsExplicitTurnAndOperationalEvidence() async throws {
        let fixture = try TimelineFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.sourceWithEvidence)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)

        let kinds = try await runtime.timeline(sessionID: "S", query: try UsageQuery()).points.map(\.kind)
        #expect(kinds.contains(.humanTurn))
        #expect(kinds.contains(.goalTurn))
        #expect(kinds.contains(.compaction))
        #expect(kinds.contains(.tool))
        #expect(kinds.contains(.wait))
        #expect(kinds.contains(.unknown))
    }

    @Test func filtersHalfOpenPeriodAndDoesNotAggregateChildSession() async throws {
        let fixture = try TimelineFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.sourceWithEvidence + fixture.childRecord)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)

        let query = try UsageQuery(since: Date(timeIntervalSince1970: 102),
                                   until: Date(timeIntervalSince1970: 103),
                                   timeZoneIdentifier: "Europe/Moscow")
        let timeline = try await runtime.timeline(sessionID: "S", query: query)
        #expect(timeline.query == query)
        guard let since = query.since, let until = query.until else {
            Issue.record("The bounded timeline query should have both dates")
            return
        }
        #expect(timeline.points.allSatisfy { $0.timestamp >= since && $0.timestamp < until })
        #expect(timeline.points.filter { $0.kind == .usageRequest }.count == 1)
        #expect(try await runtime.report(since: query.since, until: query.until).totals.inputTokens == 100)
        #expect(try await runtime.timeline(sessionID: "child", query: try UsageQuery()).points.count == 1)
    }

    @Test func timezoneChangesPresentationMetadataButNotAbsoluteDates() async throws {
        let fixture = try TimelineFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.sourceWithEvidence)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        let since = Date(timeIntervalSince1970: 102)
        let until = Date(timeIntervalSince1970: 104)
        let utc = try await runtime.timeline(sessionID: "S", query: UsageQuery(since: since, until: until))
        let moscow = try await runtime.timeline(
            sessionID: "S", query: UsageQuery(since: since, until: until, timeZoneIdentifier: "Europe/Moscow")
        )
        #expect(utc.query.timeZoneIdentifier == "UTC")
        #expect(moscow.query.timeZoneIdentifier == "Europe/Moscow")
        #expect(utc.points.map(\.timestamp) == moscow.points.map(\.timestamp))
    }

    @Test func emptyTimelineAndUnknownCacheAreExplicit() async throws {
        let fixture = try TimelineFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.sourceWithEvidence)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        let empty = try await runtime.timeline(sessionID: "missing", query: try UsageQuery())
        #expect(empty.isEmpty)
        let unknown = try await runtime.timeline(sessionID: "S", query: try UsageQuery()).points
            .first { $0.responseID == "R2" }
        #expect(unknown?.cachedInputTokens == nil)
        #expect(unknown?.uncachedInputTokens == nil)
    }
}

private struct TimelineFixture {
    let directory: URL
    var database: URL { directory.appending(path: "usage.sqlite") }
    var source: URL { directory.appending(path: "rollout.jsonl") }

    // swiftlint:disable line_length
    var sourceWithEvidence: String {
        """
        {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"S","timestamp":"1970-01-01T00:01:40Z"}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"T","started_at":101}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"T","model":"fixture"}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"response_item","payload":{"type":"message","role":"user","turn_id":"T"}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"goal_turn_started","turn_id":"T"}}
        {"timestamp":"1970-01-01T00:01:42Z","type":"token_usage_record","payload":{"thread_id":"S","turn_id":"T","response_id":"R1","usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10}}}
        {"timestamp":"1970-01-01T00:01:42Z","type":"compacted","payload":{}}
        {"timestamp":"1970-01-01T00:01:42Z","type":"response_item","payload":{"type":"function_call","turn_id":"T"}}
        {"timestamp":"1970-01-01T00:01:42Z","type":"event_msg","payload":{"type":"wait_started","turn_id":"T"}}
        {"timestamp":"1970-01-01T00:01:42Z","type":"event_msg","payload":{"type":"mystery_event","turn_id":"T"}}
        {"timestamp":"1970-01-01T00:01:43Z","type":"token_usage_record","payload":{"thread_id":"S","turn_id":"T","response_id":"R2","usage":{"input_tokens":50,"cached_input_tokens":null,"output_tokens":10}}}

        """
    }

    var childRecord: String {
        """
        {"timestamp":"1970-01-01T00:01:44Z","type":"session_meta","payload":{"id":"child","timestamp":"1970-01-01T00:01:44Z"}}
        {"timestamp":"1970-01-01T00:01:45Z","type":"event_msg","payload":{"type":"task_started","turn_id":"C","started_at":105}}
        {"timestamp":"1970-01-01T00:01:45Z","type":"turn_context","payload":{"turn_id":"C","model":"fixture"}}
        {"timestamp":"1970-01-01T00:01:46Z","type":"token_usage_record","payload":{"thread_id":"child","turn_id":"C","response_id":"C1","usage":{"input_tokens":7,"cached_input_tokens":0,"output_tokens":1}}}

        """
    }
    // swiftlint:enable line_length

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func write(_ content: String) throws {
        try content.write(to: source, atomically: true, encoding: .utf8)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
