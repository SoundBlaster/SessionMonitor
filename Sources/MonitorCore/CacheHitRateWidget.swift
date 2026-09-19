import Foundation

/// Privacy-safe input for the cache-hit widget. `sessionID` is used only to derive
/// a per-session rate inside one bucket and is never carried into presentation output.
public struct CacheHitRateObservation: Equatable, Sendable {
    public let timestamp: Date
    public let sessionID: String
    public let cacheableInputTokens: Int64
    public let cachedInputTokens: Int64?

    public init(timestamp: Date, sessionID: String, cacheableInputTokens: Int64,
                cachedInputTokens: Int64?) {
        self.timestamp = timestamp
        self.sessionID = sessionID
        self.cacheableInputTokens = cacheableInputTokens
        self.cachedInputTokens = cachedInputTokens
    }
}

public enum CacheHitRateWidgetPeriod: String, CaseIterable, Codable, Sendable {
    case last24Hours
    case last7Days
    case last14Days
    case last30Days

    public var duration: TimeInterval {
        switch self {
        case .last24Hours: 24 * 60 * 60
        case .last7Days: 7 * 24 * 60 * 60
        case .last14Days: 14 * 24 * 60 * 60
        case .last30Days: 30 * 24 * 60 * 60
        }
    }
}

public enum CacheHitRateWidgetAvailability: Equatable, Sendable {
    case available
    case partialCoverage(unknownObservationCount: Int)
    case notApplicable
    case noData
}

/// An identity-free exceptional session point. Presentation may disclose only these values.
public struct CacheHitRateOutlier: Equatable, Hashable, Sendable {
    public enum Severity: Equatable, Hashable, Sendable { case notable, strong }

    public let cacheHitRate: Double
    public let deviation: Double
    public let severity: Severity

    public init(cacheHitRate: Double, deviation: Double, severity: Severity) {
        self.cacheHitRate = cacheHitRate
        self.deviation = deviation
        self.severity = severity
    }
}

public struct CacheHitRateBucket: Equatable, Sendable, Identifiable {
    public let start: Date
    public let end: Date
    public let lower: Double
    public let upper: Double
    public let average: Double
    public let median: Double?
    public let outliers: [CacheHitRateOutlier]
    public let sampleCount: Int
    public let usesMinMaxFallback: Bool

    public var id: Date { start }

    public init(start: Date, end: Date, lower: Double, upper: Double, average: Double,
                median: Double?, outliers: [CacheHitRateOutlier], sampleCount: Int,
                usesMinMaxFallback: Bool) {
        self.start = start
        self.end = end
        self.lower = lower
        self.upper = upper
        self.average = average
        self.median = median
        self.outliers = outliers
        self.sampleCount = sampleCount
        self.usesMinMaxFallback = usesMinMaxFallback
    }
}

public struct CacheHitRateWidgetReport: Equatable, Sendable {
    public let period: CacheHitRateWidgetPeriod
    public let periodStart: Date
    public let periodEnd: Date
    public let periodCacheHitRate: Double?
    public let comparisonDeltaPercentagePoints: Double?
    public let availability: CacheHitRateWidgetAvailability
    public let sessionCount: Int
    public let buckets: [CacheHitRateBucket]

    public init(period: CacheHitRateWidgetPeriod, periodStart: Date, periodEnd: Date,
                periodCacheHitRate: Double?, comparisonDeltaPercentagePoints: Double?,
                availability: CacheHitRateWidgetAvailability, sessionCount: Int,
                buckets: [CacheHitRateBucket]) {
        self.period = period
        self.periodStart = periodStart
        self.periodEnd = periodEnd
        self.periodCacheHitRate = periodCacheHitRate
        self.comparisonDeltaPercentagePoints = comparisonDeltaPercentagePoints
        self.availability = availability
        self.sessionCount = sessionCount
        self.buckets = buckets
    }
}

/// Builds display data without exposing session or model identity. Input observations must include
/// the requested period and its immediately preceding equal period for comparison.
public enum CacheHitRateWidgetBuilder {
    public static func build(
        observations: [CacheHitRateObservation], period: CacheHitRateWidgetPeriod,
        referenceDate: Date, timeZone: TimeZone
    ) -> CacheHitRateWidgetReport {
        let periodEnd = referenceDate
        let periodStart = referenceDate.addingTimeInterval(-period.duration)
        let previousStart = periodStart.addingTimeInterval(-period.duration)
        let current = observations.filter { $0.timestamp >= periodStart && $0.timestamp < periodEnd }
        let previous = observations.filter { $0.timestamp >= previousStart && $0.timestamp < periodStart }
        let currentRate = weightedRate(current)
        let previousRate = weightedRate(previous)
        let availability = availability(for: current)
        let buckets = buckets(for: current, period: period, periodStart: periodStart,
                              periodEnd: periodEnd, timeZone: timeZone)
        let sessionCount = Set(current.map(\.sessionID)).count
        return CacheHitRateWidgetReport(
            period: period,
            periodStart: periodStart,
            periodEnd: periodEnd,
            periodCacheHitRate: availability == .available ? currentRate : nil,
            comparisonDeltaPercentagePoints: currentRate.flatMap { currentRate in
                previousRate.map { currentRate - $0 }
            },
            availability: availability,
            sessionCount: sessionCount,
            buckets: buckets
        )
    }

