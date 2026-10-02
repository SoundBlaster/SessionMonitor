import Foundation
import MonitorCore
import MonitorStore
import Testing

struct TimelineEventIdentityTests {
    @Test func assignedAccountEventsDeduplicateMirrorsWithoutCrossAccountIDCollisions() throws {
        let fixture = try AccountProfileFixture()
        defer { fixture.remove() }
        let store = try UsageStore(url: fixture.database)
        let personal = fixture.rollout(identity: SourceAccountIdentity(accountID: "A", userID: nil))
        var work = fixture.rollout(identity: SourceAccountIdentity(accountID: "B", userID: nil))
        work.timelineEvents = personal.timelineEvents
        try store.replace(source: fixture.source("a/one.jsonl"), rollout: personal)
        try store.replace(source: fixture.source("a/mirror.jsonl"), rollout: personal)
        try store.replace(source: fixture.source("b/one.jsonl"), rollout: work)
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "a"),
                                           profileID: "personal", label: "Personal")
        _ = try store.assignAccountProfile(sourceRoot: fixture.directory.appending(path: "b"),
                                           profileID: "work", label: "Work")
        let all = try store.timeline(sessionID: "session-collision", query: UsageQuery())
        let scoped = try store.timeline(sessionID: "session-collision", query: UsageQuery(
            accountScope: UsageAccountScope(profileID: "personal")
        ))
        #expect(all.points.filter { $0.kind == .tool }.count == 2)
        #expect(scoped.points.filter { $0.kind == .tool }.count == 1)
        #expect(Set(all.points.map(\.id)).count == all.points.count)
        #expect(scoped.points.allSatisfy { all.points.contains($0) })
    }

    @Test func unknownScopeEventsDeduplicateMirrorsAndKeepDistinctEventsStable() throws {
        let fixture = try AccountProfileFixture()
        defer { fixture.remove() }
        let original = fixture.rollout(identity: nil)
        var different = original
        different.timelineEvents = [TimelineSourceEvent(
            sessionID: "session-collision", timestamp: fixture.date, sourceLine: 3, kind: .tool,
            evidence: "fixture:unknown", toolName: "wait", activityClass: .wait
        )]
        let sources = [
            ("a/one.jsonl", original), ("a/mirror.jsonl", original),
            ("a/different.jsonl", different), ("b/one.jsonl", original)
        ]
        let forward = try UsageStore(url: fixture.database)
        let reverse = try UsageStore(url: fixture.directory.appending(path: "reverse.sqlite"))
        for (path, rollout) in sources {
            try forward.replace(source: fixture.source(path), rollout: rollout)
        }
        for (path, rollout) in sources.reversed() {
            try reverse.replace(source: fixture.source(path), rollout: rollout)
        }
        let query = try UsageQuery(accountScope: .unknownOrMixed)
        let timeline = try forward.timeline(sessionID: "session-collision", query: query)
        #expect(timeline == (try reverse.timeline(sessionID: "session-collision", query: query)))
        #expect(timeline.points.filter { $0.kind == .usageRequest }.count == 2)
        #expect(timeline.points.filter { $0.kind == .tool }.count == 3)
        #expect(Set(timeline.points.map(\.id)).count == timeline.points.count)
        #expect(try forward.activity(query: query).coverage.observedToolEvents == 3)
        #expect(try forward.report(since: nil, until: nil).totals.requests == 2)
    }

}
