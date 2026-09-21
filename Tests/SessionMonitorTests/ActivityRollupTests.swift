import CodexSource
import Foundation
import GRDB
import MonitorCore
import MonitorRuntime
import MonitorStore
import Testing

struct ActivityRollupTests {
    @Test func parserClassifiesOnlyExactKnownToolNamesAndPreservesUnknowns() throws {
        let fixture = try ActivityFixture()
        defer { fixture.remove() }
        try fixture.writeParent()
        let rollout = try RolloutDecoder().parse(fixture.parentFile)
        let tools = rollout.timelineEvents.filter { $0.kind == .tool }
        #expect(tools.map(\.toolName) == [
            "exec_command", "exec_command", "wait", "wait", "write_stdin", "wait_threads", "wait_threads",
            "clock.sleep", "prefix_exec_command", nil
        ])
        #expect(tools.map(\.activityClass) == [
            .shell, .shell, .wait, .wait, .processWait, .waitThreads, .waitThreads, .clockSleep, .unknown, .unknown
        ])
        #expect(tools.dropLast().allSatisfy { $0.model == "model-parent" })
        #expect(tools.last?.model == nil)
        #expect(rollout.timelineEvents.first { $0.kind == .goalTurn }?.activityClass == .goalContinuation)
        #expect(tools.last?.evidence == "custom_tool_call_output")
        let futureEvent = try #require(rollout.timelineEvents.first { $0.evidence == "future_tool_call" })
        #expect(futureEvent.kind == .unknown)
        #expect(futureEvent.toolName == "exec_command")
        #expect(futureEvent.activityClass == nil)
    }

    @Test func rollupPreservesEvidenceScopesParentAndSubagentAndDoesNotChangeAccounting() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.remove() }
        try fixture.writeParent()
        try fixture.writeChild()
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)
        let before = try await runtime.report()

        let all = try await runtime.activity(query: UsageQuery())
        #expect(all.totals == before.totals)
        #expect(all.totals.cacheWriteInputTokens == 4)
        #expect(all.totals.reasoningOutputTokens == 4)
        #expect(all.totals.totalTokens == 147)
        #expect(all.usageByModel.map(\.model) == ["model-child", "model-parent"])
        #expect(all.usageByModel.first?.cacheWriteInputTokens == 1)
        #expect(all.usageByModel.last?.reasoningOutputTokens == 2)
        #expect(all.usageByModel.reduce(0) { $0 + ($1.totalTokens ?? 0) } == 147)
        #expect(all.usageByThreadAndModel.map(\.sessionID) == ["child", "parent"])
        #expect(all.coverage.state == .observed)
        #expect(all.toolEvents.contains { $0.classification == .shell && $0.sessionID == "parent" })
        #expect(all.toolEvents.contains { $0.classification == .processWait && $0.toolName == "write_stdin" })
        #expect(all.toolEvents.contains { $0.classification == .unknown && $0.toolName == "prefix_exec_command" })
        let goalEvent = try #require(all.toolEvents.first { $0.classification == .goalContinuation })
        #expect(goalEvent.evidence == "goal_turn_started")
        #expect(goalEvent.model == "model-parent")
        #expect(goalEvent.sourceLines == [13])
        let parentWaitEvents = all.toolEvents.filter {
            $0.sessionID == "parent" && $0.classification == .waitThreads
        }
        #expect(parentWaitEvents.map(\.evidence) == ["custom_tool_call", "custom_tool_call_output"])
        let shellEvents = all.toolEvents.filter { $0.classification == .shell }
        #expect(shellEvents.map(\.evidence) == ["function_call", "function_call_output"])
        #expect(shellEvents.allSatisfy { $0.toolName == "exec_command" })
        #expect(shellEvents.allSatisfy { $0.model == "model-parent" })
        let futureEvent = try #require(all.toolEvents.first { $0.evidence == "future_tool_call" })
        #expect(futureEvent.classification == .unknown)
        #expect(futureEvent.toolName == "exec_command")
        #expect(futureEvent.sourceLines == [15])

        let root = try await runtime.activity(query: UsageQuery(), rootSessionID: "parent")
        #expect(root.totals.requests == 2)
        #expect(root.usageByThreadAndModel.map(\.sessionID) == ["child", "parent"])
        let child = try await runtime.activity(query: UsageQuery(), sessionID: "child")
        #expect(child.totals.requests == 1)
        #expect(child.toolEvents.map(\.classification) == [.waitThreads])
        #expect(try await runtime.report().totals == before.totals)

        _ = try await runtime.importDirectory(fixture.directory)
        let repeated = try await runtime.activity(query: UsageQuery())
        #expect(repeated == all)
        _ = try await runtime.importDirectory(fixture.directory, rescan: true)
        #expect(try await runtime.activity(query: UsageQuery()) == all)
    }

    @Test func activityUsesHalfOpenIntervalAndNoEventsMeansUnknownCoverage() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.remove() }
        try fixture.writeParent()
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)

        let query = try UsageQuery(
            since: Date(timeIntervalSince1970: 103), until: Date(timeIntervalSince1970: 104)
        )
        let selected = try await runtime.activity(query: query)
        #expect(selected.toolEvents.count == 2)
        #expect(selected.toolEvents[0].classification == .shell)
        #expect(selected.toolEvents[0].sourceLines == [5])

        let empty = try UsageQuery(
            since: Date(timeIntervalSince1970: 200), until: Date(timeIntervalSince1970: 201)
        )
        let noEvents = try await runtime.activity(query: empty)
        #expect(noEvents.toolEvents.isEmpty)
        #expect(noEvents.coverage.state == .unknown)
        #expect(noEvents.coverage.unknownReason != nil)
    }

    @Test func migrationKeepsV1ToolEventsAsUnknownEvidence() throws {
        let fixture = try ActivityFixture()
        defer { fixture.remove() }
        try fixture.writeLegacyTimelineDatabase()

        let store = try UsageStore(url: fixture.database)
        let report = try store.activity(query: UsageQuery())
        let event = try #require(report.toolEvents.first)
        #expect(event.classification == .unknown)
        #expect(event.toolName == nil)
        #expect(event.evidence == "function_call")
        #expect(event.sourceLines == [8])
        #expect(report.coverage.unknownClassEvents == 1)
    }

    @Test func mirroredRolloutsDoNotDoubleCountActivityEvents() async throws {
        let fixture = try ActivityFixture()
        defer { fixture.remove() }
        try fixture.writeParent()
        try fixture.writeMirror()
        let runtime = try SessionMonitor(databaseURL: fixture.database)
        _ = try await runtime.importDirectory(fixture.directory)

        let report = try await runtime.activity(query: UsageQuery())
        #expect(report.totals.requests == 1)
        #expect(report.toolEvents.reduce(0) { $0 + $1.count } == 12)
        #expect(report.toolEvents.first { $0.toolName == "exec_command" }?.sourceLines == [5])
    }

    @Test func toolCallNameSurvivesCheckpointUntilOutputEnvelope() throws {
        let fixture = try ActivityFixture()
        defer { fixture.remove() }
        let file = fixture.directory.appending(path: "incremental.jsonl")
        try (fixture.callOnlyRollout() + "\n").write(to: file, atomically: true, encoding: .utf8)
        let decoder = RolloutDecoder()
        let first = try decoder.parseIncrementally(file)
        #expect(first.rollout.timelineEvents.first?.toolName == "exec_command")

        try fixture.appendOutput(to: file)
        let second = try decoder.parseIncrementally(file, checkpoint: first.checkpoint)
        let output = try #require(second.rollout.timelineEvents.first)
        #expect(second.mode == .appended)
        #expect(output.kind == .tool)
        #expect(output.evidence == "function_call_output")
        #expect(output.toolName == "exec_command")
        #expect(output.activityClass == .shell)
    }
}

