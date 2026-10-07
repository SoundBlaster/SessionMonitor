import Foundation
import MonitorCore
import SpecificationCore

// MARK: - Measures

/// Values the live-rule specifications and decisions share, derived from one session's evidence.
extension LiveRuleContext {
    var burnRequests: [RequestTimelinePoint] {
        let start = now.addingTimeInterval(-configuration.burnWindow)
        return requests.filter { $0.timestamp > start && $0.timestamp <= now }
    }

    var burnKnownInputs: [Int64] { burnRequests.compactMap(LiveRuleSupport.input) }

    var burnRate: Double { Double(LiveRuleSupport.saturatingSum(burnKnownInputs)) / (configuration.burnWindow / 60) }

    /// The user's usual busy pace; `nil` while the history is too short or has no positive pace.
    var burnReference: Double? {
        let rates = baseline.bucketRates
        guard rates.count >= configuration.minimumBaselineBuckets,
              let reference = LiveBaseline.percentile(rates, 0.9), reference > 0 else { return nil }
        return reference
    }

    var burnThreshold: Double? { burnReference.map { $0 * configuration.burnMultiplier } }

    var lastBoundaryIndex: Int? { points.lastIndex { $0.kind == .humanTurn || $0.kind == .goalTurn } }

    var stretchRequests: [RequestTimelinePoint] {
        guard let boundary = lastBoundaryIndex else { return [] }
        return points[(boundary + 1)...].filter { $0.kind == .usageRequest }
    }

    var loopReference: Int? {
        let lengths = baseline.stretchLengths
        return lengths.count >= configuration.minimumBaselineStretches ? LiveBaseline.percentile(lengths, 0.9) : nil
    }

    var loopThreshold: Double? {
        loopReference.map { max(Double(configuration.minimumLoopRequests), Double($0) * configuration.loopMultiplier) }
    }

    /// The newest requests since the last compaction, as many as the growth rule examines.
    var growthWindow: [RequestTimelinePoint] {
        let start = points.lastIndex { $0.kind == .compaction }.map { $0 + 1 } ?? 0
        return Array(points[start...].filter { $0.kind == .usageRequest }.suffix(configuration.growthRequests))
    }

    var growthInputs: [Int64] { growthWindow.compactMap(LiveRuleSupport.input) }

    var growthReference: Int64? {
        let history = baseline.requestInputs
        return history.count >= configuration.minimumBaselineRequests ? LiveBaseline.percentile(history, 0.9) : nil
    }
}

// MARK: - Specifications

/// Only sessions with a request inside the live window are judged; finished work is history.
struct IsLiveSessionSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        guard let newest = context.requests.last?.timestamp else { return false }
        let age = context.now.timeIntervalSince(newest)
        return age >= 0 && age <= context.configuration.liveWindow
    }
}

struct HasEnoughBurnRequestsSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        context.burnRequests.count >= context.configuration.minimumBurnRequests
    }
}

/// Unknown input is never counted as zero: one unknown request makes the whole window unknown.
struct HasKnownBurnInputSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        context.burnKnownInputs.count == context.burnRequests.count
    }
}

struct HasBurnBaselineSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool { context.burnReference != nil }
}

struct ExceedsBurnThresholdSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        context.burnThreshold.map { context.burnRate > $0 } ?? false
    }
}

struct HasHumanBoundarySpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool { context.lastBoundaryIndex != nil }
}

struct HasLoopBaselineSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool { context.loopReference != nil }
}

struct ExceedsLoopThresholdSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        context.loopThreshold.map { Double(context.stretchRequests.count) > $0 } ?? false
    }
}

struct HasFullGrowthWindowSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        context.growthWindow.count == context.configuration.growthRequests
    }
}

struct HasKnownGrowthInputSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        context.growthInputs.count == context.growthWindow.count
    }
}

/// Input never decreases across the window and ends at least `growthRatio` above where it started.
struct IsGrowingInputSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        let inputs = context.growthInputs
        guard let first = inputs.first, let last = inputs.last, first > 0 else { return false }
        return zip(inputs, inputs.dropFirst()).allSatisfy { $0 <= $1 }
            && Double(last) >= Double(first) * context.configuration.growthRatio
    }
}

struct HasGrowthBaselineSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool { context.growthReference != nil }
}

struct ReachesUsualRequestSizeSpec: Specification {
    func isSatisfiedBy(_ context: LiveRuleContext) -> Bool {
        guard let last = context.growthInputs.last, let reference = context.growthReference else { return false }
        return last >= reference
    }
}

// MARK: - Ordered blockers

/// The first unmet requirement names why a rule cannot alert: `quiet` is a clear negative that lets an
/// existing alert resolve, `unknown` is missing evidence that leaves it untouched.
enum LiveRuleBlockers {
    typealias Match = FirstMatchSpec<LiveRuleContext, LiveRuleOutcome>
    typealias Blocker = Match.SpecificationPair

    static func requiring<S: Specification>(_ spec: S, otherwise outcome: LiveRuleOutcome) -> Blocker
        where S.T == LiveRuleContext {
        (AnySpecification(spec.not()), outcome)
    }

    static func burn(_ configuration: LiveRuleConfiguration) -> Match {
        let blockers: [Blocker] = [
            requiring(IsLiveSessionSpec(), otherwise: .quiet),
            requiring(HasEnoughBurnRequestsSpec(), otherwise: .quiet),
            requiring(
                HasKnownBurnInputSpec(),
                otherwise: .unknown("Input tokens are unknown for some requests in the recent window.")
            ),
            requiring(
                HasBurnBaselineSpec(),
                otherwise: .unknown("Fewer than \(configuration.minimumBaselineBuckets) active historical intervals.")
            ),
            requiring(ExceedsBurnThresholdSpec(), otherwise: .quiet)
        ]
        return Match(blockers)
    }

    static func loop(_ configuration: LiveRuleConfiguration) -> Match {
        let blockers: [Blocker] = [
            requiring(IsLiveSessionSpec(), otherwise: .quiet),
            requiring(HasHumanBoundarySpec(), otherwise: .unknown("No human turn is inside the evaluated window.")),
            requiring(
                HasLoopBaselineSpec(),
                otherwise: .unknown("Fewer than \(configuration.minimumBaselineStretches) completed historical turns.")
            ),
            requiring(ExceedsLoopThresholdSpec(), otherwise: .quiet)
        ]
        return Match(blockers)
    }

    static func growth(_ configuration: LiveRuleConfiguration) -> Match {
        let blockers: [Blocker] = [
            requiring(IsLiveSessionSpec(), otherwise: .quiet),
            requiring(HasFullGrowthWindowSpec(), otherwise: .quiet),
            requiring(
                HasKnownGrowthInputSpec(),
                otherwise: .unknown("Input tokens are unknown for some recent requests.")
            ),
            requiring(IsGrowingInputSpec(), otherwise: .quiet),
            requiring(
                HasGrowthBaselineSpec(),
                otherwise: .unknown("Fewer than \(configuration.minimumBaselineRequests) historical requests.")
            ),
            requiring(ReachesUsualRequestSizeSpec(), otherwise: .quiet)
        ]
        return Match(blockers)
    }
}
