import AppKit
import Foundation
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

final class CacheHitRateWidgetBucketDetailTests: XCTestCase {
    private let english = Locale(identifier: "en_US")

    func testPointerPositionMapsToTheNearestPlottedSlot() {
        let detail = CacheHitRateWidgetBucketDetail.self
        XCTAssertEqual(detail.slotID(forX: -0.5, slotCount: 7), 0)
        XCTAssertEqual(detail.slotID(forX: 0.49, slotCount: 7), 0)
        XCTAssertEqual(detail.slotID(forX: 0.5, slotCount: 7), 1)
        XCTAssertEqual(detail.slotID(forX: 6.49, slotCount: 7), 6)
        XCTAssertNil(detail.slotID(forX: 6.5, slotCount: 7))
        XCTAssertNil(detail.slotID(forX: -0.51, slotCount: 7))
        XCTAssertNil(detail.slotID(forX: .nan, slotCount: 7))
        XCTAssertNil(detail.slotID(forX: 0, slotCount: 0))
    }

    func testDailyDetailNamesDateAverageRangeAndSessionCountWithoutIdentities() throws {
        let report = try weekReport()
        let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
        let monday = try XCTUnwrap(slots.first { $0.bucket?.sampleCount == 2 })
        let text = CacheHitRateWidgetBucketDetail.text(for: monday, report: report, locale: english)
        XCTAssertEqual(text, "Mon, Sep 28 · avg 85.0% · min–max 80–90% · 2 sessions")
        XCTAssertFalse(text.contains("session-"), "no session identity may reach the chart text")

        let saturday = try XCTUnwrap(slots.first { $0.bucket?.sampleCount == 1 })
        XCTAssertEqual(CacheHitRateWidgetBucketDetail.text(for: saturday, report: report, locale: english),
                       "Sat, Sep 26 · avg 95.0% · min–max 95–95% · 1 session")
    }

    func testAnIntervalWithoutDataSaysSoInsteadOfShowingZero() throws {
        let report = try weekReport()
        let empty = try XCTUnwrap(CacheHitRateWidgetChartPresentation.slots(for: report)
            .first { $0.bucket == nil })
        let text = CacheHitRateWidgetBucketDetail.text(for: empty, report: report, locale: english)
        XCTAssertTrue(text.hasSuffix("no cache range to show"), text)
        XCTAssertFalse(text.contains("0%"), text)
    }

