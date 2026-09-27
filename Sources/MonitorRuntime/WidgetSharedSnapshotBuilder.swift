import Foundation
import MonitorCore

private struct WidgetUsageQueries {
    let today: UsageQuery
    let week: UsageQuery
    let todayStart: Date
    let weekStart: Date
}

extension SessionMonitor {
    /// Builds the small aggregate-only payload shared with the WidgetKit extension.
    /// A watermark fence prevents publishing a mixture of two import revisions.
    public func widgetSharedSnapshot(
        generatedAt: Date = Date(), timeZone: TimeZone = .current
    ) throws -> WidgetSharedSnapshot {
        var latestRevision: Int64 = 0
        for _ in 0..<2 {
            let queries = try widgetUsageQueries(generatedAt: generatedAt, timeZone: timeZone)
            let today = try snapshot(query: queries.today)
            let week = try snapshot(query: queries.week)
            let cache = try cacheHitRateWidget(period: .last7Days, referenceDate: generatedAt, timeZone: timeZone)
            let fence = try snapshot(query: queries.week)
            latestRevision = fence.watermark.revision
            guard today.watermark.databaseID == week.watermark.databaseID,
                  week.watermark.databaseID == fence.watermark.databaseID,
                  today.watermark.revision == week.watermark.revision,
                  week.watermark.revision == fence.watermark.revision else { continue }

            let usage = try widgetUsagePeriods(today: today, week: week, queries: queries, generatedAt: generatedAt)
            let cacheSnapshot = try widgetCacheSnapshot(from: cache)
            return try WidgetSharedSnapshot(generatedAt: generatedAt, timeZoneIdentifier: timeZone.identifier,
                                            revision: fence.watermark.revision, usage: usage, cache: cacheSnapshot)
        }
        throw WidgetSharedSnapshotBuildError.concurrentImport(revision: latestRevision)
    }

    private func widgetUsageQueries(generatedAt: Date, timeZone: TimeZone) throws -> WidgetUsageQueries {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let todayStart = calendar.startOfDay(for: generatedAt)
        let weekStart = generatedAt.addingTimeInterval(-CacheHitRateWidgetPeriod.last7Days.duration)
        return WidgetUsageQueries(
            today: try UsageQuery(since: todayStart, until: generatedAt, timeZoneIdentifier: timeZone.identifier),
            week: try UsageQuery(since: weekStart, until: generatedAt, timeZoneIdentifier: timeZone.identifier),
            todayStart: todayStart,
            weekStart: weekStart
        )
    }

    private func widgetUsagePeriods(
        today: UsageSnapshot, week: UsageSnapshot, queries: WidgetUsageQueries, generatedAt: Date
    ) throws -> [WidgetUsagePeriodSnapshot] {
        try [
            WidgetUsagePeriodSnapshot(period: .today, startsAt: queries.todayStart, endsAt: generatedAt,
                                      totals: today.report.totals),
            WidgetUsagePeriodSnapshot(period: .last7Days, startsAt: queries.weekStart, endsAt: generatedAt,
                                      totals: week.report.totals)
        ]
    }

    private func widgetCacheSnapshot(from cache: CacheHitRateWidgetReport) throws -> WidgetCachePeriodSnapshot {
        let availability: WidgetCachePeriodSnapshot.Availability = switch cache.availability {
        case .available: .available
        case .partialCoverage: .partial
        case .notApplicable: .notApplicable
        case .noData: .noData
        }
        let buckets = try cache.buckets.map { bucket in
            let outliers = try bucket.outliers.map { point in
                let severity: WidgetCacheOutlier.Severity = switch point.severity {
                case .notable: .notable
                case .strong: .strong
                }
                return try WidgetCacheOutlier(hitRate: point.cacheHitRate, deviation: point.deviation,
                                              severity: severity)
            }
            return try WidgetCacheBucket(startsAt: bucket.start, endsAt: bucket.end, lower: bucket.lower,
                                         upper: bucket.upper, average: bucket.average,
                                         sampleCount: bucket.sampleCount, outliers: outliers)
        }
        let unknownCount: Int
        if case let .partialCoverage(count) = cache.availability { unknownCount = count } else { unknownCount = 0 }
        return try WidgetCachePeriodSnapshot(
            startsAt: cache.periodStart, endsAt: cache.periodEnd, hitRate: cache.periodCacheHitRate,
            comparisonDeltaPercentagePoints: cache.comparisonDeltaPercentagePoints,
            availability: availability, sessionCount: cache.sessionCount,
            unknownObservationCount: unknownCount, buckets: buckets
        )
    }
}
