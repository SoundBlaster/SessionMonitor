import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

@MainActor
final class TimelineViewportTests: XCTestCase {
    func testZoomAndPanClampWhilePreservingQueryAndData() async throws {
        let model = try await loaded()
        let original = try XCTUnwrap(model.timeline)
        let fit = try XCTUnwrap(model.axis)
        model.zoom(by: 0.5)
        XCTAssertEqual(try XCTUnwrap(model.axis).visibleDomain.duration, fit.visibleDomain.duration / 2, accuracy: 0.01)
        model.pan(by: 100)
        let end = try XCTUnwrap(model.axis)
        XCTAssertEqual(end.visibleDomain.end, end.navigationDomain.end)
        model.pan(by: -100)
        let start = try XCTUnwrap(model.axis)
        XCTAssertEqual(start.visibleDomain.start, start.navigationDomain.start)
        XCTAssertEqual(model.timeline?.query, original.query)
        XCTAssertEqual(model.timeline?.points, original.points)
    }

    func testSliderExtremesAndMinimumZoom() async throws {
        let model = try await loaded()
        model.zoom(by: 0.0001)
        XCTAssertEqual(model.axis?.visibleDomain.duration, 60)
        model.scroll(to: 1)
        XCTAssertEqual(model.axis?.visibleDomain.end, model.axis?.navigationDomain.end)
        model.scroll(to: 0)
        XCTAssertEqual(model.axis?.visibleDomain.start, model.axis?.navigationDomain.start)
        XCTAssertEqual(model.scrollPosition, 0)
    }

    func testInvalidFromToLeavesViewportUnchanged() async throws {
        let model = try await loaded()
        let previous = model.axis?.visibleDomain
        model.applyRange(from: date(900), to: date(100))
        XCTAssertNotNil(model.rangeError)
        XCTAssertEqual(model.axis?.visibleDomain, previous)
        model.applyRange(from: date(-10_000), to: date(100))
        XCTAssertNotNil(model.rangeError)
        XCTAssertEqual(model.axis?.visibleDomain, previous)
        model.applyRange(from: date(100), to: date(900))
        XCTAssertNil(model.rangeError)
        XCTAssertEqual(model.rangeMode, .custom)
        XCTAssertEqual(model.axis?.visibleDomain, DateInterval(start: date(100), end: date(900)))
    }

    func testRefreshPreservesCustomRangeAndNewSessionResetsIt() async throws {
        let model = try await loaded()
        model.applyRange(from: date(100), to: date(900))
        let previous = model.axis?.visibleDomain
        let timeline = try XCTUnwrap(model.timeline)
        await model.load(sessionID: "one", query: timeline.query, source: ViewportSource(value: timeline))
        XCTAssertEqual(model.axis?.visibleDomain, previous)
        let next = RequestTimeline(sessionID: "two", query: timeline.query, points: timeline.points)
        await model.load(sessionID: "two", query: next.query, source: ViewportSource(value: next))
        XCTAssertEqual(model.rangeMode, .fitToData)
        XCTAssertNil(model.customDomain)
    }

    func testShortBoundsAndNonfiniteNavigationAreSafe() async throws {
        let short = DateInterval(start: date(0), end: date(1))
        XCTAssertEqual(TimelineViewport.clamp(short, to: short), short)
        let model = try await loaded()
        let before = model.axis?.visibleDomain
        model.zoom(by: .nan)
        model.pan(by: .infinity)
        model.scroll(to: .nan)
        XCTAssertEqual(model.axis?.visibleDomain, before)
    }

    private func loaded() async throws -> RequestTimelineModel {
        let query = try UsageQuery(since: date(0), until: date(10_000), timeZoneIdentifier: "Europe/Moscow")
        let points = [100, 9_900].map { seconds in
            RequestTimelinePoint(id: "p-\(seconds)", sessionID: "one", timestamp: date(seconds),
                                 kind: .usageRequest, cachedInputTokens: 80, uncachedInputTokens: 20)
        }
        let value = RequestTimeline(sessionID: "one", query: query, points: points)
        let model = RequestTimelineModel()
        await model.load(sessionID: "one", query: query, source: ViewportSource(value: value))
        return model
    }

    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: seconds) }
}

private struct ViewportSource: RequestTimelineSource {
    let value: RequestTimeline
    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline { value }
}
