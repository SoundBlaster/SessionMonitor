import MonitorCore
import SpecificationCore

/// The supported range for the user-configured minimum cache hit percentage.
public struct CacheHitThresholdSpec: Specification {
    public init() {}

    public func isSatisfiedBy(_ candidate: Double) -> Bool {
        candidate.isFinite && (0...100).contains(candidate)
    }
}

public enum CacheHitThresholdValidationError: Error, Equatable, Sendable {
    case outOfRange
    case nonFinite
}

/// A validated threshold used by cache-hit presentation decisions.
public struct CacheHitThreshold: Equatable, Sendable {
    public static let `default` = CacheHitThreshold(uncheckedPercent: 80)

    public let percent: Double

    public init(percent: Double) throws {
        guard percent.isFinite else { throw CacheHitThresholdValidationError.nonFinite }
        guard CacheHitThresholdSpec().isSatisfiedBy(percent) else {
            throw CacheHitThresholdValidationError.outOfRange
        }
        self.percent = percent
    }

    private init(uncheckedPercent percent: Double) { self.percent = percent }
}

/// Pure, non-mutating projection for one canonical session summary.
public struct CacheHitThresholdPolicy: Sendable {
    public enum Presentation: Equatable, Sendable {
        case knownBelowThreshold(cacheHitPercent: Double, thresholdPercent: Double)
        case knownAtThreshold(cacheHitPercent: Double, thresholdPercent: Double)
        case knownAboveThreshold(cacheHitPercent: Double, thresholdPercent: Double)
        case unknown
        case partialCacheCoverage(unknownRequests: Int64)
        case zeroInput
        case noCanonicalRequests
    }

    public let threshold: CacheHitThreshold

    public init(threshold: CacheHitThreshold) { self.threshold = threshold }

    public func presentation(for session: SessionSummary) -> Presentation {
        let totals = session.totals
        guard totals.requests > 0 else { return .noCanonicalRequests }
        guard totals.unknownCacheRequests == 0 else {
            return .partialCacheCoverage(unknownRequests: totals.unknownCacheRequests)
        }
        guard totals.inputTokens > 0 else { return .zeroInput }
        guard totals.cachedInputTokens >= 0, totals.cachedInputTokens <= totals.inputTokens,
              let ratio = totals.cacheHitRatio, ratio.isFinite else { return .unknown }

        let cacheHitPercent = ratio * 100
        if cacheHitPercent < threshold.percent {
            return .knownBelowThreshold(
                cacheHitPercent: cacheHitPercent, thresholdPercent: threshold.percent
            )
        }
        if cacheHitPercent == threshold.percent {
            return .knownAtThreshold(
                cacheHitPercent: cacheHitPercent, thresholdPercent: threshold.percent
            )
        }
        return .knownAboveThreshold(
            cacheHitPercent: cacheHitPercent, thresholdPercent: threshold.percent
        )
    }
}
