import Foundation
import MonitorCore
import MonitorPolicies
import MonitorRuntime
import MonitorStore
import Testing

struct AgentHookTests {
    @Test func decodesCodexAndClaudeCodePayloadsAndIgnoresUnknownFields() throws {
        let codex = Data("""
            {"session_id":"019a-codex","transcript_path":"/tmp/rollout.jsonl","cwd":"/repo",
             "hook_event_name":"UserPromptSubmit","model":"gpt-5","turn_id":"t1","prompt":"hi"}
            """.utf8)
        let claude = Data("""
            {"session_id":"abc","transcript_path":null,"hook_event_name":"UserPromptSubmit",
             "permission_mode":"default","effort":{"level":"high"}}
            """.utf8)
        let decodedCodex = try JSONDecoder().decode(AgentHookInput.self, from: codex)
        #expect(decodedCodex == AgentHookInput(
            sessionID: "019a-codex", transcriptPath: "/tmp/rollout.jsonl", hookEventName: "UserPromptSubmit",
            cwd: "/repo"
        ))
        #expect(try JSONDecoder().decode(AgentHookInput.self, from: claude).transcriptPath == nil)
    }

    @Test func contextIsSilentWithoutAlertsAndBoundedWithThem() throws {
        let quiet = Self.report(alerts: [])
        #expect(AgentHookContext.render(quiet, match: .sessionID) == nil)
        #expect(AgentHookContext.render(quiet, match: .sessionID, always: true)?
            .contains("No active alerts") == true)

        let info = Self.report(alerts: [Self.alert("cache", severity: .info)])
        #expect(AgentHookContext.render(info, match: .sessionID) == nil)

        let long = String(repeating: "x", count: 5_000)
        let loud = Self.report(alerts: [Self.alert("polling", severity: .warning, message: long)])
        let text = try #require(AgentHookContext.render(loud, match: .sessionID))
        #expect(text.hasPrefix("SessionMonitor"))
        #expect(text.contains("[warning] polling"))
        #expect(text.count <= AgentHookContext.characterLimit)

        let output = try JSONEncoder().encode(
            AgentHookOutput(hookEventName: "UserPromptSubmit", additionalContext: text)
        )
        let object = try JSONSerialization.jsonObject(with: output) as? [String: Any]
        let specific = object?["hookSpecificOutput"] as? [String: Any]
        #expect(specific?["hookEventName"] as? String == "UserPromptSubmit")
        #expect(specific?["additionalContext"] as? String == text)
    }

    @Test func matchesBySessionIDThenTranscriptAndNeverFallsBackToLatest() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "usage.sqlite")
        let transcript = directory.appending(path: "rollout-own.jsonl")
        try Data().write(to: transcript)
        let transcriptSource = transcript.resolvingSymlinksInPath().path
        let now = Date()
        let store = try UsageStore(url: url)
        for (source, session, offset) in [(transcriptSource, "own", -300.0), ("other.jsonl", "newest", -60.0)] {
            var rollout = ParsedRollout()
            rollout.records = [UsageRecord(
                responseID: "\(session)-1", sessionID: session, turnID: "T",
                timestamp: now.addingTimeInterval(offset),
                model: "fixture", inputTokens: 1_000, cachedInputTokens: 900, outputTokens: 10, sourceLine: 1
            )]
            rollout.provenance = SessionProvenance(sessionID: session, models: ["fixture"])
            try store.replace(source: source, rollout: rollout)
        }
        _ = try store.applyAlertEvaluation(AlertEvaluation(scopes: [], candidates: [AlertCandidate(
            key: "quota|remaining|weekly", scope: AlertScope("quota:remaining"), source: .quota,
            kind: "low_remaining", severity: .warning, title: "Low remaining quota", message: "Fixture."
        )], observedAt: now))
        let monitor = try SessionMonitor(databaseURL: url)

        let byID = try await monitor.agentHook(
            AgentHookInput(sessionID: "own", transcriptPath: nil, hookEventName: "UserPromptSubmit"),
            now: now, importTranscript: false
        )
        #expect(byID.match == .sessionID)
        #expect(byID.report.session?.id == "own")

        let byTranscript = try await monitor.agentHook(
            AgentHookInput(sessionID: "unknown-thread", transcriptPath: transcript.path, hookEventName: "Stop"),
            now: now, importTranscript: false
        )
        #expect(byTranscript.match == .transcript)
        #expect(byTranscript.report.session?.id == "own")

        let claude = try await monitor.agentHook(
            AgentHookInput(sessionID: "claude-session", transcriptPath: nil, hookEventName: "UserPromptSubmit"),
            now: now, importTranscript: false
        )
        #expect(claude.match == .none)
        #expect(claude.report.session == nil)
        #expect(claude.report.alerts.map(\.key) == ["quota|remaining|weekly"])
        let text = try #require(AgentHookContext.render(claude.report, match: claude.match))
        #expect(text.contains("not a Codex session"))
    }

    @Test func importedTranscriptIsEvaluatedSoTheHookSeesNewSignals() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transcript = directory.appending(path: "rollout-hook.jsonl")
        // Two expensive requests in the first turn, then a cheap one: the startup-overhead anomaly.
        // swiftlint:disable line_length
        func record(_ id: String, turn: String, second: Int, input: Int) -> String {
            "{\"timestamp\":\"1970-01-01T00:01:\(second)Z\",\"type\":\"token_usage_record\",\"payload\":{\"thread_id\":\"H\",\"turn_id\":\"\(turn)\",\"response_id\":\"\(id)\",\"usage\":{\"input_tokens\":\(input),\"cached_input_tokens\":0,\"output_tokens\":10}}}\n"
        }
        let rollout = """
            {"timestamp":"1970-01-01T00:01:40Z","type":"session_meta","payload":{"id":"H","timestamp":"1970-01-01T00:01:40Z"}}
            {"timestamp":"1970-01-01T00:01:41Z","type":"event_msg","payload":{"type":"task_started","turn_id":"first","started_at":101}}
            {"timestamp":"1970-01-01T00:01:41Z","type":"turn_context","payload":{"turn_id":"first","model":"fixture-model"}}

            """ + record("R1", turn: "first", second: 42, input: 1_000) + record("R2", turn: "first", second: 43, input: 1_000)
            + "{\"timestamp\":\"1970-01-01T00:01:44Z\",\"type\":\"event_msg\",\"payload\":{\"type\":\"task_started\",\"turn_id\":\"later\",\"started_at\":104}}\n"
            + "{\"timestamp\":\"1970-01-01T00:01:44Z\",\"type\":\"turn_context\",\"payload\":{\"turn_id\":\"later\",\"model\":\"fixture-model\"}}\n"
            + record("R3", turn: "later", second: 45, input: 100)
        // swiftlint:enable line_length
        try Data(rollout.utf8).write(to: transcript)
        let monitor = try SessionMonitor(databaseURL: directory.appending(path: "usage.sqlite"))
        let now = Date(timeIntervalSince1970: 400)

        let result = try await monitor.agentHook(
            AgentHookInput(sessionID: "H", transcriptPath: transcript.path, hookEventName: "UserPromptSubmit"),
            now: now
        )
        #expect(result.importedTranscript)
        #expect(result.match == .sessionID)
        #expect(result.report.alerts.contains { $0.key == "anomaly|excessive_startup_overhead|H" })
        #expect(AgentHookContext.render(result.report, match: result.match) != nil)
    }

    private static func report(alerts: [AgentStatusReport.Alert]) -> AgentStatusReport {
        AgentStatusReport(
            generatedAt: Date(timeIntervalSince1970: 0), lookbackSeconds: 3_600,
            index: AgentStatusReport.Index(revision: 1, committedAt: nil, ageSeconds: nil),
            session: nil, recent: nil, alerts: alerts, quota: []
        )
    }

    private static func alert(
        _ title: String, severity: DiagnosticSeverity, message: String = "Fixture."
    ) -> AgentStatusReport.Alert {
        let now = Date(timeIntervalSince1970: 0)
        return AgentStatusReport.Alert(AlertRecord(
            candidate: AlertCandidate(
                key: title, scope: AlertScope(title), source: .anomaly, kind: title, severity: severity,
                title: title, message: message, sessionIDs: ["s"]
            ),
            status: .active, firstSeenAt: now, raisedAt: now, lastSeenAt: now
        ))
    }
}
