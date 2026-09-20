import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

@MainActor
final class RequestTimelineAxisTests: XCTestCase {
    func testYAxisReservesSafeTopInsetForLargeLabels() {
        XCTAssertGreaterThanOrEqual(RequestTimelineChartLayout.yAxisTopInset, 16)
        XCTAssertEqual(RequestTimelineChartLayout.chartHeight, 250)
    }

    func testLargeTokenValuesKeepAxisLayoutReadable() throws {
        let query = try UsageQuery(since: date(0), until: date(10_000))
        let axis = try XCTUnwrap(RequestTimelineAxis(
            points: [point("large", seconds: 100, cached: 280_000, uncached: 20_000)],
            query: query,
            mode: .fitToData
        ))

        XCTAssertTrue(axis.visibleDomain.contains(date(100)))
        XCTAssertGreaterThanOrEqual(RequestTimelineChartLayout.yAxisTopInset, 16)
    }

    func testZeroAndSmallValuesUseTheSameSafeLayout() throws {
        let query = try UsageQuery(since: date(0), until: date(10_000))
        for tokens: Int64 in [0, 1, 10] {
            let axis = try XCTUnwrap(RequestTimelineAxis(
                points: [point("small-\(tokens)", seconds: 100, cached: tokens, uncached: 0)],
                query: query,
                mode: .fitToData
            ))
            XCTAssertTrue(axis.visibleDomain.contains(date(100)))
            XCTAssertGreaterThanOrEqual(RequestTimelineChartLayout.yAxisTopInset, 16)
        }
    }

    func testAllRangeModesShareTheSafeYAxisLayout() throws {
        let query = try UsageQuery(since: date(0), until: date(50_000))
        let points = [
            point("early", seconds: 100, cached: 300_000, uncached: 1),
            point("late", seconds: 40_000, cached: 1, uncached: 1)
        ]

        for mode in RequestTimelineRangeMode.allCases {
            let axis = try XCTUnwrap(RequestTimelineAxis(points: points, query: query, mode: mode))
            XCTAssertGreaterThan(axis.visibleDomain.duration, 0)
            XCTAssertGreaterThanOrEqual(RequestTimelineChartLayout.yAxisTopInset, 16)
        }
    }

    func testTimelineAccessibilityLabelRemainsComplete() {
        XCTAssertEqual(
            RequestTimelineChartLayout.accessibilityLabel,
            "Known cached and uncached token sums over time"
        )
    }

    func testSeparatedClustersKeepAbsoluteSpanAndOfferLastEventsNavigation() throws {
        let points = [
            point("early-1", seconds: 100),
            point("early-2", seconds: 110),
            point("late-1", seconds: 40_000),
            point("late-2", seconds: 40_010)
        ]
        let query = try UsageQuery(
            since: date(0),
            until: date(50_000),
            timeZoneIdentifier: "Europe/Moscow"
        )

        let fit = try XCTUnwrap(RequestTimelineAxis(points: points, query: query, mode: .fitToData))
        let full = try XCTUnwrap(RequestTimelineAxis(points: points, query: query, mode: .fullQuery))
        let last = try XCTUnwrap(RequestTimelineAxis(points: points, query: query, mode: .lastEvents))

        XCTAssertEqual(fit.dataBounds.start, date(100))
        XCTAssertEqual(fit.dataBounds.end, date(40_010))
        XCTAssertLessThan(fit.dataDomain.duration, full.queryDomain.duration)
        XCTAssertEqual(full.visibleDomain, full.queryDomain)
        XCTAssertGreaterThan(last.visibleDomain.start, fit.dataBounds.start)
        XCTAssertLessThan(last.visibleDomain.start, date(40_010 - 15 * 60))
        XCTAssertGreaterThan(last.visibleDomain.end, date(40_010))
        XCTAssertTrue(last.visibleDomain.contains(date(40_010)))
    }

    func testBeginningAndEndingClustersRemainReadableInFitAndFullModes() throws {
        let query = try UsageQuery(since: date(0), until: date(10_000))
        let beginning = try XCTUnwrap(RequestTimelineAxis(
            points: [point("a", seconds: 10), point("b", seconds: 20)],
            query: query,
            mode: .fitToData
        ))
        let ending = try XCTUnwrap(RequestTimelineAxis(
            points: [point("a", seconds: 9_980), point("b", seconds: 9_990)],
            query: query,
            mode: .fitToData
        ))
        let fullBeginning = try XCTUnwrap(RequestTimelineAxis(
            points: [point("a", seconds: 10), point("b", seconds: 20)],
            query: query,
            mode: .fullQuery
        ))
        let fullEnding = try XCTUnwrap(RequestTimelineAxis(
            points: [point("a", seconds: 9_980), point("b", seconds: 9_990)],
            query: query,
            mode: .fullQuery
        ))

        XCTAssertTrue(beginning.visibleDomain.contains(date(10)))
        XCTAssertTrue(beginning.visibleDomain.contains(date(20)))
        XCTAssertTrue(ending.visibleDomain.contains(date(9_980)))
        XCTAssertTrue(ending.visibleDomain.contains(date(9_990)))
        XCTAssertEqual(fullBeginning.visibleDomain, fullBeginning.queryDomain)
        XCTAssertEqual(fullEnding.visibleDomain, fullEnding.queryDomain)
    }

