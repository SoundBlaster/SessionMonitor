import Foundation
import MonitorCore
import MonitorStore
import Testing

struct SessionSpanTests {
    @Test func sessionSummariesCarryTheirWholeHistoryFirstAndLastRequest() throws {
        let fixture = try SpanFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: "long", rollout: fixture.rollout(
            records: [("A", 1_000), ("B", 5_000), ("C", 9_000)].enumerated().map { index, entry in
                fixture.record(id: entry.0, timestamp: entry.1, line: index + 1)
            }
        ))
        // The period only contains the middle request, but the dates describe the whole session.
        let query = try UsageQuery(since: Date(timeIntervalSince1970: 4_000), until: Date(timeIntervalSince1970: 6_000))
        let snapshot = try #require(try store.snapshot(query: query))
        let session = try #require(snapshot.report.sessions.first)
        #expect(session.totals.requests == 1)
        #expect(session.firstRequestAt == Date(timeIntervalSince1970: 1_000))
        #expect(session.lastRequestAt == Date(timeIntervalSince1970: 9_000))
    }

    @Test func sessionDatesAreScopedToTheSelectedAccount() throws {
        let fixture = try SpanFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        try store.replace(source: fixture.source("a/one.jsonl"), rollout: fixture.rollout(
            records: [fixture.record(id: "R-A", timestamp: 1_000, line: 1)],
            identity: SourceAccountIdentity(accountID: "account-A", userID: "user-A")
        ))
        try store.replace(source: fixture.source("b/one.jsonl"), rollout: fixture.rollout(
            records: [fixture.record(id: "R-B", timestamp: 6_000, line: 1)],
            identity: SourceAccountIdentity(accountID: "account-B", userID: "user-B")
        ))
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "a"),
                                           profileID: "personal", label: "Personal")
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "b"),
                                           profileID: "work", label: "Work")

        func session(_ scope: UsageAccountScope) throws -> SessionSummary? {
            try store.snapshot(query: UsageQuery(accountScope: scope))?.report.sessions.first
        }
        let personal = try session(UsageAccountScope(profileID: "personal"))
        let work = try session(UsageAccountScope(profileID: "work"))
        let all = try session(.allAccounts)

        #expect(personal?.firstRequestAt == Date(timeIntervalSince1970: 1_000))
        #expect(personal?.lastRequestAt == Date(timeIntervalSince1970: 1_000))
        #expect(work?.firstRequestAt == Date(timeIntervalSince1970: 6_000))
        #expect(all?.firstRequestAt == Date(timeIntervalSince1970: 1_000))
        #expect(all?.lastRequestAt == Date(timeIntervalSince1970: 6_000))
    }
}

private struct SpanFixture {
    let directory: URL
    var database: URL { directory.appending(path: "usage.sqlite") }

    init() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        for name in ["a", "b"] {
            try FileManager.default.createDirectory(
                at: directory.appending(path: name), withIntermediateDirectories: true
            )
        }
    }

    func source(_ relative: String) -> String { directory.appending(path: relative).standardizedFileURL.path }

    func record(id: String, timestamp: TimeInterval, line: Int) -> UsageRecord {
        UsageRecord(
            responseID: id, sessionID: "session-shared", turnID: "T",
            timestamp: Date(timeIntervalSince1970: timestamp), model: "fixture",
            inputTokens: 100, cachedInputTokens: 80, outputTokens: 10, sourceLine: line
        )
    }

    func rollout(records: [UsageRecord], identity: SourceAccountIdentity? = nil) -> ParsedRollout {
        var result = ParsedRollout()
        result.records = records
        result.accountIdentity = identity
        return result
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}
