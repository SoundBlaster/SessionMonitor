import Foundation
import MonitorCore

enum RequestTimelineChartLayout {
    static let chartHeight: CGFloat = 250
    static let yAxisTopInset: CGFloat = 16
    static let barWidth: CGFloat = 6
    static let eventSymbolSize: CGFloat = 12
    static let axisAllowance: Double = 80
    static let minimumMarkSpacing: Double = 14
    static let maximumBuckets = 120
    static let minimumYAxisUpperBound: Double = 1
    static let yAxisHeadroomFraction: Double = 0.08
    static let accessibilityLabel = "Known cached and uncached token sums over time"
}

struct TimelineBucket: Identifiable {
    let id: Int
    let start: Date
    let end: Date
    var requestCount = 0
    var knownRequestCount = 0
    var cached: Double = 0
    var uncached: Double = 0
    var events: [TimelineEventKind: Int] = [:]
    var timestamp: Date { start.addingTimeInterval(end.timeIntervalSince(start) / 2) }
    var unknownRequestCount: Int { requestCount - knownRequestCount }
    var eventCount: Int { events.values.reduce(0, +) }
}

/// Every visible observation belongs to one pixel-budget bucket. No downsampling.
struct TimelineAggregation {
    let buckets: [TimelineBucket]
    let capacity: Int
    let interval: TimeInterval
    var requestCount: Int { buckets.reduce(0) { $0 + $1.requestCount } }
    var unknownRequestCount: Int { buckets.reduce(0) { $0 + $1.unknownRequestCount } }

    init(points: [RequestTimelinePoint], domain: DateInterval, width: Double) {
        let bucketCapacity = Self.bucketCapacity(for: width)
        capacity = bucketCapacity
        interval = Self.bucketInterval(for: domain, capacity: bucketCapacity)
        var grouped: [Int: TimelineBucket] = [:]
        for point in points where point.timestamp >= domain.start && point.timestamp <= domain.end {
            let slot = min(capacity - 1, Int(point.timestamp.timeIntervalSince(domain.start) / interval))
            let start = domain.start.addingTimeInterval(Double(slot) * interval)
            var bucket = grouped[slot] ?? TimelineBucket(
                id: slot, start: start, end: min(domain.end, start.addingTimeInterval(interval)))
            if point.kind == .usageRequest {
                bucket.requestCount += 1
                if let cached = point.cachedInputTokens, let uncached = point.uncachedInputTokens {
                    bucket.knownRequestCount += 1
                    bucket.cached += Double(cached)
                    bucket.uncached += Double(uncached)
                }
            } else {
                bucket.events[point.kind, default: 0] += 1
            }
            grouped[slot] = bucket
        }
        buckets = grouped.values.sorted { $0.id < $1.id }
    }

    static func bucketCapacity(for width: Double) -> Int {
        let safeWidth = width.isFinite ? width : RequestTimelineChartLayout.axisAllowance
        let availableWidth = max(0, safeWidth - RequestTimelineChartLayout.axisAllowance)
        let proposedCapacity = min(Double(RequestTimelineChartLayout.maximumBuckets),
                                   availableWidth / RequestTimelineChartLayout.minimumMarkSpacing)
        return max(1, Int(proposedCapacity))
    }

    static func bucketInterval(for domain: DateInterval, capacity: Int) -> TimeInterval {
        max(domain.duration, 0.001) / Double(max(1, capacity))
    }

    var description: String {
        let seconds = max(1, Int(interval.rounded()))
        return "Known token sums per ~\(seconds)s interval · \(requestCount) requests · "
            + "\(unknownRequestCount) with unavailable token data. Zoom in for finer intervals."
    }
}
