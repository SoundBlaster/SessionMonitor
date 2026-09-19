import Foundation
import MonitorCore

/// Calendar slots include missing buckets. A rolling period can have partial first/last days.
struct CacheHitRateWidgetSlot: Identifiable {
    let id: Int
    let start: Date
    let bucket: CacheHitRateBucket?
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
            slots.append(.init(id: slots.count, start: cursor, bucket: bucket))
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
