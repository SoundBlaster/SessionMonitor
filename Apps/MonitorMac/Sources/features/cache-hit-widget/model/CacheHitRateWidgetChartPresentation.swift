import Foundation
import MonitorCore

/// Calendar slots include missing buckets. A rolling period can have partial first/last days.
struct CacheHitRateWidgetSlot: Identifiable {
    let id: Int
    let start: Date
    let bucket: CacheHitRateBucket?
    /// Whether the interval has any request. A slot can have usage but no bucket (single-request sessions
    /// only), and is still selectable.
    let hasUsage: Bool

    init(id: Int, start: Date, bucket: CacheHitRateBucket?, hasUsage: Bool? = nil) {
        self.id = id
        self.start = start
        self.bucket = bucket
        self.hasUsage = hasUsage ?? (bucket != nil)
    }
}

enum CacheHitRateWidgetChartPresentation {
    static func averageMarker(for bucket: CacheHitRateBucket) -> Double { bucket.average }

    static func slots(for report: CacheHitRateWidgetReport) -> [CacheHitRateWidgetSlot] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: report.timeZoneIdentifier) ?? .gmt
        let component: Calendar.Component = report.period == .last24Hours ? .hour : .day
        var cursor = report.periodStart
        var slots: [CacheHitRateWidgetSlot] = []
        while cursor < report.periodEnd, slots.count < 32 {
            guard let interval = calendar.dateInterval(of: component, for: cursor) else { break }
            let end = min(interval.end, report.periodEnd)
            guard end > cursor else { break }
            let bucket = report.buckets.first { $0.start >= cursor && $0.start < end }
            let occupied = report.occupiedBucketStarts.contains { $0 >= cursor && $0 < end }
            slots.append(.init(id: slots.count, start: cursor, bucket: bucket, hasUsage: bucket != nil || occupied))
            cursor = end
        }
        return slots
    }
}

enum CacheHitRateWidgetAxis {
    static func domain(for buckets: [CacheHitRateBucket]) -> ClosedRange<Double> {
        let normalMinimum = buckets.map(\.lower).min() ?? 75
        let minimum = [75.0, 50, 25, 0].first(where: { $0 <= normalMinimum }) ?? 0
        return minimum...100
    }

    static func ticks(for domain: ClosedRange<Double>) -> [Double] {
        let step = domain.lowerBound == 75 ? 5.0 : domain.lowerBound == 50 ? 10.0 : 25.0
        return Array(stride(from: domain.lowerBound, through: domain.upperBound, by: step))
    }
}
