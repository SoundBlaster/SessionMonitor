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

    func testPanUsesVisibleSpanAndClampsWithoutChangingZoom() {
        var viewport = CacheAnalyticsViewport(zoom: 3, position: 0.5)
        XCTAssertTrue(viewport.pan(translation: 100, plotWidth: 500, slotCount: 30))
        XCTAssertEqual(viewport.domain(slotCount: 30), 7.5...17.5)
        XCTAssertEqual(viewport.zoom, 3)
        XCTAssertTrue(viewport.pan(translation: 10_000, plotWidth: 500, slotCount: 30))
        XCTAssertEqual(viewport.domain(slotCount: 30), -0.5...9.5)
        XCTAssertFalse(viewport.pan(translation: 10, plotWidth: 500, slotCount: 30))
        XCTAssertTrue(viewport.pan(translation: -10_000, plotWidth: 500, slotCount: 30))
        XCTAssertEqual(viewport.domain(slotCount: 30), 19.5...29.5)
        XCTAssertFalse(viewport.pan(translation: -10, plotWidth: 500, slotCount: 30))
        var fullPeriod = CacheAnalyticsViewport()
        XCTAssertFalse(fullPeriod.pan(translation: 100, plotWidth: 500, slotCount: 30))
    }

    func testMagnifyKeepsThePointerAnchorAndBoundsTheSpan() {
        var viewport = CacheAnalyticsViewport(zoom: 2, position: 0.5)
        let before = viewport.domain(slotCount: 30)
        viewport.magnify(by: 2, anchor: 0.25, slotCount: 30)
        let after = viewport.domain(slotCount: 30)
        XCTAssertEqual(before.lowerBound + 0.25 * (before.upperBound - before.lowerBound),
                       after.lowerBound + 0.25 * (after.upperBound - after.lowerBound), accuracy: 0.0001)
        XCTAssertEqual(viewport.zoom, 4)
        viewport.magnify(by: 1_000, anchor: 0.5, slotCount: 30)
        XCTAssertEqual(viewport.zoom, 30)
        viewport.magnify(by: 0.0001, anchor: 0.5, slotCount: 30)
        XCTAssertEqual(viewport.domain(slotCount: 30), -0.5...29.5)
    }

    func testInvalidNavigationEventsLeaveViewportUnchanged() {
        var viewport = CacheAnalyticsViewport(zoom: 3, position: 0.5)
        let original = viewport.domain(slotCount: 30)
        for factor in [0, -1, Double.nan, Double.infinity] {
            viewport.magnify(by: factor, anchor: 0.5, slotCount: 30)
            XCTAssertEqual(viewport.domain(slotCount: 30), original)
        }
        viewport.magnify(by: 2, anchor: .nan, slotCount: 30)
        viewport.pan(translation: .infinity, plotWidth: 500, slotCount: 30)
        viewport.pan(translation: 100, plotWidth: 0, slotCount: 30)
        viewport.pan(translation: 100, plotWidth: .nan, slotCount: 30)
        XCTAssertEqual(viewport.domain(slotCount: 30), original)
    }

    func testKeyboardRevealPreservesZoomAndIncludesEmptySlots() {
        let slots = CacheHitRateWidgetChartPresentation.slots(for: CacheHitRateWidgetFixture.gaps.report)
        var viewport = CacheAnalyticsViewport(zoom: 3, position: 1)
        viewport.reveal(slot: 1, slotCount: slots.count)
        XCTAssertTrue(viewport.domain(slotCount: slots.count).contains(1))
        XCTAssertEqual(viewport.zoom, 3)
        XCTAssertNil(viewport.selectedSlot(1, slots: slots)?.bucket)
        let visible = viewport.domain(slotCount: slots.count)
        viewport.reveal(slot: 1, slotCount: slots.count)
        XCTAssertEqual(viewport.domain(slotCount: slots.count), visible)
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

    func testExplicitSelectionPersistsWhenPointerLeavesThePlot() {
        let chosen = CacheAnalyticsViewport.committedSelection(2.2, previous: nil, slotCount: 7)
        XCTAssertEqual(chosen, 2)
        XCTAssertEqual(CacheAnalyticsViewport.committedSelection(-0.4, previous: nil, slotCount: 7), 0)
        for coordinate in [nil, -1, 7, Double.nan, Double.infinity] as [Double?] {
            XCTAssertEqual(CacheAnalyticsViewport.committedSelection(coordinate, previous: chosen, slotCount: 7), 2)
        }
        XCTAssertEqual(CacheAnalyticsViewport.committedSelection(4.1, previous: chosen, slotCount: 7), 4)
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
    func testDetailCardKeepsItsLayoutHeightForWideAndCompactWindows() throws {
        let report = CacheHitRateWidgetFixture.month.report
        let slot = try XCTUnwrap(CacheHitRateWidgetChartPresentation.slots(for: report).first)
        for width in [900.0, 440.0] {
            let expectedHeight = width > CacheAnalyticsLayout.singleRowContentWidth ? 184.0 : 232.0
            for selectedSlot in [slot, nil] {
                let view = CacheAnalyticsBucketDetail(slot: selectedSlot, report: report)
                    .frame(width: width)
                let renderer = ImageRenderer(content: view)
                let image = try XCTUnwrap(renderer.nsImage)
                XCTAssertEqual(image.size.width, width, accuracy: 1)
                XCTAssertEqual(image.size.height, expectedHeight, accuracy: 1)
            }
        }
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
