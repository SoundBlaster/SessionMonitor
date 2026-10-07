import Foundation
import MonitorCore
@testable import MonitorPolicies
import SpecificationCore
import Testing

/// Each requirement is a Specification of its own, so it is tested apart from the rule that orders them.
struct LiveRuleSpecsTests {
    private static func context(
        _ points: [RequestTimelinePoint], baseline: LiveBaseline = LiveRulesTests.baseline
    ) throws -> LiveRuleContext {
        LiveRuleContext(
            timeline: try LiveRulesTests.timeline(points), baseline: baseline, now: LiveRulesTests.now,
            configuration: LiveRulesTests.configuration
        )
    }

    @Test func liveSessionNeedsARecentRequest() throws {
        #expect(IsLiveSessionSpec().isSatisfiedBy(try Self.context(LiveRulesTests.burst())))
        let old = [LiveRulesTests.request(1, secondsAgo: 3_600, input: 1)]
        #expect(!IsLiveSessionSpec().isSatisfiedBy(try Self.context(old)))
        #expect(!IsLiveSessionSpec().isSatisfiedBy(try Self.context([])))
    }

    @Test func burnRequirementsAreIndependent() throws {
        let burst = try Self.context(LiveRulesTests.burst())
        #expect(HasEnoughBurnRequestsSpec().isSatisfiedBy(burst))
        #expect(HasKnownBurnInputSpec().isSatisfiedBy(burst))
        #expect(HasBurnBaselineSpec().isSatisfiedBy(burst))
        #expect(ExceedsBurnThresholdSpec().isSatisfiedBy(burst))

        let unknown = try Self.context(LiveRulesTests.burst(unknownAt: 1))
        #expect(!HasKnownBurnInputSpec().isSatisfiedBy(unknown))
        #expect(!HasEnoughBurnRequestsSpec().isSatisfiedBy(try Self.context(LiveRulesTests.burst(count: 2))))
        #expect(!ExceedsBurnThresholdSpec().isSatisfiedBy(try Self.context(LiveRulesTests.burst(input: 5_000))))
        let flat = LiveBaseline(bucketRates: Array(repeating: 0, count: 8), stretchLengths: [], requestInputs: [])
        #expect(!HasBurnBaselineSpec().isSatisfiedBy(try Self.context(LiveRulesTests.burst(), baseline: flat)))
    }

    @Test func loopRequirementsAreIndependent() throws {
        let loop = try Self.context(LiveRulesTests.loop(requests: 12))
        #expect(HasHumanBoundarySpec().isSatisfiedBy(loop))
        #expect(HasLoopBaselineSpec().isSatisfiedBy(loop))
        #expect(ExceedsLoopThresholdSpec().isSatisfiedBy(loop))
        #expect(!ExceedsLoopThresholdSpec().isSatisfiedBy(try Self.context(LiveRulesTests.loop(requests: 6))))
        let bare = (0..<12).map { LiveRulesTests.request($0, secondsAgo: 800 - Double($0 * 10), input: 1) }
        #expect(!HasHumanBoundarySpec().isSatisfiedBy(try Self.context(bare)))
        let short = LiveBaseline(bucketRates: [], stretchLengths: [3], requestInputs: [])
        #expect(!HasLoopBaselineSpec().isSatisfiedBy(try Self.context(bare, baseline: short)))
    }

    @Test func growthRequirementsAreIndependent() throws {
        let growing = try Self.context(LiveRulesTests.growth([800, 1_000, 1_300, 1_600]))
        #expect(HasFullGrowthWindowSpec().isSatisfiedBy(growing))
        #expect(HasKnownGrowthInputSpec().isSatisfiedBy(growing))
        #expect(IsGrowingInputSpec().isSatisfiedBy(growing))
        #expect(HasGrowthBaselineSpec().isSatisfiedBy(growing))
        #expect(ReachesUsualRequestSizeSpec().isSatisfiedBy(growing))

        let wobbling = try Self.context(LiveRulesTests.growth([800, 1_300, 1_000, 1_600]))
        let small = try Self.context(LiveRulesTests.growth([100, 200, 300, 400]))
        let missing = try Self.context(LiveRulesTests.growth([800, nil, 1_300, 1_600]))
        #expect(!IsGrowingInputSpec().isSatisfiedBy(wobbling))
        #expect(!ReachesUsualRequestSizeSpec().isSatisfiedBy(small))
        #expect(!HasKnownGrowthInputSpec().isSatisfiedBy(missing))
        #expect(!HasFullGrowthWindowSpec().isSatisfiedBy(
            try Self.context(LiveRulesTests.growth([800, 1_000, 1_300, 1_600], compactionAfter: 2))
        ))
    }

    @Test func blockersNameWhyARuleCannotAlert() throws {
        let configuration = LiveRulesTests.configuration
        let finished = try Self.context([LiveRulesTests.request(1, secondsAgo: 3_600, input: 1)])
        #expect(LiveRuleBlockers.burn(configuration).decide(finished) == .quiet)
        let unknown = try Self.context(LiveRulesTests.burst(unknownAt: 1))
        if case .unknown? = LiveRuleBlockers.burn(configuration).decide(unknown) {} else {
            Issue.record("unknown input must block as unknown")
        }
        // A rule that passes every requirement has no blocker, so its decision builds the alert.
        #expect(LiveRuleBlockers.burn(configuration).decide(try Self.context(LiveRulesTests.burst())) == nil)
        if case .alert? = BurnRateDecision().decide(try Self.context(LiveRulesTests.burst())) {} else {
            Issue.record("expected an alert")
        }
    }
}
