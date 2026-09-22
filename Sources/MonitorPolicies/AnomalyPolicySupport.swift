import Foundation
import MonitorCore

enum AnomalyPolicySupport {
    static func requestPoints(_ context: AnomalyPolicyContext) -> [RequestTimelinePoint] {
        context.timeline.points.filter {
            $0.kind == .usageRequest && $0.sessionID == context.session.id
        }.sorted { lhs, rhs in
            lhs.timestamp == rhs.timestamp ? lhs.id < rhs.id : lhs.timestamp < rhs.timestamp
        }
    }

    static func pollingPoints(_ context: AnomalyPolicyContext) -> [RequestTimelinePoint] {
        context.timeline.points.filter { point in
            switch point.activityClass {
            case .wait: return point.kind == .wait || isToolInvocation(point)
            case .waitThreads: return isToolInvocation(point)
            case .processWait, .clockSleep, .goalContinuation, .shell, .unknown: return false
            case nil: return point.kind == .wait
            }
        }.filter { $0.sessionID == context.session.id }.sorted { lhs, rhs in
            lhs.timestamp == rhs.timestamp ? lhs.id < rhs.id : lhs.timestamp < rhs.timestamp
        }
    }

    static func isToolInvocation(_ point: RequestTimelinePoint) -> Bool {
        guard point.kind == .tool else { return false }
        return point.evidence == "function_call" || point.evidence == "custom_tool_call"
    }

    static func pollingPairs(
        _ context: AnomalyPolicyContext, configuration: AnomalyPolicyConfiguration
    ) -> [(wait: RequestTimelinePoint, request: RequestTimelinePoint)] {
        let waits = pollingPoints(context)
        let requests = requestPoints(context)
        var requestIndex = 0
        var pairs: [(wait: RequestTimelinePoint, request: RequestTimelinePoint)] = []
        for wait in waits {
            while requestIndex < requests.count && requests[requestIndex].timestamp < wait.timestamp {
                requestIndex += 1
            }
            guard requestIndex < requests.count,
                  requests[requestIndex].timestamp.timeIntervalSince(wait.timestamp)
                    <= configuration.pollingPairWindow else { continue }
            pairs.append((wait, requests[requestIndex]))
            requestIndex += 1
        }
        guard pairs.count >= configuration.minimumPollingPairs else { return [] }
        var windowStart = 0
        var best: ArraySlice<(wait: RequestTimelinePoint, request: RequestTimelinePoint)> = []
        for end in pairs.indices {
            while windowStart < end,
                  pairs[end].request.timestamp.timeIntervalSince(pairs[windowStart].wait.timestamp)
                    > configuration.pollingSequenceWindow {
                windowStart += 1
            }
            let candidate = pairs[windowStart...end]
            if candidate.count >= configuration.minimumPollingPairs && candidate.count > best.count {
                best = candidate
            }
        }
        return Array(best)
    }

    static func inputTokens(_ point: RequestTimelinePoint) -> Int64? {
        guard let cached = point.cachedInputTokens, let uncached = point.uncachedInputTokens else { return nil }
        let (total, overflow) = cached.addingReportingOverflow(uncached)
        return overflow ? nil : total
    }

    static func cacheRatio(_ point: RequestTimelinePoint) -> Double? {
        guard let input = inputTokens(point), input > 0, let cached = point.cachedInputTokens else { return nil }
        return Double(cached) / Double(input)
    }

    static func comparableCachePairs(
        _ context: AnomalyPolicyContext, configuration: AnomalyPolicyConfiguration
    ) -> [CacheChangePair] {
        let known = requestPoints(context).filter { point in
            inputTokens(point).map { $0 > 0 } == true && point.cachedInputTokens != nil
        }
        return zip(known, known.dropFirst()).compactMap { before, after in
            guard let beforeRatio = cacheRatio(before), let afterRatio = cacheRatio(after) else { return nil }
            let gap = after.timestamp.timeIntervalSince(before.timestamp)
            guard abs(afterRatio - beforeRatio) >= configuration.cacheChangeRatio,
                  gap >= 0, gap <= configuration.cacheComparisonWindow,
                  before.model != nil, after.model != nil, before.model == after.model,
                  (inputTokens(before) ?? 0) >= configuration.minimumCacheInputTokens,
                  (inputTokens(after) ?? 0) >= configuration.minimumCacheInputTokens else { return nil }
            return CacheChangePair(before: before, after: after, change: abs(afterRatio - beforeRatio))
        }
    }

    static func median(_ values: [Int64]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        if sorted.count % 2 == 1 { return Double(sorted[sorted.count / 2]) }
        let upper = sorted.count / 2
        return (Double(sorted[upper - 1]) + Double(sorted[upper])) / 2
    }

    static func percentage(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }
}

struct CacheChangePair {
    let before: RequestTimelinePoint
    let after: RequestTimelinePoint
    let change: Double
}