private struct ActivityFixture {
    let directory: URL
    var database: URL { directory.appending(path: "usage.sqlite") }
    var parentFile: URL { directory.appending(path: "parent.jsonl") }
    var childFile: URL { directory.appending(path: "child.jsonl") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }

    func writeParent() throws { try parent().write(to: parentFile, atomically: true, encoding: .utf8) }
    func writeChild() throws { try child().write(to: childFile, atomically: true, encoding: .utf8) }
    func writeMirror() throws {
        try parent().write(to: directory.appending(path: "parent-copy.jsonl"), atomically: true, encoding: .utf8)
    }

    func writeLegacyTimelineDatabase() throws {
        let database = try DatabaseQueue(path: self.database.path)
        try database.write { connection in
            try connection.execute(sql: "CREATE TABLE grdb_migrations (identifier TEXT NOT NULL PRIMARY KEY)")
            let oldMigrations = [
                "canonical-v1", "source-checkpoints-v1", "query-watermark-v1",
                "session-provenance-v1", "timeline-evidence-v1"
            ]
            for identifier in oldMigrations {
                try connection.execute(sql: "INSERT INTO grdb_migrations VALUES (?)", arguments: [identifier])
            }
            try connection.execute(sql: """
                CREATE TABLE source_timeline_events (
                    source TEXT NOT NULL, line INTEGER NOT NULL, session TEXT NOT NULL, turn TEXT,
                    timestamp REAL NOT NULL, kind TEXT NOT NULL, evidence TEXT NOT NULL,
                    PRIMARY KEY(source, line)
                )
                """)
            try connection.execute(sql: """
                INSERT INTO source_timeline_events VALUES ('legacy', 8, 'S', 'T', 100, 'tool', 'function_call')
                """)
            try connection.execute(sql: """
                CREATE TABLE source_provenance (source TEXT NOT NULL, session TEXT NOT NULL, root_session TEXT)
                """)
            try connection.execute(sql: """
                CREATE TABLE source_records (
                    source TEXT NOT NULL, line INTEGER NOT NULL, response TEXT NOT NULL, session TEXT NOT NULL,
                    turn TEXT NOT NULL, timestamp REAL NOT NULL, model TEXT NOT NULL, input INTEGER NOT NULL,
                    cached INTEGER, output INTEGER NOT NULL, fingerprint TEXT NOT NULL,
                    cache_write INTEGER, reasoning INTEGER, total INTEGER
                )
                """)
            try connection.execute(sql: """
                CREATE VIEW confirmed AS
                SELECT response, session, turn, MIN(timestamp) AS timestamp, model, input, cached, output,
                       cache_write, reasoning, total
                FROM source_records GROUP BY response HAVING COUNT(DISTINCT fingerprint) = 1
                """)
        }
    }

