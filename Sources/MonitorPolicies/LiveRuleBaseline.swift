import Foundation
import MonitorCore

/// Thresholds for live rules. Rates, lengths and sizes are compared with the user's own history
/// (`LiveBaseline`); the values here are multipliers and sample-size guards, not usage limits.
public struct LiveRuleConfiguration: Equatable, Sendable {
    /// A session is live when its newest request is at most this old.
    public let liveWindow: TimeInterval
    /// Recent window used to measure the current input rate.
    public let burnWindow: TimeInterval
    /// Current rate must exceed this multiple of the historical 90th percentile rate.
    public let burnMultiplier: Double
    /// Requests required in `burnWindow`, both now and in each historical bucket.
    public let minimumBurnRequests: Int
    /// Active historical buckets required before burn rate can be judged.
    public let minimumBaselineBuckets: Int
    /// Requests since the last human turn must exceed this multiple of the historical 90th percentile.
    public let loopMultiplier: Double
    /// Absolute floor for a runaway loop, so short histories cannot flag ordinary turns.
    public let minimumLoopRequests: Int
    /// Completed human-turn stretches required before a loop can be judged.
    public let minimumBaselineStretches: Int
    /// Consecutive requests (since the last compaction) examined for input growth.
    public let growthRequests: Int
    /// Newest input must be at least this multiple of the oldest examined input.
    public let growthRatio: Double
    /// Historical requests required before growth can be compared with the user's usual size.
    public let minimumBaselineRequests: Int
    /// Quota observations of the current window used for the projection.
    public let projectionWindow: TimeInterval
    /// Shortest observed span that gives a meaningful quota rate.
    public let projectionMinimumSpan: TimeInterval
    /// Newest quota observation may be at most this old.
    public let projectionFreshness: TimeInterval
    /// Projected exhaustion this close raises an error instead of a warning.
    public let criticalExhaustion: TimeInterval

    public init(
        liveWindow: TimeInterval = 900, burnWindow: TimeInterval = 600, burnMultiplier: Double = 3,
        minimumBurnRequests: Int = 3, minimumBaselineBuckets: Int = 20, loopMultiplier: Double = 2,
        minimumLoopRequests: Int = 10, minimumBaselineStretches: Int = 10, growthRequests: Int = 6,
        growthRatio: Double = 1.5, minimumBaselineRequests: Int = 50, projectionWindow: TimeInterval = 3_600,
        projectionMinimumSpan: TimeInterval = 600, projectionFreshness: TimeInterval = 900,
        criticalExhaustion: TimeInterval = 1_800
    ) {
        self.liveWindow = Self.positive(liveWindow, fallback: 900)
        self.burnWindow = Self.positive(burnWindow, fallback: 600)
        self.burnMultiplier = Self.atLeastOne(burnMultiplier, fallback: 3)
        self.minimumBurnRequests = max(2, minimumBurnRequests)
        self.minimumBaselineBuckets = max(5, minimumBaselineBuckets)
        self.loopMultiplier = Self.atLeastOne(loopMultiplier, fallback: 2)
        self.minimumLoopRequests = max(3, minimumLoopRequests)
        self.minimumBaselineStretches = max(5, minimumBaselineStretches)
        self.growthRequests = max(3, growthRequests)
        self.growthRatio = Self.atLeastOne(growthRatio, fallback: 1.5)
        self.minimumBaselineRequests = max(10, minimumBaselineRequests)
        self.projectionWindow = Self.positive(projectionWindow, fallback: 3_600)
        self.projectionMinimumSpan = Self.positive(projectionMinimumSpan, fallback: 600)
        self.projectionFreshness = Self.positive(projectionFreshness, fallback: 900)
        self.criticalExhaustion = Self.positive(criticalExhaustion, fallback: 1_800)
    }

    private static func positive(_ value: TimeInterval, fallback: TimeInterval) -> TimeInterval {
        value.isFinite && value > 0 ? value : fallback
    }

    private static func atLeastOne(_ value: Double, fallback: Double) -> Double {
        value.isFinite && value >= 1 ? value : fallback
    }
}

