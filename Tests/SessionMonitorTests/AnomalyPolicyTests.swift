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
        #expect(findings.map(\.kind) == [.startupOverhead, .repetitivePolling])
        #expect(findings.allSatisfy { finding in
            finding.evidence.inference.contains { $0.source == "specification_core_policy" }
        })
    }

    @Test func processWaitAndClockSleepAreNotPolling() throws {
        let points = [
            Self.request(id: "R1", turn: "T1", timestamp: 10, input: 100, cached: 80, session: "normal"),
            Self.request(id: "R2", turn: "T2", timestamp: 20, input: 100, cached: 80, session: "normal"),
            Self.request(id: "R3", turn: "T3", timestamp: 30, input: 100, cached: 80, session: "normal"),
            Self.event(id: "P1", timestamp: 9, class: .processWait, session: "normal"),
            Self.event(id: "P2", timestamp: 19, class: .processWait, session: "normal"),
            Self.event(id: "P3", timestamp: 29, class: .clockSleep, session: "normal")
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
                Self.request(id: "R1", turn: "T1", timestamp: 1, input: 1_000, cached: 1_000, session: "partial"),
                Self.request(id: "R2", turn: "T2", timestamp: 2, input: 1_000, cached: nil, session: "partial"),
                Self.request(id: "R3", turn: "T3", timestamp: 3, input: 1_000, cached: 0, session: "partial")
            ])
        )

        #expect(UnusualCacheChangeSpec().isSatisfiedBy(context))
        let finding = AnomalyPolicyEngine().evaluate(context).first { $0.kind == .cacheDrop }
        #expect(finding?.kind == .cacheDrop)
        #expect(finding?.coverage == .partial(
            reason: "Some request cache values were unknown and excluded from comparison."
        ))
        let encoded = try JSONEncoder().encode(finding)
        #expect(try JSONDecoder().decode(AnomalyFinding.self, from: encoded) == finding)
    }

    private static func request(
        id: String, turn: String, timestamp: TimeInterval, input: Int64, cached: Int64?,
        session: String = "session", model: String = "fixture"
    ) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: session, timestamp: Date(timeIntervalSince1970: timestamp),
            kind: .usageRequest, turnID: turn, responseID: id, cachedInputTokens: cached,
            uncachedInputTokens: cached.map { input - $0 }, model: model
        )
    }

    private static func wait(id: String, timestamp: TimeInterval) -> RequestTimelinePoint {
        Self.event(id: id, timestamp: timestamp, class: nil, kind: .wait)
    }

    private static func event(
        id: String, timestamp: TimeInterval, class activityClass: ActivityToolClass?,
        kind: TimelineEventKind = .tool, session: String = "session"
    ) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: session, timestamp: Date(timeIntervalSince1970: timestamp),
            kind: kind, sourceLine: Int(timestamp), activityClass: activityClass
        )
    }

    @Test func medianUsesValuesRatherThanChronologicalOrder() throws {
        let context = AnomalyPolicyContext(
            session: SessionSummary(id: "median", model: "fixture", totals: UsageTotals(requests: 5)),
            timeline: RequestTimeline(sessionID: "median", query: try UsageQuery(), points: [
                Self.request(id: "R1", turn: "first", timestamp: 1, input: 1_000, cached: 500, session: "median"),
                Self.request(id: "R2", turn: "first", timestamp: 2, input: 1_000, cached: 500, session: "median"),
                Self.request(id: "R3", turn: "later", timestamp: 3, input: 100, cached: 50, session: "median"),
                Self.request(id: "R4", turn: "later", timestamp: 4, input: 10_000, cached: 5_000, session: "median"),
                Self.request(id: "R5", turn: "later", timestamp: 5, input: 100, cached: 50, session: "median")
            ])
        )

        #expect(ExcessiveStartupSpec().isSatisfiedBy(context))
    }

    @Test func pollingPairsMustBelongToOneShortSequence() throws {
        let points = [
            Self.request(id: "R1", turn: "T1", timestamp: 1, input: 100, cached: 80),
            Self.request(id: "R2", turn: "T2", timestamp: 3_601, input: 100, cached: 80),
            Self.request(id: "R3", turn: "T3", timestamp: 7_201, input: 100, cached: 80),
            Self.wait(id: "W1", timestamp: 0), Self.wait(id: "W2", timestamp: 3_600),
            Self.wait(id: "W3", timestamp: 7_200)
        ]
        let context = AnomalyPolicyContext(
            session: SessionSummary(id: "session", model: "fixture", totals: UsageTotals(requests: 3)),
            timeline: RequestTimeline(sessionID: "session", query: try UsageQuery(), points: points)
        )

        #expect(!RepetitivePollingSpec().isSatisfiedBy(context))
    }

    @Test func pollingFindsSequenceBeforeLaterOutlierPair() throws {
        let points = [
            Self.request(id: "R1", turn: "T1", timestamp: 1, input: 100, cached: 80),
            Self.request(id: "R2", turn: "T2", timestamp: 3, input: 100, cached: 80),
            Self.request(id: "R3", turn: "T3", timestamp: 5, input: 100, cached: 80),
            Self.request(id: "R4", turn: "T4", timestamp: 10_000, input: 100, cached: 80),
            Self.wait(id: "W1", timestamp: 0), Self.wait(id: "W2", timestamp: 2),
            Self.wait(id: "W3", timestamp: 4), Self.wait(id: "W4", timestamp: 9_999)
        ]
        let context = AnomalyPolicyContext(
            session: SessionSummary(id: "session", model: "fixture", totals: UsageTotals(requests: 4)),
            timeline: RequestTimeline(sessionID: "session", query: try UsageQuery(), points: points)
        )

        #expect(RepetitivePollingSpec().isSatisfiedBy(context))
    }

    @Test func cacheRecoveryIsNotReportedAsDrop() throws {
        let context = AnomalyPolicyContext(
            session: SessionSummary(id: "recovery", model: "fixture", totals: UsageTotals(requests: 2)),
            timeline: RequestTimeline(sessionID: "recovery", query: try UsageQuery(), points: [
                Self.request(id: "R1", turn: "T1", timestamp: 1, input: 1_000, cached: 0, session: "recovery"),
                Self.request(id: "R2", turn: "T2", timestamp: 2, input: 1_000, cached: 1_000, session: "recovery")
            ])
        )

        let finding = AnomalyPolicyEngine().evaluate(context).first
        #expect(finding?.kind == .cacheRecovery)
        #expect(finding?.severity == .info)
    }

    @Test func cacheDropAndRecoveryAreReportedIndependently() throws {
        let context = AnomalyPolicyContext(
            session: SessionSummary(id: "volatile", model: "fixture", totals: UsageTotals(requests: 3)),
            timeline: RequestTimeline(sessionID: "volatile", query: try UsageQuery(), points: [
                Self.request(id: "V1", turn: "T1", timestamp: 1, input: 1_000, cached: 800, session: "volatile"),
                Self.request(id: "V2", turn: "T2", timestamp: 2, input: 1_000, cached: 200, session: "volatile"),
                Self.request(id: "V3", turn: "T3", timestamp: 3, input: 1_000, cached: 1_000, session: "volatile")
            ])
        )

        let findings = AnomalyPolicyEngine().evaluate(context)
        #expect(findings.contains { $0.kind == .cacheDrop })
        #expect(findings.contains { $0.kind == .cacheRecovery })
    }

    @Test func startupRequiresTwoKnownSamplesAndReportsPartialCoverage() throws {
        let insufficient = AnomalyPolicyContext(
            session: SessionSummary(id: "insufficient", model: "fixture", totals: UsageTotals(requests: 3)),
            timeline: RequestTimeline(sessionID: "insufficient", query: try UsageQuery(), points: [
                Self.request(
                    id: "I1", turn: "first", timestamp: 1, input: 1_000, cached: 900, session: "insufficient"
                ),
                Self.request(
                    id: "I2", turn: "first", timestamp: 2, input: 1_000, cached: nil, session: "insufficient"
                ),
                Self.request(
                    id: "I3", turn: "later", timestamp: 3, input: 400, cached: 300, session: "insufficient"
                )
            ])
        )
        #expect(!ExcessiveStartupSpec().isSatisfiedBy(insufficient))

        let partial = AnomalyPolicyContext(
            session: SessionSummary(id: "partial-startup", model: "fixture", totals: UsageTotals(requests: 4)),
            timeline: RequestTimeline(sessionID: "partial-startup", query: try UsageQuery(), points: [
                Self.request(
                    id: "P1", turn: "first", timestamp: 1, input: 1_000, cached: 900, session: "partial-startup"
                ),
                Self.request(
                    id: "P2", turn: "first", timestamp: 2, input: 1_000, cached: 900, session: "partial-startup"
                ),
                Self.request(
                    id: "P3", turn: "first", timestamp: 3, input: 1_000, cached: nil, session: "partial-startup"
                ),
                Self.request(id: "P4", turn: "later", timestamp: 4, input: 400, cached: 300, session: "partial-startup")
            ])
        )
        let finding = AnomalyPolicyEngine().evaluate(partial).first { $0.kind == .startupOverhead }
        #expect(finding?.coverage == .partial(
            reason: "Some first-turn cache values were unknown and excluded from startup comparison."
        ))
    }

    @Test func highUsageAndDominantSessionRemainIndependentFromCacheRatio() throws {
        let dominant = SessionSummary(
            id: "dominant", model: "fixture",
            totals: UsageTotals(requests: 10, inputTokens: 10_000, cachedInputTokens: 9_900)
        )
        let peer = SessionSummary(
            id: "peer", model: "fixture",
            totals: UsageTotals(requests: 2, inputTokens: 1_000, cachedInputTokens: 900)
        )
        let context = AnomalyPolicyContext(
            session: dominant,
            timeline: RequestTimeline(sessionID: "dominant", query: try UsageQuery(), points: []),
            cohort: [dominant, peer]
        )
        let configuration = AnomalyPolicyConfiguration(
            minimumAbsoluteInputTokens: 5_000, minimumAbsoluteRequests: 100,
            dominantSessionShare: 0.5, minimumDominantInputTokens: 5_000
        )

        let findings = AnomalyPolicyEngine(configuration: configuration).evaluate(context)
        #expect(findings.contains { $0.kind == .highAbsoluteUsage })
        #expect(findings.contains { $0.kind == .dominantSession })
    }

    @Test func uncachedBurstUsesAbsoluteAndRatioThresholds() throws {
        let context = AnomalyPolicyContext(
            session: SessionSummary(id: "burst", model: "fixture", totals: UsageTotals(requests: 1)),
            timeline: RequestTimeline(sessionID: "burst", query: try UsageQuery(), points: [
                Self.request(id: "B1", turn: "T1", timestamp: 1, input: 2_000, cached: 500, session: "burst")
            ])
        )
        let configuration = AnomalyPolicyConfiguration(minimumUncachedInputTokens: 1_000)
        let findings = AnomalyPolicyEngine(configuration: configuration).evaluate(context)

        #expect(findings.contains { $0.kind == .uncachedBurst })
    }

    @Test func invalidConfigurationFallsBackToSafeValues() {
        let configuration = AnomalyPolicyConfiguration(
            minimumPollingPairs: 0, pollingPairWindow: .infinity, pollingSequenceWindow: .nan,
            startupMultiplier: .nan, minimumCacheSamples: 0, cacheChangeRatio: 2,
            minimumCacheInputTokens: 0, cacheComparisonWindow: -.infinity
        )

        #expect(configuration.minimumPollingPairs == 1)
        #expect(configuration.pollingPairWindow == 60)
        #expect(configuration.pollingSequenceWindow == 300)
        #expect(configuration.startupMultiplier == 2)
        #expect(configuration.minimumCacheSamples == 2)
        #expect(configuration.cacheChangeRatio == 1)
        #expect(configuration.minimumCacheInputTokens == 1)
        #expect(configuration.cacheComparisonWindow == 3_600)
    }
}