    // Synthetic anonymized payloads exercise the observed Codex rollout envelope and explicit tool-name field.
    // swiftlint:disable line_length
    private func parent() -> String {
        """
        {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"parent","timestamp":"1970-01-01T00:01:40Z","cli_version":"fixture-version"}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"P1","started_at":101}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"P1","model":"model-parent"}}
        {"timestamp":"1970-01-01T00:01:42Z","type":"token_usage_record","payload":{"thread_id":"parent","turn_id":"P1","response_id":"parent-response","usage":{"input_tokens":100,"cached_input_tokens":80,"output_tokens":10,"cache_write_input_tokens":3,"reasoning_output_tokens":2,"total_tokens":112}}}
        {"timestamp":"1970-01-01T00:01:43Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"call-shell","internal_chat_message_metadata_passthrough":{"turn_id":"P1"}}}
        {"timestamp":"1970-01-01T00:01:43Z","type":"response_item","payload":{"type":"function_call_output","call_id":"call-shell","output":"done"}}
        {"timestamp":"1970-01-01T00:01:44Z","type":"response_item","payload":{"type":"custom_tool_call","name":"wait","call_id":"call-wait","turn_id":"P1"}}
        {"timestamp":"1970-01-01T00:01:44Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-wait","output":"done"}}
        {"timestamp":"1970-01-01T00:01:45Z","type":"response_item","payload":{"type":"custom_tool_call","name":"write_stdin","turn_id":"P1"}}
        {"timestamp":"1970-01-01T00:01:46Z","type":"response_item","payload":{"type":"custom_tool_call","name":"wait_threads","call_id":"call-wait-threads","turn_id":"P1"}}
        {"timestamp":"1970-01-01T00:01:46Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"call-wait-threads","output":"done"}}
        {"timestamp":"1970-01-01T00:01:47Z","type":"response_item","payload":{"type":"custom_tool_call","name":"clock.sleep","turn_id":"P1"}}
        {"timestamp":"1970-01-01T00:01:48Z","type":"event_msg","payload":{"type":"goal_turn_started","turn_id":"P1"}}
        {"timestamp":"1970-01-01T00:01:49Z","type":"response_item","payload":{"type":"custom_tool_call","name":"prefix_exec_command","turn_id":"P1"}}
        {"timestamp":"1970-01-01T00:01:50Z","type":"response_item","payload":{"type":"future_tool_call","name":"exec_command","turn_id":"P1"}}
        {"timestamp":"1970-01-01T00:01:51Z","type":"response_item","payload":{"type":"custom_tool_call_output","call_id":"orphan-call","output":"unknown call"}}

        """
    }

    func callOnlyRollout() -> String {
        """
        {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"parent","timestamp":"1970-01-01T00:01:40Z"}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"P1","started_at":101}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"P1","model":"model-parent"}}
        {"timestamp":"1970-01-01T00:01:43Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","call_id":"call-shell"}}
        """
    }

    func appendOutput(to file: URL) throws {
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("\n{\"timestamp\":\"1970-01-01T00:01:44Z\",\"type\":\"response_item\",\"payload\":{\"type\":\"function_call_output\",\"call_id\":\"call-shell\",\"output\":\"done\"}}\n".utf8))
    }

    private func child() -> String {
        """
        {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"child","timestamp":"1970-01-01T00:01:40Z","root_session_id":"parent","parent_thread_id":"parent","thread_source":"subagent"}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"C1","started_at":101}}
        {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"C1","model":"model-child"}}
        {"timestamp":"1970-01-01T00:01:42Z","type":"token_usage_record","payload":{"thread_id":"child","turn_id":"C1","response_id":"child-response","usage":{"input_tokens":30,"cached_input_tokens":20,"output_tokens":5,"cache_write_input_tokens":1,"reasoning_output_tokens":2,"total_tokens":35}}}
        {"timestamp":"1970-01-01T00:01:43Z","type":"response_item","payload":{"type":"custom_tool_call","name":"wait_threads","turn_id":"C1"}}

        """
    }
    // swiftlint:enable line_length
}