    func testHourlySlotsNameTheHourInTheReportTimeZone() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let now = date("2026-09-30T09:30:00Z")
        let query = try UsagePeriodPreset.today.resolve(referenceDate: now, timeZoneIdentifier: zone.identifier)
        let interval = try DateInterval(start: XCTUnwrap(query.since), end: XCTUnwrap(query.until))
        let report = CacheHitRateWidgetBuilder.build(
            observations: requests(interval.start.addingTimeInterval(10 * 3_600), session: "a", rate: 90),
            period: .last24Hours, referenceDate: now, timeZone: zone, interval: interval)
        let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
        let text = CacheHitRateWidgetBucketDetail.text(for: slots[10], report: report,
                                                       locale: Locale(identifier: "en_GB"))
        XCTAssertTrue(text.contains("10:00"), text)
        XCTAssertTrue(text.contains("30"), text)
    }

    func testAccessibilityTextMatchesTheVisibleTextWhenThereAreNoOutliers() throws {
        let report = try weekReport()
        let slot = try XCTUnwrap(CacheHitRateWidgetChartPresentation.slots(for: report).first { $0.bucket != nil })
        XCTAssertEqual(CacheHitRateWidgetBucketDetail.accessibilityText(for: slot, report: report, locale: english),
                       CacheHitRateWidgetBucketDetail.text(for: slot, report: report, locale: english))
    }

    @MainActor
    func testInspectingWidgetRendersAtSidebarWidth() throws {
        let report = try weekReport()
        let renderer = ImageRenderer(content: CacheHitRateWidget(
            report: report, family: .medium, containerStyle: .embedded, periodTitle: "Last 7 Days",
            inspectsBuckets: true).frame(width: 290))
        let image = try XCTUnwrap(renderer.nsImage)
        XCTAssertEqual(image.size.width, 290, accuracy: 1)
        let attachment = XCTAttachment(image: image)
        attachment.name = "Sidebar chart with the hover line"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testClickingADaySelectsThatDayAndAnEmptyDaySelectsNothing() throws {
        let report = try weekReport()
        let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
        let monday = try XCTUnwrap(slots.first { $0.bucket?.sampleCount == 2 })
        let interval = try XCTUnwrap(
            CacheHitRateWidgetBucketDetail.interval(ofSlot: monday.id, in: slots, report: report))
        XCTAssertEqual(interval.start, date("2026-09-28T00:00:00Z"))
        XCTAssertEqual(interval.end, date("2026-09-29T00:00:00Z"))
        let empty = try XCTUnwrap(slots.first { $0.bucket == nil })
        XCTAssertNil(CacheHitRateWidgetBucketDetail.interval(ofSlot: empty.id, in: slots, report: report))
        XCTAssertNil(CacheHitRateWidgetBucketDetail.interval(ofSlot: 99, in: slots, report: report))
    }

    func testTheLastSlotEndsAtThePeriodEnd() throws {
        let report = try weekReport()
        let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
        let last = try XCTUnwrap(slots.last)
        let bucketed = CacheHitRateWidgetSlot(id: last.id, start: last.start, bucket: slots.compactMap(\.bucket).first)
        let interval = try XCTUnwrap(CacheHitRateWidgetBucketDetail.interval(
            ofSlot: last.id, in: Array(slots.dropLast()) + [bucketed], report: report))
        XCTAssertEqual(interval.end, report.periodEnd)
    }

    func testFocusLabelNamesADayOrAnHour() {
        let day = DateInterval(start: date("2026-09-28T00:00:00Z"), end: date("2026-09-29T00:00:00Z"))
        XCTAssertEqual(CacheHitRateWidgetBucketDetail.focusLabel(day, timeZoneIdentifier: "UTC", locale: english),
                       "Sep 28")
        let hour = DateInterval(start: date("2026-09-30T06:00:00Z"), end: date("2026-09-30T07:00:00Z"))
        let label = CacheHitRateWidgetBucketDetail.focusLabel(hour, timeZoneIdentifier: "Europe/Moscow",
                                                              locale: english)
        XCTAssertTrue(label.contains("9:00"), label)
    }

    private func weekReport() throws -> CacheHitRateWidgetReport {
        let now = date("2026-09-30T09:30:00Z")
        let query = try UsagePeriodPreset.lastSevenDays.resolve(referenceDate: now, timeZoneIdentifier: "UTC")
        let interval = try DateInterval(start: XCTUnwrap(query.since), end: XCTUnwrap(query.until))
        return CacheHitRateWidgetBuilder.build(observations:
            requests(date("2026-09-28T10:00:00Z"), session: "session-a", rate: 80)
            + requests(date("2026-09-28T11:00:00Z"), session: "session-b", rate: 90)
            + requests(date("2026-09-26T10:00:00Z"), session: "session-c", rate: 95),
        period: .last7Days, referenceDate: now, timeZone: .gmt, interval: interval)
    }

    /// Two requests: a session with a single request is a cold start and is not plotted.
    private func requests(_ timestamp: Date, session: String, rate: Int64) -> [CacheHitRateObservation] {
        [0, 60].map {
            .init(timestamp: timestamp.addingTimeInterval($0), sessionID: session,
                  cacheableInputTokens: 100, cachedInputTokens: rate)
        }
    }

    private func date(_ value: String) -> Date {
        guard let date = try? Date.ISO8601FormatStyle().parse(value) else {
            preconditionFailure("Invalid fixture date: \(value)")
        }
        return date
    }
}
