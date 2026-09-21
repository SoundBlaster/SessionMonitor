import Foundation
import MonitorCore

/// Holds the request timeline's vertical scale steady while the visible time window moves.
struct TimelineYAxisScale: Equatable {
    let domain: ClosedRange<Double>
    let maximumBucketTotal: Double

    struct CacheKey: Hashable {
        let navigationStart: Date
        let navigationEnd: Date
        let bucketCapacity: Int

        init(navigationDomain: DateInterval, width: Double) {
            navigationStart = navigationDomain.start
            navigationEnd = navigationDomain.end
            bucketCapacity = TimelineAggregation.bucketCapacity(for: width)
        }
    }

    init(points: [RequestTimelinePoint], navigationDomain: DateInterval, width: Double) {
        self.init(index: TimelinePointIndex(points: points), navigationDomain: navigationDomain, width: width)
    }

    init(index: TimelinePointIndex, navigationDomain: DateInterval, width: Double) {
        let capacity = Self.CacheKey(navigationDomain: navigationDomain, width: width).bucketCapacity
        let duration = navigationDomain.duration.isFinite
            ? max(navigationDomain.duration, 0.001)
            : Double.greatestFiniteMagnitude
        let referenceWindow = duration / Double(capacity)
        let maximum = Self.maximumKnownInputTotal(
            in: index.points,
            navigationDomain: navigationDomain,
            window: referenceWindow
        )
        let upperBound = max(
            RequestTimelineChartLayout.minimumYAxisUpperBound,
            maximum * (1 + RequestTimelineChartLayout.yAxisHeadroomFraction)
        )
        domain = 0...upperBound
        maximumBucketTotal = maximum
    }

    private static func maximumKnownInputTotal(
        in points: [RequestTimelinePoint],
        navigationDomain: DateInterval,
        window: TimeInterval
    ) -> Double {
        let requests = points.compactMap { point -> (timestamp: Date, total: Double)? in
            guard point.kind == .usageRequest,
                  point.timestamp >= navigationDomain.start,
                  point.timestamp <= navigationDomain.end,
                  let cached = point.cachedInputTokens,
                  let uncached = point.uncachedInputTokens else {
                return nil
            }
            let total = Double(cached) + Double(uncached)
            guard total.isFinite else { return nil }
            return (point.timestamp, total)
        }

        var firstInWindow = 0
        var runningTotal = 0.0
        var maximumTotal = 0.0
        for lastInWindow in requests.indices {
            runningTotal += requests[lastInWindow].total
            while requests[lastInWindow].timestamp.timeIntervalSince(requests[firstInWindow].timestamp) > window {
                runningTotal -= requests[firstInWindow].total
                firstInWindow += 1
            }
            maximumTotal = max(maximumTotal, runningTotal)
        }
        return maximumTotal
    }
}
