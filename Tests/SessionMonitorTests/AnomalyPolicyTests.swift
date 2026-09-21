import Foundation
import MonitorCore
import MonitorPolicies
import Testing

struct AnomalyPolicyTests {
    @Test func policyEngineEvaluatesIndependentSignals() throws {
        let context = AnomalyPolicyContext(
            session: SessionSummary(
                id: "session", model: "fixture",
                totals: UsageTotals(requests: 4, inputTokens: 4_400, cachedInputTokens: 3_960, outputTokens: 10)
            ),
            timeline: RequestTimeline(sessionID: "session", query: try UsageQuery(), points: [
                Self.request(id: "R1", turn: "first", timestamp: 1, input: 1_000, cached: 900),
                Self.request(id: "R2", turn: "first", timestamp: 3, input: 1_000, cached: 900),
                Self.wait(id: "W1", timestamp: 2),
                Self.request(id: "R3", turn: "later", timestamp: 5, input: 200, cached: 180),
                Self.wait(id: "W2", timestamp: 4),
                Self.request(id: "R4", turn: "later", timestamp: 7, input: 200, cached: 180),
                Self.wait(id: "W3", timestamp: 6)
            ])
        )

        let findings = AnomalyPolicyEngine().evaluate(context)
        #expect(findings.map(\.id) == ["excessive_startup_overhead", "repetitive_polling"])
        #expect(findings.allSatisfy { finding in
            finding.evidence.inference.contains { $0.source == "specification_core_policy" }
        })
    }

    @Test func processWaitAndClockSleepAreNotPolling() throws {
        let points = [
            Self.request(id: "R1", turn: "T1", timestamp: 10, input: 100, cached: 80),
            Self.request(id: "R2", turn: "T2", timestamp: 20, input: 100, cached: 80),
            Self.request(id: "R3", turn: "T3", timestamp: 30, input: 100, cached: 80),
            Self.event(id: "P1", timestamp: 9, class: .processWait),
            Self.event(id: "P2", timestamp: 19, class: .processWait),
            Self.event(id: "P3", timestamp: 29, class: .clockSleep)
        ]
        let context = AnomalyPolicyContext(
            session: SessionSummary(id: "normal", model: "fixture", totals: UsageTotals(requests: 3, inputTokens: 300)),
            timeline: RequestTimeline(sessionID: "normal", query: try UsageQuery(), points: points)
        )

        #expect(!RepetitivePollingSpec().isSatisfiedBy(context))
        #expect(!AnomalyPolicyEngine().evaluate(context).contains { $0.id == "repetitive_polling" })
    }

    @Test func unknownCacheDoesNotBecomeCacheChangeSignal() throws {
        let context = AnomalyPolicyContext(
            session: SessionSummary(id: "partial", model: "fixture", totals: UsageTotals(requests: 3)),
            timeline: RequestTimeline(sessionID: "partial", query: try UsageQuery(), points: [
                Self.request(id: "R1", turn: "T1", timestamp: 1, input: 100, cached: 100),
                Self.request(id: "R2", turn: "T2", timestamp: 2, input: 100, cached: nil),
                Self.request(id: "R3", turn: "T3", timestamp: 3, input: 100, cached: 0)
            ])
        )

        #expect(UnusualCacheChangeSpec().isSatisfiedBy(context))
        let finding = AnomalyPolicyEngine().evaluate(context).first { $0.id == "unusual_cache_changes" }
        #expect(finding?.coverage == .partial(
            reason: "Some request cache values were unknown and excluded from comparison."
        ))
        let encoded = try JSONEncoder().encode(finding)
        #expect(try JSONDecoder().decode(AnomalyFinding.self, from: encoded) == finding)
    }

    private static func request(
        id: String, turn: String, timestamp: TimeInterval, input: Int64, cached: Int64?
    ) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: "session", timestamp: Date(timeIntervalSince1970: timestamp),
            kind: .usageRequest, turnID: turn, responseID: id, cachedInputTokens: cached,
            uncachedInputTokens: cached.map { input - $0 }
        )
    }

    private static func wait(id: String, timestamp: TimeInterval) -> RequestTimelinePoint {
        Self.event(id: id, timestamp: timestamp, class: nil, kind: .wait)
    }

    private static func event(
        id: String, timestamp: TimeInterval, class activityClass: ActivityToolClass?, kind: TimelineEventKind = .tool
    ) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: "session", timestamp: Date(timeIntervalSince1970: timestamp),
            kind: kind, sourceLine: Int(timestamp), activityClass: activityClass
        )
    }
}
