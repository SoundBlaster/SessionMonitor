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
