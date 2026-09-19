import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

final class CacheHitRateWidgetTests: XCTestCase {
    func testDefaultCopyProvidesStableTitleAndLegendText() {
        let copy = CacheHitRateWidgetAppearance.Copy.default

        XCTAssertEqual(copy.title, "Cache Hit Rate")
        XCTAssertEqual(copy.rangeLegend, "Range (P10 – P90)")
        XCTAssertEqual(copy.averageLegend, "Average")
        XCTAssertEqual(copy.outlierLegend, "Outlier")
        XCTAssertEqual(copy.comparisonLabel, "vs previous period")
    }

    func testQuarterBandAxisUsesNormalRangeAndIgnoresOutliers() {
        let bucket = CacheHitRateBucket(
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400),
            lower: 82, upper: 93, average: 88, median: 88,
            outliers: [CacheHitRateOutlier(cacheHitRate: 10, deviation: -4, severity: .strong)],
            sampleCount: 12, usesMinMaxFallback: false
        )

        XCTAssertEqual(CacheHitRateWidgetAxis.domain(for: [bucket]), 75...100)
    }

    func testQuarterBandAxisDropsToNextBandForNormalLowRange() {
        let bucket = CacheHitRateBucket(
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400),
            lower: 68, upper: 88, average: 78, median: 78,
            outliers: [], sampleCount: 12, usesMinMaxFallback: false
        )

        XCTAssertEqual(CacheHitRateWidgetAxis.domain(for: [bucket]), 50...100)
    }

    func testQuarterBandAxisIncludesWeightedAverage() {
        let bucket = CacheHitRateBucket(
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400),
            lower: 82, upper: 93, average: 49, median: 88,
            outliers: [CacheHitRateOutlier(cacheHitRate: 10, deviation: -4, severity: .strong)],
            sampleCount: 12, usesMinMaxFallback: false
        )

        XCTAssertEqual(CacheHitRateWidgetAxis.domain(for: [bucket]), 25...100)
    }

    func testHourlyBucketLabelUsesReportTimeZone() {
        let date = Date(timeIntervalSince1970: 0)
        let label = CacheHitRateWidgetLabelFormat.bucketLabel(
            for: date,
            period: .last24Hours,
            family: .medium,
            timeZoneIdentifier: "America/Los_Angeles",
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(label.replacingOccurrences(of: "\u{202F}", with: " "), "4 PM")
    }

    func testDailyLabelsAreThreeLetterWeekdaysForMediumFamily() {
        let label = CacheHitRateWidgetLabelFormat.bucketLabel(
            for: Date(timeIntervalSince1970: 0),
            period: .last7Days,
            family: .medium,
            timeZoneIdentifier: "UTC",
            locale: Locale(identifier: "en_US_POSIX")
        )

        XCTAssertEqual(label, "Thu")
    }

    func testAverageMarkerStaysWithinDisplayedRange() {
        let bucket = CacheHitRateBucket(
            start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 86_400),
            lower: 82, upper: 93, average: 97, median: 88,
            outliers: [], sampleCount: 12, usesMinMaxFallback: false
        )

        XCTAssertEqual(CacheHitRateWidgetChartPresentation.averageMarker(for: bucket), 93)
    }

    func testRefreshScheduleUsesNextHourBoundary() throws {
        let date = Date(timeIntervalSince1970: 1_725_925_930)
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        XCTAssertEqual(
            CacheHitRateWidgetRefreshSchedule.nextRefresh(after: date, timeZone: timeZone),
            Date(timeIntervalSince1970: 1_725_926_400)
        )
    }

    @MainActor
    func testWidgetPeriodPersistsAndInvalidStoredValueFallsBackToSevenDays() throws {
        let suiteName = "CacheHitRateWidgetTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = CacheHitRateWidgetSettings(defaults: defaults)
        XCTAssertEqual(settings.period, .last7Days)
        settings.selectPeriod(.last14Days)
        XCTAssertEqual(CacheHitRateWidgetSettings(defaults: defaults).period, .last14Days)

        defaults.set("not-a-period", forKey: CacheHitRateWidgetSettings.periodStorageKey)
        XCTAssertEqual(CacheHitRateWidgetSettings(defaults: defaults).period, .last7Days)
    }
}
