import AppKit
import Foundation
import MonitorCore
import MonitorRuntime
import SwiftUI
import XCTest
@testable import SessionMonitor

final class SidebarCachePeriodTests: XCTestCase {
    func testTodayExcludesYesterdayAndKeepsEmptyHoursFromLocalMidnight() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let now = date("2026-09-30T09:30:00Z")
        let query = try UsagePeriodPreset.today.resolve(referenceDate: now, timeZoneIdentifier: zone.identifier)
        let interval = try DateInterval(start: XCTUnwrap(query.since), end: XCTUnwrap(query.until))
        let report = CacheHitRateWidgetBuilder.build(observations: [
            observation(date("2026-09-29T20:59:59Z"), rate: 0),
            observation(date("2026-09-29T21:00:00Z"), rate: 80),
            observation(date("2026-09-30T09:00:00Z"), rate: 100),
            observation(interval.end, rate: 0)
        ], period: .last24Hours, referenceDate: now, timeZone: zone, interval: interval)
        XCTAssertEqual(report.periodCacheHitRate, 90)
        XCTAssertEqual(report.periodStart, date("2026-09-29T21:00:00Z"))
        let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
        XCTAssertEqual(slots.count, 24)
        XCTAssertEqual(slots.first?.start, interval.start)
        XCTAssertEqual(slots.filter { $0.bucket != nil }.map(\.id), [0, 12])
        XCTAssertEqual(CacheHitRateWidgetLabelFormat.bucketLabel(for: interval.start,
            period: .last24Hours, family: .medium, timeZoneIdentifier: zone.identifier,
            locale: Locale(identifier: "ru_RU")), "00:00")
    }

    func testDSTDaysUse23Or25RealHourlySlots() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        for (day, count) in [("2026-03-08T16:00:00Z", 23), ("2026-11-01T16:00:00Z", 25)] {
            let now = date(day)
            let query = try UsagePeriodPreset.today.resolve(referenceDate: now, timeZoneIdentifier: zone.identifier)
            let interval = try DateInterval(start: XCTUnwrap(query.since), end: XCTUnwrap(query.until))
            let report = CacheHitRateWidgetBuilder.build(observations: [], period: .last24Hours,
                referenceDate: now, timeZone: zone, interval: interval)
            let slots = CacheHitRateWidgetChartPresentation.slots(for: report)
            XCTAssertEqual(slots.count, count)
            XCTAssertEqual(Set(slots.map(\.start)).count, count)
            XCTAssertEqual(report.availability, .noData)
        }
    }

    func testCalendarSevenDaysUsesQueryRatherThanRollingWindowAndEqualComparison() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let now = date("2026-09-30T09:30:00Z")
        let query = try UsagePeriodPreset.lastSevenDays.resolve(referenceDate: now, timeZoneIdentifier: zone.identifier)
        let interval = try DateInterval(start: XCTUnwrap(query.since), end: XCTUnwrap(query.until))
        let report = CacheHitRateWidgetBuilder.build(observations: [
            observation(interval.start, rate: 90),
            observation(interval.start.addingTimeInterval(-1), rate: 70)
        ], period: .last7Days, referenceDate: now, timeZone: zone, interval: interval)
        XCTAssertEqual(report.periodStart, interval.start)
        XCTAssertEqual(report.periodEnd, interval.end)
        XCTAssertEqual(report.comparisonDeltaPercentagePoints, 20)
        XCTAssertEqual(CacheHitRateWidgetChartPresentation.slots(for: report).count, 7)
    }

    func testCalendarThirtyDaysKeepsEveryDayIncludingGaps() throws {
        let now = date("2026-09-30T09:30:00Z")
        let query = try UsagePeriodPreset.lastThirtyDays.resolve(referenceDate: now, timeZoneIdentifier: "UTC")
        let interval = try DateInterval(start: XCTUnwrap(query.since), end: XCTUnwrap(query.until))
        let report = CacheHitRateWidgetBuilder.build(observations: [], period: .last30Days,
            referenceDate: now, timeZone: .gmt, interval: interval)
        XCTAssertEqual(CacheHitRateWidgetChartPresentation.slots(for: report).count, 30)
    }

    func testRuntimePassesCalendarQueryBoundsAndTimeZone() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let runtime = try MonitorRuntime.SessionMonitor(databaseURL: directory.appending(path: "usage.sqlite"))
        let now = date("2026-09-30T09:30:00Z")
        let query = try UsagePeriodPreset.today.resolve(referenceDate: now, timeZoneIdentifier: "Europe/Moscow")
        let report = try await runtime.cacheHitRateWidget(period: .last24Hours, referenceDate: now,
            timeZone: .gmt, query: query)
        XCTAssertEqual(report.periodStart, query.since)
        XCTAssertEqual(report.periodEnd, query.until)
        XCTAssertEqual(report.timeZoneIdentifier, query.timeZoneIdentifier)
    }

    @MainActor
    func testModelForwardsSelectedQueryToSidebarChart() async throws {
        let runtime = StubExplorerRuntime(report: UsageReport(totals: UsageTotals(), sessions: [], diagnostics: [:]))
        let model = SessionExplorerModel(runtimeFactory: { runtime })
        let periodQuery = try UsagePeriodPreset.today.resolve(referenceDate: date("2026-09-30T09:30:00Z"),
            timeZoneIdentifier: "Europe/Moscow")
        let query = try UsageQuery(since: periodQuery.since, until: periodQuery.until,
            timeZoneIdentifier: periodQuery.timeZoneIdentifier, accountScope: UsageAccountScope(profileID: "personal"))
        await model.loadIfNeeded(query: query)
        await model.loadCacheHitRateWidget(period: .last24Hours, timeZone: .current, followsReportScope: true)
        let forwardedQuery = await runtime.lastCacheQuery
        XCTAssertEqual(forwardedQuery, query)
        await model.loadCacheHitRateWidget(period: .last14Days, timeZone: .current)
        let independentQuery = await runtime.lastCacheQuery
        XCTAssertNil(independentQuery)
    }

    @MainActor
    func testTodayRendersAtSidebarWidthInBothThemes() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        let now = date("2026-09-30T09:30:00Z")
        let query = try UsagePeriodPreset.today.resolve(referenceDate: now, timeZoneIdentifier: zone.identifier)
        let interval = try DateInterval(start: XCTUnwrap(query.since), end: XCTUnwrap(query.until))
        let observations = (0..<13).map {
            observation(interval.start.addingTimeInterval(Double($0) * 3_600), rate: Int64(80 + $0))
        }
        let report = CacheHitRateWidgetBuilder.build(observations: observations, period: .last24Hours,
            referenceDate: now, timeZone: zone, interval: interval)
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: CacheHitRateWidget(report: report, family: .medium,
                containerStyle: .embedded, periodTitle: "Today")
                .frame(width: 290).environment(\.colorScheme, scheme))
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, 290, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = "Today sidebar \(scheme)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func observation(_ timestamp: Date, rate: Int64) -> CacheHitRateObservation {
        .init(timestamp: timestamp, sessionID: timestamp.description,
              cacheableInputTokens: 100, cachedInputTokens: rate)
    }

    private func date(_ value: String) -> Date {
        // Deterministic fixtures independent of the computer's locale/time zone.
        guard let date = try? Date.ISO8601FormatStyle().parse(value) else {
            preconditionFailure("Invalid fixture date: \(value)")
        }
        return date
    }
}
