import Foundation
import MonitorCore
import Testing

struct SessionExportTests {
    @Test func exportUsesTheVersionedFixtureAndPreservesUnknownCounters() throws {
        let export = try #require(AnonymizedSessionExportBuilder.build(
            clientVersion: "codex-1.2.3",
            timeline: timeline()
        ))
        let data = try export.encodedJSON()
        let fixtureURL = try #require(Bundle.module.url(forResource: "session-export.v1", withExtension: "json"))
        let expectedFixture = try Data(contentsOf: fixtureURL)
        let fixtureExport = try JSONDecoder().decode(AnonymizedSessionExport.self, from: expectedFixture)
        #expect(data == expectedFixture)
        #expect(fixtureExport == export)
        #expect(export.format == "session-export.v1")
        #expect(export.requests.map(\.ordinal) == [1, 2])
        #expect(export.requests.map(\.offsetSeconds) == [0, 1.25])
        #expect(export.requests[0].inputTokens == 100)
        #expect(export.requests[0].contextWindowTokens == 258_400)
        #expect(export.requests[1].cachedInputTokens == nil)
    }

    @Test func exportOmitsIdentityAbsoluteTimePathsToolNamesAndEvidence() throws {
        let export = try #require(AnonymizedSessionExportBuilder.build(
            clientVersion: "codex-1.2.3",
            timeline: timeline()
        ))
        let json = try #require(String(data: export.encodedJSON(), encoding: .utf8))
        for forbidden in [
            "session-secret", "turn-secret", "response-secret", "1970-01-01", "1000.0", "/Users/private",
            "working-directory-secret", "mcp-secret-tool", "prompt-secret", "sourceLine", "session_id", "turn_id",
            "response_id", "account_scope", "profile_id", "tool_name", "evidence"
        ] {
            #expect(!json.localizedCaseInsensitiveContains(forbidden), "Unexpected private value: \(forbidden)")
        }
        #expect(json.contains("gpt-6-luna"))
        #expect(json.contains("codex-1.2.3"))
        #expect(json.contains("\"tool_class\" : \"shell\""))
    }

    @Test func exportReturnsNilWithoutCanonicalUsageRequests() throws {
        let point = RequestTimelinePoint(
            id: "event-only", sessionID: "session-secret", timestamp: Date(timeIntervalSince1970: 1),
            kind: .tool, evidence: "private"
        )
        let timeline = RequestTimeline(sessionID: "session-secret", query: try UsageQuery(), points: [point])
        #expect(AnonymizedSessionExportBuilder.build(clientVersion: nil, timeline: timeline) == nil)
    }

    private func timeline() throws -> RequestTimeline {
        let first = RequestTimelinePoint(
            id: "request:secret-scope:response-secret", sessionID: "session-secret",
            timestamp: Date(timeIntervalSince1970: 1_000), kind: .usageRequest,
            turnID: "turn-secret", sourceLine: 41, responseID: "response-secret",
            inputTokens: 100, cachedInputTokens: 80, uncachedInputTokens: 20,
            outputTokens: 12, reasoningOutputTokens: 3, cacheWriteInputTokens: 5,
            evidence: "/Users/private/prompt-secret", model: "gpt-6-luna", contextWindowTokens: 258_400
        )
        let shell = RequestTimelinePoint(
            id: "event-secret", sessionID: "session-secret", timestamp: Date(timeIntervalSince1970: 1_001),
            kind: .tool, turnID: "turn-secret", sourceLine: 42, evidence: "prompt-secret",
            toolName: "mcp-secret-tool", model: "gpt-6-luna", activityClass: .shell
        )
        let wait = RequestTimelinePoint(
            id: "wait-secret", sessionID: "session-secret", timestamp: Date(timeIntervalSince1970: 1_001.1),
            kind: .wait, sourceLine: 43, evidence: "working-directory-secret", toolName: "wait_threads",
            activityClass: .waitThreads
        )
        let secondShell = RequestTimelinePoint(
            id: "event-secret-2", sessionID: "session-secret", timestamp: Date(timeIntervalSince1970: 1_001.2),
            kind: .tool, turnID: "turn-secret", sourceLine: 44, evidence: "another-prompt-secret",
            toolName: "another-mcp-secret-tool", model: "gpt-6-luna", activityClass: .shell
        )
        let second = RequestTimelinePoint(
            id: "request:secret-scope:another-response-secret", sessionID: "session-secret",
            timestamp: Date(timeIntervalSince1970: 1_001.25), kind: .usageRequest,
            turnID: "turn-secret", responseID: "another-response-secret", inputTokens: 40,
            cachedInputTokens: nil, uncachedInputTokens: nil, outputTokens: 8,
            model: "gpt-6.1-sol"
        )
        let query = try UsageQuery()
        return RequestTimeline(
            sessionID: "session-secret", query: query, points: [first, shell, wait, secondShell, second]
        )
    }
}