    private static func availability(for observations: [CacheHitRateObservation]) -> CacheHitRateWidgetAvailability {
        guard !observations.isEmpty else { return .noData }
        let applicable = observations.filter { $0.cacheableInputTokens > 0 }
        guard !applicable.isEmpty else { return .notApplicable }
        let unknown = applicable.filter { $0.cachedInputTokens == nil }.count
        return unknown == 0 ? .available : .partialCoverage(unknownObservationCount: unknown)
    }

    private static func weightedRate(_ observations: [CacheHitRateObservation]) -> Double? {
        let applicable = observations.filter { $0.cacheableInputTokens > 0 }
        guard !applicable.isEmpty, applicable.allSatisfy({ $0.cachedInputTokens != nil }) else { return nil }
        let input = applicable.reduce(Int64.zero) { $0 + $1.cacheableInputTokens }
        guard input > 0 else { return nil }
        let cached = applicable.reduce(Int64.zero) { $0 + ($1.cachedInputTokens ?? 0) }
        return clamp(Double(cached) / Double(input) * 100)
    }

    private static func buckets(
        for observations: [CacheHitRateObservation], period: CacheHitRateWidgetPeriod,
        periodStart: Date, periodEnd: Date, timeZone: TimeZone
    ) -> [CacheHitRateBucket] {
        let calendar = calendar(for: timeZone)
        let intervals = bucketIntervals(period: period, periodStart: periodStart, periodEnd: periodEnd,
                                        calendar: calendar)
        return intervals.compactMap { interval in
            let values = sessionRates(in: observations.filter {
                $0.timestamp >= interval.start && $0.timestamp < interval.end
            })
            guard !values.isEmpty else { return nil }
            return makeBucket(start: interval.start, end: interval.end, values: values)
        }
    }

    private static func sessionRates(in observations: [CacheHitRateObservation]) -> [(rate: Double, weight: Int64)] {
        let grouped = Dictionary(grouping: observations, by: \.sessionID)
        return grouped.values.compactMap { values in
            guard let rate = weightedRate(values) else { return nil }
            let weight = values.reduce(Int64.zero) { $0 + max(0, $1.cacheableInputTokens) }
            return weight > 0 ? (rate, weight) : nil
        }
    }

    private static func makeBucket(
        start: Date, end: Date, values: [(rate: Double, weight: Int64)]
    ) -> CacheHitRateBucket {
        let sorted = values.map(\.rate).sorted()
        let fallback = sorted.count < 4
        let lower = fallback ? sorted[0] : percentile(sorted, 10)
        let upper = fallback ? sorted[sorted.count - 1] : percentile(sorted, 90)
        let weightedTotal = values.reduce(Int64.zero) { $0 + $1.weight }
        let average = clamp(values.reduce(0.0) { $0 + $1.rate * Double($1.weight) } / Double(weightedTotal))
        let median = percentile(sorted, 50)
        let outliers = fallback ? [] : outliers(in: sorted, median: median)
        return CacheHitRateBucket(start: start, end: end, lower: lower, upper: upper, average: average,
                                  median: median, outliers: outliers, sampleCount: sorted.count,
                                  usesMinMaxFallback: fallback)
    }

    private static func outliers(in values: [Double], median: Double) -> [CacheHitRateOutlier] {
        let mad = percentile(values.map { abs($0 - median) }.sorted(), 50)
        guard mad > 0 else { return [] }
        return values.compactMap { value in
            let robustZScore = 0.6745 * (value - median) / mad
            let absolute = abs(robustZScore)
            let severity: CacheHitRateOutlier.Severity?
            if absolute >= 2.5 {
                severity = .strong
            } else if absolute >= 2.0 {
                severity = .notable
            } else {
                severity = nil
            }
            return severity.map {
                CacheHitRateOutlier(cacheHitRate: value, deviation: robustZScore, severity: $0)
            }
        }
        .sorted { abs($0.deviation) > abs($1.deviation) }
    }

    private static func bucketIntervals(
        period: CacheHitRateWidgetPeriod, periodStart: Date, periodEnd: Date, calendar: Calendar
    ) -> [(start: Date, end: Date)] {
        if period == .last24Hours {
            var result: [(Date, Date)] = []
            var cursor = calendar.dateInterval(of: .hour, for: periodStart)?.start ?? periodStart
            while cursor < periodEnd {
                let next = calendar.date(byAdding: .hour, value: 1, to: cursor) ?? periodEnd
                result.append((max(cursor, periodStart), min(next, periodEnd)))
                cursor = next
            }
            return result
        }
        var result: [(Date, Date)] = []
        var cursor = calendar.startOfDay(for: periodStart)
        while cursor < periodEnd {
            let next = calendar.date(byAdding: .day, value: 1, to: cursor) ?? periodEnd
            result.append((max(cursor, periodStart), min(next, periodEnd)))
            cursor = next
        }
        return result
    }

    private static func calendar(for timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    private static func percentile(_ sorted: [Double], _ percent: Double) -> Double {
        precondition(!sorted.isEmpty)
        guard sorted.count > 1 else { return sorted[0] }
        let position = (Double(sorted.count) - 1) * percent / 100
        let lower = Int(position.rounded(.down))
        let upper = Int(position.rounded(.up))
        let fraction = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * fraction
    }

    private static func clamp(_ value: Double) -> Double { min(100, max(0, value)) }
}
