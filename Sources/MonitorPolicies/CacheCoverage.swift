import MonitorCore
import SpecificationCore

public struct HasCompleteCacheCoverageSpec: Specification {
    public init() {}

    public func isSatisfiedBy(_ candidate: UsageTotals) -> Bool {
        candidate.requests > 0 && candidate.unknownCacheRequests == 0 && candidate.inputTokens > 0
    }
}

public struct CacheCoverageDecision: DecisionSpec {
    public init() {}

    public func decide(_ context: UsageTotals) -> String? {
        guard context.requests > 0 else { return "No confirmed canonical requests in this selection." }
        guard HasCompleteCacheCoverageSpec().isSatisfiedBy(context) else {
            return "Cache hit is unavailable: cache data is incomplete or input is zero."
        }
        return "Cache hit covers all confirmed requests. It does not measure task efficiency or subscription quota."
    }
}
