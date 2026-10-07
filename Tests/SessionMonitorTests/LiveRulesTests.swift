import Foundation
import MonitorCore
@testable import MonitorPolicies
import Testing

struct LiveRulesTests {
    static let now = Date(timeIntervalSince1970: 1_000_000)
    static let configuration = LiveRuleConfiguration(
        minimumBaselineBuckets: 5, minimumLoopRequests: 4, minimumBaselineStretches: 5, growthRequests: 4,
        minimumBaselineRequests: 10
    )

    /// Busy history: 10-minute buckets at 1 000 tokens/min, turns of 3 requests, requests of 1 000 tokens.
    static let baseline = LiveBaseline(
        bucketRates: Array(repeating: 1_000, count: 8), stretchLengths: Array(repeating: 3, count: 8),
        requestInputs: Array(repeating: 1_000, count: 20)
    )

    static func request(_ index: Int, secondsAgo: TimeInterval, input: Int64?) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: "r\(index)", sessionID: "s", timestamp: now.addingTimeInterval(-secondsAgo), kind: .usageRequest,
            sourceLine: index, responseID: "resp\(index)", inputTokens: input
        )
    }

    static func marker(_ kind: TimelineEventKind, _ index: Int, secondsAgo: TimeInterval) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: "m\(index)", sessionID: "s", timestamp: now.addingTimeInterval(-secondsAgo), kind: kind,
            sourceLine: 100 + index
        )
    }

    static func timeline(_ points: [RequestTimelinePoint]) throws -> RequestTimeline {
        RequestTimeline(sessionID: "s", query: try UsageQuery(), points: points)
    }

    static func outcome(
        _ rule: String, _ points: [RequestTimelinePoint], baseline: LiveBaseline = baseline
    ) throws -> LiveRuleOutcome {
        let outcomes = LiveRules.outcomes(
            try timeline(points), baseline: baseline, now: now, configuration: configuration
        )
        return try #require(outcomes.first { $0.0 == rule }).1
    }

    static func burst(input: Int64 = 100_000, count: Int = 5, unknownAt: Int? = nil) -> [RequestTimelinePoint] {
        (0..<count).map { request($0, secondsAgo: Double(30 + $0 * 60), input: $0 == unknownAt ? nil : input) }
    }

    // MARK: burn rate

    @Test func burnRateRaisesWhenPaceExceedsOwnHistory() throws {
        guard case let .alert(candidate) = try Self.outcome("burn_rate", Self.burst()) else {
            Issue.record("expected an alert")
            return
        }
        #expect(candidate.key == "live|burn_rate|s")
        #expect(candidate.source == .liveRule)
        #expect(candidate.severity == .warning)
        #expect(candidate.coverage == .observed)
        #expect(candidate.sessionIDs == ["s"])
        #expect(candidate.evidence.observed.first?.responseIDs.count == 5)
        #expect(candidate.evidence.inference.first?.source == "own_history")
        #expect(!candidate.evidence.limitations.isEmpty)
    }

    @Test func burnRateStaysQuietAtOrBelowThreshold() throws {
        // 5 × 5 000 tokens in 10 minutes = 2 500 tokens/min, under 3 × the 1 000 tokens/min baseline.
        #expect(try Self.outcome("burn_rate", Self.burst(input: 5_000)) == .quiet)
    }

    @Test func burnRateIsUnknownNotZeroWhenInputOrHistoryIsMissing() throws {
        if case .unknown = try Self.outcome("burn_rate", Self.burst(unknownAt: 2)) {} else {
            Issue.record("unknown input must give unknown")
        }
        let shortHistory = LiveBaseline(bucketRates: [1_000, 1_000], stretchLengths: [], requestInputs: [])
        if case .unknown = try Self.outcome("burn_rate", Self.burst(), baseline: shortHistory) {} else {
            Issue.record("short history must give unknown")
        }
        #expect(LiveRules.sessionSignals(
            timelines: [try Self.timeline(Self.burst(unknownAt: 2))], baseline: Self.baseline, now: Self.now,
            configuration: Self.configuration
        ).candidates.isEmpty)
    }

    @Test func burnRateIgnoresFinishedAndSparseSessions() throws {
        let finished = (0..<5).map { Self.request($0, secondsAgo: 3_600 + Double($0 * 60), input: 100_000) }
        #expect(try Self.outcome("burn_rate", finished) == .quiet)
        #expect(try Self.outcome("burn_rate", Self.burst(count: 2)) == .quiet)
    }

    // MARK: runaway loop

    static func loop(requests: Int, boundary: TimelineEventKind = .humanTurn) -> [RequestTimelinePoint] {
        [Self.marker(boundary, 1, secondsAgo: 900)]
            + (0..<requests).map { Self.request($0, secondsAgo: 800 - Double($0 * 10), input: 10) }
    }

    @Test func runawayLoopRaisesAboveOwnTurnLength() throws {
        guard case let .alert(candidate) = try Self.outcome("runaway_loop", Self.loop(requests: 12)) else {
            Issue.record("expected an alert")
            return
        }
        #expect(candidate.key == "live|runaway_loop|s")
        #expect(candidate.message.contains("12 requests"))
        #expect(candidate.evidence.observed.first?.sourceLines.count == 10)
    }

    @Test func runawayLoopHonoursFloorTurnBoundariesAndUnknowns() throws {
        // 3 usual requests per turn × 2 = 6, but the absolute floor is 4: 6 requests do not exceed 6.
        #expect(try Self.outcome("runaway_loop", Self.loop(requests: 6)) == .quiet)
        // A goal turn is a boundary too, so the stretch restarts.
        let withGoal = Self.loop(requests: 12) + [Self.marker(.goalTurn, 2, secondsAgo: 60)]
        #expect(try Self.outcome("runaway_loop", withGoal) == .quiet)
        // No human turn in the window: the length of the stretch is unknown.
        let none = (0..<12).map { Self.request($0, secondsAgo: 800 - Double($0 * 10), input: 10) }
        if case .unknown = try Self.outcome("runaway_loop", none) {} else { Issue.record("expected unknown") }
        let shortHistory = LiveBaseline(bucketRates: [], stretchLengths: [3], requestInputs: [])
        if case .unknown = try Self.outcome("runaway_loop", Self.loop(requests: 12), baseline: shortHistory) {} else {
            Issue.record("expected unknown")
        }
    }

    // MARK: input growth

    static func growth(_ inputs: [Int64?], compactionAfter: Int? = nil) -> [RequestTimelinePoint] {
        var points = inputs.enumerated().map { index, input in
            Self.request(index, secondsAgo: 600 - Double(index * 60), input: input)
        }
        if let compactionAfter {
            points.append(Self.marker(.compaction, 1, secondsAgo: 600 - Double(compactionAfter * 60) + 1))
        }
        return points
    }

    @Test func inputGrowthIsInformationalAndNeedsOwnHistory() throws {
        let growing = Self.growth([800, 1_000, 1_300, 1_600])
        guard case let .alert(candidate) = try Self.outcome("input_growth", growing) else {
            Issue.record("expected an alert")
            return
        }
        #expect(candidate.severity == .info)
        #expect(candidate.kind == "input_growth")
        let short = LiveBaseline(bucketRates: [], stretchLengths: [], requestInputs: [1_000])
        if case .unknown = try Self.outcome("input_growth", growing, baseline: short) {
        } else {
            Issue.record("expected unknown")
        }
    }

    @Test func inputGrowthNegativeCases() throws {
        // Not monotonic.
        #expect(try Self.outcome("input_growth", Self.growth([800, 1_300, 1_000, 1_600])) == .quiet)
        // Growth below the ratio.
        #expect(try Self.outcome("input_growth", Self.growth([1_000, 1_100, 1_200, 1_300])) == .quiet)
        // Still below the user's usual large request.
        #expect(try Self.outcome("input_growth", Self.growth([100, 200, 300, 400])) == .quiet)
        // A compaction inside the window leaves too few requests after it.
        #expect(try Self.outcome("input_growth", Self.growth([800, 1_000, 1_300, 1_600], compactionAfter: 2)) == .quiet)
        // Unknown input is not zero.
        if case .unknown = try Self.outcome("input_growth", Self.growth([800, nil, 1_300, 1_600])) {} else {
            Issue.record("expected unknown")
        }
    }

    // MARK: signals and baseline

    @Test func quietRulesEvaluateScopesSoOldAlertsResolve() throws {
        let finished = (0..<5).map { Self.request($0, secondsAgo: 3_600 + Double($0 * 60), input: 100_000) }
        let batch = LiveRules.sessionSignals(
            timelines: [try Self.timeline(finished)], baseline: Self.baseline, now: Self.now,
            configuration: Self.configuration
        )
        #expect(batch.candidates.isEmpty)
        #expect(batch.scopes == Set(LiveRules.kinds.map { LiveRules.scope($0, "s") }))
    }

    @Test func baselineSkipsUnknownBucketsAndIncompleteStretches() throws {
        let points = [
            Self.request(1, secondsAgo: 5_000, input: 1_000), Self.request(2, secondsAgo: 4_990, input: 1_000),
            Self.request(3, secondsAgo: 4_980, input: 1_000),
            Self.request(4, secondsAgo: 2_000, input: 1_000), Self.request(5, secondsAgo: 1_990, input: nil),
            Self.request(6, secondsAgo: 1_980, input: 1_000)
        ]
        let rates = LiveBaselineBuilder.bucketRates(
            points.sorted { $0.timestamp < $1.timestamp }, bucket: 600, minimumRequests: 3
        )
        #expect(rates == [300])

        let stretched = [
            Self.request(1, secondsAgo: 900, input: 1), Self.marker(.humanTurn, 1, secondsAgo: 800),
            Self.request(2, secondsAgo: 700, input: 1), Self.request(3, secondsAgo: 600, input: 1),
            Self.marker(.humanTurn, 2, secondsAgo: 500), Self.request(4, secondsAgo: 400, input: 1)
        ]
        #expect(LiveBaselineBuilder.completedStretches(try Self.timeline(stretched)) == [2])
    }

    @Test func percentileUsesNearestRank() {
        #expect(LiveBaseline.percentile([1, 2, 3, 4, 5, 6, 7, 8, 9, 10], 0.9) == 9)
        #expect(LiveBaseline.percentile([Int](), 0.9) == nil)
        #expect(LiveBaseline.percentile([5], 0.9) == 5)
    }

    @Test func configurationRejectsNonsenseValues() {
        let configuration = LiveRuleConfiguration(
            liveWindow: .nan, burnMultiplier: 0.2, minimumBaselineBuckets: 0, growthRatio: .infinity
        )
        #expect(configuration.liveWindow == 900)
        #expect(configuration.burnMultiplier == 3)
        #expect(configuration.minimumBaselineBuckets == 5)
        #expect(configuration.growthRatio == 1.5)
    }
}
