import Foundation
import MonitorCore
import MonitorStore
import Testing

struct RootActivityAccountIsolationTests {
    @Test(arguments: [false, true])
    func rootMembershipNeverLeaksFromForeignAccount(mapped: Bool) throws {
        let fixture = try AccountProfileFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let personal = mapped ? SourceAccountIdentity(accountID: "A", userID: nil) : nil
        let work = mapped ? SourceAccountIdentity(accountID: "B", userID: nil) : nil
        let root = rollout(identity: personal, session: "R", root: nil, input: 100, date: fixture.date)
        try store.replace(source: fixture.source("a/root.jsonl"), rollout: root)
        try store.replace(source: fixture.source("a/root-mirror.jsonl"), rollout: root)
        try store.replace(source: fixture.source("a/child.jsonl"), rollout: rollout(
            identity: personal, session: "S", root: "OTHER", input: 900, date: fixture.date
        ))
        try store.replace(source: fixture.source("b/child.jsonl"), rollout: rollout(
            identity: work, session: "S", root: "R", input: 200, date: fixture.date
        ))
        if mapped {
            _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "a"),
                                               profileID: "personal", label: "Personal")
            _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "b"),
                                               profileID: "work", label: "Work")
        }
        let all = try store.activity(query: UsageQuery(), rootSessionID: "R")
        #expect(all.totals.requests == 2)
        #expect(all.totals.inputTokens == 300)
        #expect(all.coverage.observedToolEvents == 2)
        #expect(try store.activity(query: UsageQuery()).totals.inputTokens == 1_200)
        let scope = mapped ? UsageAccountScope(profileID: "personal") : .unknownOrMixed
        let scopedQuery = try UsageQuery(accountScope: scope)
        let scoped = try store.activity(query: scopedQuery, rootSessionID: "R")
        #expect(scoped.totals.inputTokens == (mapped ? 100 : 300))
        #expect(scoped.coverage.observedToolEvents == (mapped ? 1 : 2))
        if mapped {
            let workReport = try store.activity(query: UsageQuery(
                accountScope: UsageAccountScope(profileID: "work")
            ), rootSessionID: "R")
            #expect(workReport.totals.inputTokens == 200)
            #expect(workReport.coverage.observedToolEvents == 1)
        }
        try store.replace(source: fixture.source("b/child.jsonl"), rollout: ParsedRollout())
        let after = try store.activity(query: scopedQuery, rootSessionID: "R")
        #expect(after.totals.inputTokens == 100)
        #expect(after.coverage.observedToolEvents == 1)
        if mapped { #expect(scoped == after) }
    }

    private func rollout(identity: SourceAccountIdentity?, session: String, root: String?,
                         input: Int64, date: Date) -> ParsedRollout {
        var parsed = ParsedRollout()
        parsed.accountIdentity = identity
        parsed.records = [UsageRecord(
            responseID: "response-\(session)", sessionID: session, turnID: "T", timestamp: date,
            model: "fixture", inputTokens: input, cachedInputTokens: input, outputTokens: 1, sourceLine: 1
        )]
        parsed.provenance = SessionProvenance(sessionID: session, rootSessionID: root)
        parsed.timelineEvents = [TimelineSourceEvent(
            sessionID: session, timestamp: date, sourceLine: 3, kind: .tool,
            evidence: "function_call", toolName: "exec_command", activityClass: .shell
        )]
        return parsed
    }
}
