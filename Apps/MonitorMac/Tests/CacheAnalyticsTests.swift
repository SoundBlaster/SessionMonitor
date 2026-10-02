import AppKit
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

final class CacheAnalyticsTests: XCTestCase {
    func testViewportShowsFullPeriodAndClampsPanningAtBothEdges() {
        XCTAssertEqual(CacheAnalyticsViewport().domain(slotCount: 7), -0.5...6.5)
        XCTAssertEqual(CacheAnalyticsViewport(zoom: 3, position: -1).domain(slotCount: 30), -0.5...9.5)
        XCTAssertEqual(CacheAnalyticsViewport(zoom: 3, position: 2).domain(slotCount: 30), 19.5...29.5)
        XCTAssertEqual(CacheAnalyticsViewport(zoom: 100, position: 1).domain(slotCount: 30), 28.5...29.5)
        XCTAssertEqual(CacheAnalyticsViewport().domain(slotCount: 0), -0.5...0.5)
    }

    func testSelectedGapDoesNotBecomeAnAdjacentBucket() throws {
        let slots = CacheHitRateWidgetChartPresentation.slots(for: CacheHitRateWidgetFixture.gaps.report)
        let viewport = CacheAnalyticsViewport(zoom: 2, position: 1)
        let gap = try XCTUnwrap(viewport.selectedSlot(1, slots: slots))
        XCTAssertNil(gap.bucket)
        XCTAssertEqual(viewport.selectedSlot(5, slots: slots)?.bucket?.start, slots[5].start)
        XCTAssertNil(viewport.selectedSlot(-2, slots: slots))
        XCTAssertNil(viewport.selectedSlot(.infinity, slots: slots))
        XCTAssertNil(viewport.selectedSlot(7, slots: slots))
    }

    @MainActor
    func testOnlyTheOpeningExplorerCanUpdateTheWindow() {
        let presentation = CacheAnalyticsPresentation()
        let first = UUID()
        let second = UUID()
        presentation.open(sourceID: first, report: CacheHitRateWidgetFixture.reference.report,
                          periodTitle: "Today", accountLabel: "First account")
        presentation.update(sourceID: second, report: CacheHitRateWidgetFixture.month.report,
                            periodTitle: "Last 30 days", accountLabel: "Second account")
        XCTAssertEqual(presentation.report, CacheHitRateWidgetFixture.reference.report)
        XCTAssertEqual(presentation.accountLabel, "First account")
        presentation.open(sourceID: second, report: CacheHitRateWidgetFixture.month.report,
                          periodTitle: "Last 30 days", accountLabel: "Second account")
        presentation.update(sourceID: first, report: nil, periodTitle: nil, accountLabel: "First account")
        XCTAssertEqual(presentation.sourceID, second)
        XCTAssertEqual(presentation.report, CacheHitRateWidgetFixture.month.report)
    }

    @MainActor
    func testScopeChangeClearsOldDataBeforeReplacement() {
        let presentation = CacheAnalyticsPresentation()
        let source = UUID()
        presentation.open(sourceID: source, report: CacheHitRateWidgetFixture.reference.report,
                          periodTitle: "Last 7 days", accountLabel: "First")
        presentation.update(sourceID: source, report: nil, periodTitle: "Today", accountLabel: "Second")
        XCTAssertNil(presentation.report)
        XCTAssertEqual(presentation.periodTitle, "Today")
        XCTAssertEqual(presentation.accountLabel, "Second")
        presentation.update(sourceID: source, report: CacheHitRateWidgetFixture.hourly.report,
                            periodTitle: "Today", accountLabel: "Second")
        XCTAssertEqual(presentation.report, CacheHitRateWidgetFixture.hourly.report)
    }

    @MainActor
    func testInteractiveChartRendersZoomedLightAndDarkWithTheSameYAxis() throws {
        let report = CacheHitRateWidgetFixture.month.report
        let axis = CacheHitRateWidgetAxis.domain(for: report.buckets)
        for scheme in [ColorScheme.light, .dark] {
            for position in [0.0, 1.0] {
                let view = CacheHitRateWidgetChart(
                    report: report, family: .large, appearance: .default, preservesAspectRatio: false,
                    viewport: CacheAnalyticsViewport(zoom: 3, position: position).domain(slotCount: 30),
                    selection: .constant(20)
                )
                .frame(width: 800, height: 360)
                .environment(\.colorScheme, scheme)
                let renderer = ImageRenderer(content: view)
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, 800, accuracy: 1)
                XCTAssertEqual(image.size.height, 360, accuracy: 1)
                XCTAssertEqual(CacheHitRateWidgetAxis.domain(for: report.buckets), axis)
                let attachment = XCTAttachment(image: image)
                attachment.name = "analytics-\(scheme)-position-\(position)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}
