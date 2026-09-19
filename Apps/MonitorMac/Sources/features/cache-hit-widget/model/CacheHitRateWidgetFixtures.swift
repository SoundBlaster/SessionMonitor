#if DEBUG
import Foundation
import MonitorCore

/// Synthetic, clock-independent data. Never written to the database or selected by production UI.
enum CacheHitRateWidgetFixture: String, CaseIterable, Identifiable {
    case reference = "Reference · seven days"
    case gaps = "Missing days"
    case outliers = "Outliers below axis"
    case weighted = "Weighted average outside P10–P90"
    case single = "One session"
    case empty = "No data"
    case partial = "Partial coverage"
    case zero = "Zero cacheable input"
    case hourly = "24 hourly buckets"
    case month = "30 daily buckets"

    var id: String { rawValue }
    static let referenceDate = Date(timeIntervalSince1970: 1_789_344_000) // 2026-09-14 00:00 UTC

    var report: CacheHitRateWidgetReport {
        if self == .reference { return Self.referenceReport }
        let period: CacheHitRateWidgetPeriod = self == .hourly
            ? .last24Hours : self == .month ? .last30Days : .last7Days
        return CacheHitRateWidgetBuilder.build(
            observations: observations(period: period), period: period,
            referenceDate: Self.referenceDate, timeZone: .gmt)
    }

    private func observations(period: CacheHitRateWidgetPeriod) -> [CacheHitRateObservation] {
        if self == .empty { return [] }
        if self == .single { return [observation(day: 3, rate: 88)] }
        if self == .zero { return [observation(day: 3, rate: 0, weight: 0)] }
        if self == .partial {
            return [.init(timestamp: Self.referenceDate.addingTimeInterval(-3_600), sessionID: "synthetic",
                          cacheableInputTokens: 100, cachedInputTokens: nil)]
        }
        let count = self == .hourly ? 24 : self == .month ? 30 : 7
        let step: TimeInterval = self == .hourly ? 3_600 : 86_400
        return (0..<count).flatMap { index -> [CacheHitRateObservation] in
            if self == .gaps, [1, 3, 4, 6].contains(index) { return [] }
            let rates = self == .weighted ? [80, 82, 83, 84, 85, 85, 86, 87, 88, 100]
                : self == .outliers ? [5, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 99]
                : [81, 84, 87, 89, 92, 94]
            return rates.enumerated().map { offset, rate in
                let weight: Int64 = self == .weighted && offset == rates.count - 1 ? 100_000 : 100
                return .init(timestamp: Self.referenceDate.addingTimeInterval(-period.duration
                    + Double(index) * step + step / 2), sessionID: "synthetic-\(index)-\(offset)",
                    cacheableInputTokens: weight, cachedInputTokens: Int64(rate) * weight / 100)
            }
        }
    }

    private func observation(day: Int, rate: Int64, weight: Int64 = 100) -> CacheHitRateObservation {
        .init(timestamp: Self.referenceDate.addingTimeInterval(-Double(day) * 86_400 + 3_600),
              sessionID: "synthetic", cacheableInputTokens: weight, cachedInputTokens: rate * weight / 100)
    }

    /// Presentation fixture transcribed from the concept, not an accounting test.
    private static var referenceReport: CacheHitRateWidgetReport {
        let lower = [81.0, 86, 87, 82, 89, 83.5, 85.5]
        let upper = [87.5, 94, 93.5, 89, 97, 90.5, 91.5]
        let average = [84.5, 90, 90.2, 85, 92.5, 86.8, 88.5]
        let exceptional = [78.0, 95.5, 94.5, 80.5, 98.5, 82, 93]
        let start = referenceDate.addingTimeInterval(-CacheHitRateWidgetPeriod.last7Days.duration)
        let buckets = (0..<7).map { index in
            CacheHitRateBucket(
                start: start.addingTimeInterval(Double(index) * 86_400),
                end: start.addingTimeInterval(Double(index + 1) * 86_400),
                lower: lower[index], upper: upper[index], average: average[index], median: average[index],
                outliers: [.init(cacheHitRate: exceptional[index], deviation: index.isMultiple(of: 3) ? -3 : 2.1,
                                 severity: [0, 3, 4].contains(index) ? .strong : .notable)],
                sampleCount: 20, usesMinMaxFallback: false)
        }
        return .init(period: .last7Days, periodStart: start, periodEnd: referenceDate,
                     periodCacheHitRate: 86.4, comparisonDeltaPercentagePoints: 1.8,
                     availability: .available, sessionCount: 142, buckets: buckets)
    }
}
#endif
