import MonitorCore
import MonitorPolicies

/// Presentation projection for one session in the current query snapshot.
/// The ratio is intentionally derived from session totals, never from request-level percentages.
struct SessionCacheHitPresentation: Equatable, Sendable {
    enum UnavailableReason: Equatable, Sendable {
        case noCanonicalRequests
        case partialCoverage(unknownRequests: Int64)
        case zeroInput
        case invalidTotals
    }

    enum Availability: Equatable, Sendable {
        case known(ratio: Double)
        case unavailable(reason: UnavailableReason)
    }

    let state: Availability

    init(totals: UsageTotals) {
        if totals.requests == 0 {
            state = .unavailable(reason: .noCanonicalRequests)
        } else if totals.unknownCacheRequests > 0 {
            state = .unavailable(reason: .partialCoverage(unknownRequests: totals.unknownCacheRequests))
        } else if totals.inputTokens == 0 {
            state = .unavailable(reason: .zeroInput)
        } else if HasCompleteCacheCoverageSpec().isSatisfiedBy(totals), let ratio = totals.cacheHitRatio {
            state = .known(ratio: ratio)
        } else {
            state = .unavailable(reason: .invalidTotals)
        }
    }

    var ratio: Double? {
        guard case let .known(ratio) = state else { return nil }
        return ratio
    }

    var value: String {
        guard let ratio else { return "—" }
        return ratio.formatted(.percent.precision(.fractionLength(1)))
    }

    var explanation: String {
        switch state {
        case .known:
            return "Cache hit is \(value), calculated from cached input tokens ÷ input tokens in this session snapshot."
        case .unavailable(reason: .noCanonicalRequests):
            return "Cache hit unavailable: this session has no confirmed canonical requests."
        case let .unavailable(reason: .partialCoverage(unknownRequests)):
            return "Cache hit unavailable: cache coverage is partial; \(unknownRequests.formatted()) "
                + "request(s) have unknown cache usage."
        case .unavailable(reason: .zeroInput):
            return "Cache hit unavailable: input tokens are zero, so a percentage cannot be calculated."
        case .unavailable(reason: .invalidTotals):
            return "Cache hit unavailable: cache coverage or input totals are incomplete."
        }
    }

    var accessibilityValue: String {
        ratio == nil ? "Unavailable. \(explanation)" : "\(value). \(explanation)"
    }
}
