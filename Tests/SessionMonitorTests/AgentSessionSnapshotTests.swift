import Foundation
import MonitorCore
import MonitorStore
import Testing

struct AgentSessionSnapshotTests {
    @Test func narrowReadMatchesCanonicalSessionTotalsAndQueryWatermark() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        for (source, account) in [("home", "A"), ("work", "B")] {
            var rollout = ParsedRollout()
            rollout.accountIdentity = SourceAccountIdentity(accountID: account, userID: nil)
            rollout.records = [
                record("older-\(account)", session: "older", at: 1),
                record("first-\(account)", session: "mine", at: 10),
                record("last-\(account)", session: "mine", at: 20, cached: nil),
                record("future-\(account)", session: "future", at: 30)
            ]
            let path = fixture.directory.appending(path: "\(source)/session.jsonl").path
            try store.replace(source: path, rollout: rollout)
        }
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "work"),
                                           profileID: "work", label: "Work")
        for scope in [UsageAccountScope.allAccounts, UsageAccountScope(profileID: "work"), .unknownOrMixed] {
            let query = try UsageQuery(since: Date(timeIntervalSince1970: 10),
                                       until: Date(timeIntervalSince1970: 30), accountScope: scope)
            let full = try #require(try store.snapshot(query: query))
            let selected = try store.agentSessionSnapshot(sessionID: nil, query: query)
            #expect(selected.sessionID == "mine")
            #expect(selected.watermark == full.watermark)
            #expect(selected.summary?.totals == full.report.sessions.first { $0.id == "mine" }?.totals)
            #expect(selected.summary?.model == full.report.sessions.first { $0.id == "mine" }?.model)
            #expect(selected.summary?.sourceStorage == nil)
            let missing = try store.agentSessionSnapshot(sessionID: "missing", query: query)
            #expect(missing.sessionID == "missing")
            #expect(missing.summary == nil)
        }
    }

    @Test func sessionFilterDoesNotBypassConflictingResponseDeduplication() throws {
        let fixture = try UsageLimitFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        for (source, session, input) in [("a", "mine", Int64(100)), ("b", "other", Int64(200))] {
            var rollout = ParsedRollout()
            rollout.records = [UsageRecord(
                responseID: "conflict", sessionID: session, turnID: "turn", timestamp: Date(timeIntervalSince1970: 10),
                model: "fixture", inputTokens: input, cachedInputTokens: 0, outputTokens: 1, sourceLine: 1
            )]
            try store.replace(source: source, rollout: rollout)
        }
        let selected = try store.agentSessionSnapshot(sessionID: "mine", query: UsageQuery())
        #expect(selected.summary == nil)
        #expect(try store.snapshot(query: UsageQuery())?.report.sessions.isEmpty == true)
    }

    private func record(_ id: String, session: String, at time: Double, cached: Int64? = 90) -> UsageRecord {
        UsageRecord(responseID: id, sessionID: session, turnID: "turn", timestamp: Date(timeIntervalSince1970: time),
                    model: "fixture", inputTokens: 100, cachedInputTokens: cached, outputTokens: 10,
                    sourceLine: Int(time))
    }
}