/// The user's own usage history, reduced to the distributions the live rules compare against.
public struct LiveBaseline: Equatable, Sendable {
    /// Known input tokens per minute for each active historical bucket.
    public let bucketRates: [Double]
    /// Requests between two consecutive human turns, for stretches fully inside the history.
    public let stretchLengths: [Int]
    /// Known input tokens of every historical request.
    public let requestInputs: [Int64]

    public static let empty = LiveBaseline(bucketRates: [], stretchLengths: [], requestInputs: [])

    public init(bucketRates: [Double], stretchLengths: [Int], requestInputs: [Int64]) {
        self.bucketRates = bucketRates
        self.stretchLengths = stretchLengths
        self.requestInputs = requestInputs
    }

    /// Nearest-rank percentile (`fraction` in 0...1) of a non-empty sample.
    static func percentile<T: Comparable>(_ values: [T], _ fraction: Double) -> T? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((fraction * Double(sorted.count)).rounded(.up))
        return sorted[min(sorted.count - 1, max(0, rank - 1))]
    }
}

/// Builds a baseline from sessions that are not live. Callers must not pass the sessions being
/// judged, otherwise a runaway session would raise its own threshold.
public enum LiveBaselineBuilder {
    public static func build(
        _ timelines: [RequestTimeline], bucket: TimeInterval = 600, configuration: LiveRuleConfiguration = .init()
    ) -> LiveBaseline {
        var rates: [Double] = []
        var stretches: [Int] = []
        var inputs: [Int64] = []
        for timeline in timelines {
            let requests = LiveRuleSupport.requests(timeline)
            inputs += requests.compactMap { LiveRuleSupport.input($0) }
            rates += bucketRates(requests, bucket: bucket, minimumRequests: configuration.minimumBurnRequests)
            stretches += completedStretches(timeline)
        }
        return LiveBaseline(bucketRates: rates, stretchLengths: stretches, requestInputs: inputs)
    }

    /// A bucket with any unknown request input is skipped rather than counted as zero.
    static func bucketRates(
        _ requests: [RequestTimelinePoint], bucket: TimeInterval, minimumRequests: Int
    ) -> [Double] {
        let width = max(1, bucket)
        let groups = Dictionary(grouping: requests) { Int(($0.timestamp.timeIntervalSince1970 / width).rounded(.down)) }
        return groups.values.compactMap { group in
            let known = group.compactMap { LiveRuleSupport.input($0) }
            guard group.count >= minimumRequests, known.count == group.count else { return nil }
            return Double(LiveRuleSupport.saturatingSum(known)) / (width / 60)
        }
    }

    /// Request counts between consecutive human-turn boundaries. The stretch before the first
    /// boundary and the one after the last are incomplete and never enter the baseline.
    static func completedStretches(_ timeline: RequestTimeline) -> [Int] {
        var result: [Int] = []
        var count: Int?
        for point in LiveRuleSupport.ordered(timeline) {
            switch point.kind {
            case .humanTurn, .goalTurn:
                if let count { result.append(count) }
                count = 0
            case .usageRequest:
                count = count.map { $0 + 1 }
            default:
                break
            }
        }
        return result
    }
}

enum LiveRuleSupport {
    static func ordered(_ timeline: RequestTimeline) -> [RequestTimelinePoint] {
        timeline.points.filter { $0.sessionID == timeline.sessionID }.sorted { lhs, rhs in
            lhs.timestamp == rhs.timestamp ? lhs.id < rhs.id : lhs.timestamp < rhs.timestamp
        }
    }

    static func requests(_ timeline: RequestTimeline) -> [RequestTimelinePoint] {
        ordered(timeline).filter { $0.kind == .usageRequest }
    }

    static func input(_ point: RequestTimelinePoint) -> Int64? {
        AnomalyPolicySupport.inputTokens(point)
    }

    static func saturatingSum(_ values: [Int64]) -> Int64 {
        values.reduce(0) { partial, value in
            let (sum, overflow) = partial.addingReportingOverflow(value)
            return overflow ? Int64.max : sum
        }
    }
}
