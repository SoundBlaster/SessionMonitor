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

    @Test func carriesOutputReasoningAndCacheWriteOnlyWhenSourceHasThem() async throws {
        let fixture = try TimelineFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.sourceWithEvidence)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)

        let requests = try await runtime.timeline(sessionID: "S", query: try UsageQuery()).points
            .filter { $0.kind == .usageRequest }
        #expect(requests[0].outputTokens == 10)
        #expect(requests[0].reasoningOutputTokens == 4)
        #expect(requests[0].cacheWriteInputTokens == 30)
        #expect(requests[1].outputTokens == 10)
        #expect(requests[1].reasoningOutputTokens == nil)
        #expect(requests[1].cacheWriteInputTokens == nil)
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

    @Test func sameSecondEventsAfterARequestBelongToTheNextStep() async throws {
        let fixture = try TimelineFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.sourceWithEvidence)
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)

        let timeline = try await runtime.timeline(sessionID: "S", query: try UsageQuery())
        let requestIndexes = timeline.points.indices.filter { timeline.points[$0].kind == .usageRequest }
        #expect(requestIndexes.count == 2)
        #expect(timeline.points[requestIndexes[0]...requestIndexes[1]].map(\.kind).contains(.compaction))
        #expect(timeline.points.filter { $0.kind == .usageRequest }.allSatisfy { $0.sourceLine == nil })

        let anatomy = ContextAnatomyBuilder.build(timeline)
        #expect(anatomy.steps.count == 2)
        let first = anatomy.steps[0].activityBefore
        #expect(first.humanTurns == 1 && first.goalTurns == 1)
        #expect(first.compactions == 0 && first.tools == 0 && first.waits == 0 && first.other == 0)
        let second = anatomy.steps[1].activityBefore
        #expect(second.compactions == 1 && second.tools == 1 && second.waits == 1 && second.other == 1)
        #expect(anatomy.trailingActivity == .none)
    }

    @Test func mirroredRolloutsDoNotDuplicateTimelineEvents() async throws {
        let fixture = try TimelineFixture()
        defer { fixture.remove() }
        try fixture.write(fixture.sourceWithEvidence)
        let single = try SessionMonitor(databaseURL: fixture.database)
        _ = try await single.importDirectory(fixture.directory)
        let expected = try await single.timeline(sessionID: "S", query: try UsageQuery())

        let mirrored = try TimelineFixture()
        defer { try? FileManager.default.removeItem(at: mirrored.directory) }
        try mirrored.write(mirrored.sourceWithEvidence)
        try mirrored.sourceWithEvidence.write(
            to: mirrored.directory.appending(path: "rollout-copy.jsonl"), atomically: true, encoding: .utf8)
        let runtime = try SessionMonitor(databaseURL: mirrored.database)
        _ = try await runtime.importDirectory(mirrored.directory)

        let timeline = try await runtime.timeline(sessionID: "S", query: try UsageQuery())
        #expect(timeline.points.count == expected.points.count)
        #expect(timeline.points.map(\.kind) == expected.points.map(\.kind))
        #expect(timeline.points.filter { $0.kind == .compaction }.count == 1)
        let anatomy = ContextAnatomyBuilder.build(timeline)
        #expect(anatomy.steps.count == 2)
        #expect(anatomy.steps[1].activityBefore == ContextAnatomyBuilder.build(expected).steps[1].activityBefore)
        #expect(anatomy.steps[1].activityBefore.tools == 1)
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
        {"timestamp":"1970-01-01T00:01:42Z","type":"token_usage_record","payload":{"thread_id":"S","turn_id":"T","response_id":"R1","usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10,"reasoning_output_tokens":4,"cache_write_input_tokens":30}}}
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
