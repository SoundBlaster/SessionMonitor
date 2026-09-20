import AppKit
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

final class CacheHitRateWidgetFixtureTests: XCTestCase {
    func testReferenceHasSevenDistinctWeekdaysAndStableClock() {
        let slots = CacheHitRateWidgetChartPresentation.slots(for: CacheHitRateWidgetFixture.reference.report)
        XCTAssertEqual(slots.count, 7)
        let labels = slots.map {
            CacheHitRateWidgetLabelFormat.bucketLabel(for: $0.start, period: .last7Days,
                family: .medium, timeZoneIdentifier: "UTC", locale: Locale(identifier: "en_US_POSIX"))
        }
        XCTAssertEqual(labels, ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"])
    }

    func testMissingDaysKeepTheirSlotsWithoutInventingValues() {
        let slots = CacheHitRateWidgetChartPresentation.slots(for: CacheHitRateWidgetFixture.gaps.report)
        XCTAssertEqual(slots.count, 7)
        XCTAssertEqual(slots.filter { $0.bucket != nil }.map(\.id), [0, 2, 5])
    }

    func testWeightedScenarioExercisesMeanOutsidePercentiles() throws {
        let bucket = try XCTUnwrap(CacheHitRateWidgetFixture.weighted.report.buckets.first)
        XCTAssertGreaterThan(bucket.average, bucket.upper)
        XCTAssertEqual(CacheHitRateWidgetChartPresentation.averageMarker(for: bucket), bucket.average)
    }

    func testAxisTicksCoverLowerBandsAndIgnoreExceptionalLowPoint() {
        XCTAssertEqual(CacheHitRateWidgetAxis.ticks(for: 50...100), [50, 60, 70, 80, 90, 100])
        let report = CacheHitRateWidgetFixture.outliers.report
        XCTAssertEqual(CacheHitRateWidgetAxis.domain(for: report.buckets), 75...100)
        XCTAssertTrue(report.buckets.flatMap(\.outliers).contains { $0.cacheHitRate < 75 })
    }

    func testUnavailableAndDenseFixturesUseProductionBuilder() {
        XCTAssertEqual(CacheHitRateWidgetFixture.empty.report.availability, .noData)
        XCTAssertEqual(CacheHitRateWidgetFixture.zero.report.availability, .notApplicable)
        XCTAssertEqual(CacheHitRateWidgetFixture.partial.report.availability,
                       .partialCoverage(unknownObservationCount: 1))
        XCTAssertEqual(CacheHitRateWidgetFixture.hourly.report.buckets.count, 24)
        XCTAssertEqual(CacheHitRateWidgetFixture.month.report.buckets.count, 30)
    }

    /// Attach real SwiftUI renders for bounded, repeatable visual review in xcresult.
    @MainActor
    func testRenderFixtureMatrix() throws {
        for fixture in CacheHitRateWidgetFixture.allCases {
            try render(fixture, family: .large, width: 560, scheme: .dark, name: fixture.rawValue)
        }
        try render(.reference, family: .medium, width: 320, scheme: .dark, name: "medium-dark")
        try render(.reference, family: .small, width: 220, scheme: .dark, name: "small-dark")
        try render(.reference, family: .large, width: 560, scheme: .light, name: "large-light")
        try render(.month, family: .small, width: 220, scheme: .light, name: "dense-small-light")
        try render(.reference, family: .large, width: 220, scheme: .light, name: "narrow-large")
        try render(.reference, family: .large, width: 560, scheme: .dark, name: "large-monochrome-dark",
                   palette: .monochrome)
        try render(.reference, family: .medium, width: 320, scheme: .light, name: "medium-monochrome-light",
                   palette: .monochrome)
    }

    @MainActor
    private func render(_ fixture: CacheHitRateWidgetFixture, family: CacheHitRateWidgetAppearance.Family,
                        width: CGFloat, scheme: ColorScheme, name: String,
                        palette: UsageChartPalette = .system) throws {
        let appearance = CacheHitRateWidgetAppearance(
            palette: CacheHitRateWidgetAppearance.Palette(chart: palette), copy: .default
        )
        let view = CacheHitRateWidget(report: fixture.report, family: family, appearance: appearance)
            .frame(width: width).environment(\.colorScheme, scheme).environment(\.locale, Locale(identifier: "en_US"))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, width, accuracy: 1)
        XCTAssertGreaterThan(image.size.height, 100)
        XCTAssertLessThan(image.size.height, width * 1.6)
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