    func testDenseTimelineKeepsAbsoluteDomainIndependentOfPointCount() throws {
        let query = try UsageQuery(since: date(0), until: date(10_000))
        let sparse = try XCTUnwrap(RequestTimelineAxis(
            points: [point("a", seconds: 100), point("b", seconds: 130)],
            query: query,
            mode: .fitToData
        ))
        let dense = try XCTUnwrap(RequestTimelineAxis(
            points: (0..<100).map { point("dense-\($0)", seconds: 100 + Double($0) / 3) },
            query: query,
            mode: .fitToData
        ))

        XCTAssertEqual(sparse.visibleDomain.start, dense.visibleDomain.start)
        XCTAssertEqual(sparse.visibleDomain.duration, dense.visibleDomain.duration, accuracy: 5)
    }

    func testDenseTimelineChartCapsPresentationMarksAndPreservesBounds() {
        let points = (0..<2_545).map { index in
            point("dense-\(index)", seconds: Double(index))
        }

        let projection = TimelineAggregation(points: points,
            domain: DateInterval(start: date(0), end: date(2_544)), width: 560)
        XCTAssertLessThanOrEqual(projection.buckets.count, projection.capacity)
        XCTAssertEqual(projection.requestCount, points.count)
        XCTAssertEqual(projection.buckets.reduce(0) { $0 + $1.cached }, 80 * Double(points.count))
    }

    func testEmptyTimelineHasNoAxis() throws {
        let query = try UsageQuery()

        XCTAssertNil(RequestTimelineAxis(points: [], query: query, mode: .fitToData))
    }

    func testRangeModeSwitchingPreservesAbsoluteDataAndUsageTotals() async throws {
        let query = try UsageQuery(
            since: date(0),
            until: date(50_000),
            timeZoneIdentifier: "Europe/Moscow"
        )
        let timeline = RequestTimeline(
            sessionID: "session",
            query: query,
            points: [point("late", seconds: 40_010)]
        )
        let source = StubTimelineSource(timeline: timeline)
        let model = RequestTimelineModel()

        await model.load(sessionID: "session", query: query, source: source)
        let fit = try XCTUnwrap(model.axis)
        model.setRangeMode(.fullQuery)
        let full = try XCTUnwrap(model.axis)
        model.setRangeMode(.lastEvents)
        let last = try XCTUnwrap(model.axis)

        XCTAssertEqual(model.rangeMode, .lastEvents)
        XCTAssertEqual(fit.dataBounds, full.dataBounds)
        XCTAssertEqual(fit.dataBounds, last.dataBounds)
        XCTAssertEqual(fit.dataBounds.start, date(40_010))
        XCTAssertEqual(full.visibleDomain, full.queryDomain)
        XCTAssertTrue(last.visibleDomain.contains(date(40_010)))
    }

    func testTimezoneChangesLabelsButNotAbsoluteAxis() throws {
        let points = [point("request", seconds: 0)]
        let utcQuery = try UsageQuery(
            since: date(-100),
            until: date(100),
            timeZoneIdentifier: "UTC"
        )
        let moscowQuery = try UsageQuery(
            since: date(-100),
            until: date(100),
            timeZoneIdentifier: "Europe/Moscow"
        )
        let utc = try XCTUnwrap(RequestTimelineAxis(points: points, query: utcQuery, mode: .fitToData))
        let moscow = try XCTUnwrap(RequestTimelineAxis(points: points, query: moscowQuery, mode: .fitToData))

        XCTAssertEqual(utc.dataBounds, moscow.dataBounds)
        XCTAssertEqual(utc.visibleDomain, moscow.visibleDomain)
        let utcTimeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let moscowTimeZone = try XCTUnwrap(TimeZone(identifier: "Europe/Moscow"))
        XCTAssertNotEqual(
            timelineDateLabel(date(0), timeZone: utcTimeZone),
            timelineDateLabel(date(0), timeZone: moscowTimeZone)
        )
    }

    private func point(
        _ id: String,
        seconds: TimeInterval,
        cached: Int64 = 80,
        uncached: Int64 = 20
    ) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id,
            sessionID: "session",
            timestamp: date(seconds),
            kind: .usageRequest,
            cachedInputTokens: cached,
            uncachedInputTokens: uncached
        )
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }

}

private struct StubTimelineSource: RequestTimelineSource {
    let timeline: RequestTimeline

    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline {
        timeline
    }
}
