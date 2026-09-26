import Foundation
import MonitorCore
import SwiftUI
import WidgetKit

#if DEBUG
private enum WidgetPreviewData {
    static let snapshot = makeSnapshot()

    private static func makeSnapshot() -> WidgetSharedSnapshot {
        do {
            let now = Date.now
            let today = try makeToday(now: now)
            let week = try makeWeek(now: now)
            let cache = try makeCache(now: now)
            return try WidgetSharedSnapshot(
                generatedAt: now,
                timeZoneIdentifier: TimeZone.current.identifier,
                revision: 1,
                usage: [today, week],
                cache: cache
            )
        } catch {
            preconditionFailure("Widget preview fixture is invalid: \(error)")
        }
    }

    private static func makeToday(now: Date) throws -> WidgetUsagePeriodSnapshot {
        try WidgetUsagePeriodSnapshot(
            period: .today,
            startsAt: Calendar.current.startOfDay(for: now),
            endsAt: now,
            totals: UsageTotals(requests: 83, inputTokens: 7_578_340, cachedInputTokens: 7_293_056,
                                outputTokens: 59_871, unknownCacheRequests: 2)
        )
    }

    private static func makeWeek(now: Date) throws -> WidgetUsagePeriodSnapshot {
        try WidgetUsagePeriodSnapshot(
            period: .last7Days,
            startsAt: now.addingTimeInterval(-7 * 86_400),
            endsAt: now,
            totals: UsageTotals(requests: 2_545, inputTokens: 381_107_985, cachedInputTokens: 368_582_272,
                                outputTokens: 1_294_453)
        )
    }

    private static func makeCache(now: Date) throws -> WidgetCachePeriodSnapshot {
        let buckets = try (0..<7).map { index -> WidgetCacheBucket in
            try makeBucket(index: index, now: now)
        }
        return try WidgetCachePeriodSnapshot(
            startsAt: now.addingTimeInterval(-7 * 86_400),
            endsAt: now,
            hitRate: 96.9,
            comparisonDeltaPercentagePoints: 0.7,
            availability: .available,
            sessionCount: 142,
            buckets: buckets
        )
    }

    private static func makeBucket(index: Int, now: Date) throws -> WidgetCacheBucket {
        let start = now.addingTimeInterval(Double(index - 6) * 86_400)
        let lower = [80.0, 86, 88, 83, 90, 84, 87][index]
        let average = [85.0, 90, 91, 85, 93, 88, 89][index]
        let upper = [88.0, 94, 95, 90, 97, 92, 94][index]
        let outliers = try makeOutliers(index: index)
        return try WidgetCacheBucket(
            startsAt: start,
            endsAt: start.addingTimeInterval(86_400),
            lower: lower,
            upper: upper,
            average: average,
            sampleCount: 12 + index,
            outliers: outliers
        )
    }

    private static func makeOutliers(index: Int) throws -> [WidgetCacheOutlier] {
        switch index {
        case 0: [try WidgetCacheOutlier(hitRate: 72, deviation: -2.8, severity: .strong)]
        case 2: [try WidgetCacheOutlier(hitRate: 96, deviation: 1.9, severity: .notable)]
        case 4: [try WidgetCacheOutlier(hitRate: 99, deviation: 2.7, severity: .strong)]
        default: []
        }
    }
}

#Preview("Cache Hit Rate · Small", as: .systemSmall) {
    SessionMonitorCacheHitRateWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Cache Hit Rate · Medium", as: .systemMedium) {
    SessionMonitorCacheHitRateWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Cache Hit Rate · Large", as: .systemLarge) {
    SessionMonitorCacheHitRateWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Usage Summary · Small", as: .systemSmall) {
    SessionMonitorUsageWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Usage Summary · Medium", as: .systemMedium) {
    SessionMonitorUsageWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}

#Preview("Usage Summary · Large", as: .systemLarge) {
    SessionMonitorUsageWidget()
} timeline: {
    SessionMonitorWidgetEntry(date: .now, snapshot: WidgetPreviewData.snapshot)
}
#endif
