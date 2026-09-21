import AppKit
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class RequestTimelineDensityTests: XCTestCase {
    func testSemanticFloodRetainsEveryRequestAndToken() {
        let points = fixture()
        let projection = aggregate(points)
        XCTAssertEqual(projection.requestCount, 581)
        XCTAssertEqual(projection.buckets.reduce(0) { $0 + $1.eventCount }, 2_401)
        XCTAssertEqual(projection.buckets.reduce(0) { $0 + $1.cached },
                       points.reduce(0) { $0 + Double($1.cachedInputTokens ?? 0) })
        XCTAssertEqual(projection.buckets.reduce(0) { $0 + $1.uncached },
                       points.reduce(0) { $0 + Double($1.uncachedInputTokens ?? 0) })
        XCTAssertEqual(projection.buckets.reduce(0) { $0 + ($1.events[.compaction] ?? 0) }, 1)
    }

    func testPixelBudgetAdaptsToWidthAndNeverExceedsLimit() {
        let narrow = aggregate(fixture(), width: 300)
        let wide = aggregate(fixture(), width: 1_000)
        XCTAssertLessThan(narrow.capacity, wide.capacity)
        XCTAssertLessThanOrEqual(narrow.buckets.count, narrow.capacity)
        XCTAssertLessThanOrEqual(wide.buckets.count, wide.capacity)
        XCTAssertEqual(aggregate(fixture(), width: .greatestFiniteMagnitude).capacity, 120)
        XCTAssertEqual(aggregate(fixture(), width: .nan).capacity, 1)
        XCTAssertEqual(narrow.requestCount, wide.requestCount)
    }

    func testMissingTokensStayUnknownAndZeroStaysKnown() {
        let points = [point("nil", index: 1, kind: .usageRequest),
                      point("zero", index: 2, kind: .usageRequest, cached: 0, uncached: 0),
                      point("partial", index: 3, kind: .usageRequest, cached: 100)]
        let projection = aggregate(points, width: 80)
        XCTAssertEqual(projection.requestCount, 3)
        XCTAssertEqual(projection.unknownRequestCount, 2)
        XCTAssertEqual(projection.buckets.first?.knownRequestCount, 1)
        XCTAssertEqual(projection.buckets.first?.cached, 0)
    }

    func testBoundariesAndDuplicateTimestampsAreCountedOnce() {
        let points = [point("first", index: 0, kind: .usageRequest, cached: 5, uncached: 1),
                      point("same", index: 0, kind: .usageRequest, cached: 7, uncached: 2),
                      point("last", index: 100, kind: .usageRequest, cached: 11, uncached: 3),
                      point("outside", index: 101, kind: .usageRequest, cached: 999, uncached: 0)]
        let projection = TimelineAggregation(points: points,
            domain: DateInterval(start: date(0), end: date(100)), width: 500)
        XCTAssertEqual(projection.requestCount, 3)
        XCTAssertEqual(projection.buckets.reduce(0) { $0 + $1.cached }, 23)
        XCTAssertEqual(projection.buckets.first?.requestCount, 2)
        XCTAssertEqual(projection.buckets.last?.requestCount, 1)
        XCTAssertTrue(aggregate([]).buckets.isEmpty)
    }

    func testPointIndexReturnsVisibleSliceAndSummarizesEventKinds() {
        let points = [
            point("event-after", index: 30, kind: .tool),
            point("request-middle", index: 20, kind: .usageRequest, cached: 4, uncached: 2),
            point("event-before", index: 10, kind: .tool),
            point("request-start", index: 15, kind: .usageRequest, cached: 3, uncached: 1),
            point("event-other", index: 20, kind: .wait)
        ]
        let index = TimelinePointIndex(points: points)
        let interval = DateInterval(start: date(15), end: date(20))

        XCTAssertEqual(index.dataBounds, DateInterval(start: date(10), end: date(30)))
        XCTAssertEqual(index.points(in: interval).map(\.id), ["request-start", "event-other", "request-middle"])
        XCTAssertEqual(index.eventCounts(in: interval).map(\.count), [1])
        XCTAssertEqual(index.eventCounts(in: interval).map(\.kind), [.wait])
    }

    func testDenseViewportProjectionStaysBoundedAcrossManyUpdates() throws {
        let points = (0..<20_000).map { index in
            let kind: TimelineEventKind = index.isMultiple(of: 4) ? .tool : .usageRequest
            return point("dense-\(index)", index: index * 3, kind: kind,
                         cached: kind == .usageRequest ? 800 : nil,
                         uncached: kind == .usageRequest ? 200 : nil)
        }
        let pointIndex = TimelinePointIndex(points: points)
        let bounds = try XCTUnwrap(pointIndex.dataBounds)
        let navigation = DateInterval(start: bounds.start, end: bounds.end)
        let query = try UsageQuery()
        let capacity = TimelineAggregation.bucketCapacity(for: 560)
        let cachedScale = TimelineYAxisScale(index: pointIndex, navigationDomain: navigation, width: 560)

        measure {
            for frame in 0..<60 {
                let position = Double(frame) / 59
                let start = navigation.start.addingTimeInterval(navigation.duration * position * 0.75)
                let visibleDomain = DateInterval(start: start, duration: navigation.duration / 4)
                let axis = RequestTimelineAxis(dataBounds: bounds, query: query, mode: .custom,
                                               customDomain: visibleDomain)
                XCTAssertNotNil(axis)
                let projection = TimelineAggregation(index: pointIndex, domain: visibleDomain, width: 560)
                XCTAssertLessThanOrEqual(projection.buckets.count, capacity)
                XCTAssertFalse(pointIndex.eventCounts(in: visibleDomain).isEmpty)
                XCTAssertEqual(cachedScale.domain.lowerBound, 0)
            }
        }
    }

    private func aggregate(_ points: [RequestTimelinePoint], width: Double = 560) -> TimelineAggregation {
        TimelineAggregation(points: points, domain: DateInterval(start: date(0), end: date(18_000)), width: width)
    }

    func testRenderDenseTimelineInLightDarkAndNarrowWidth() async throws {
        let query = try UsageQuery(timeZoneIdentifier: "UTC")
        let source = DensityTimelineSource(
            value: RequestTimeline(sessionID: "fixture", query: query, points: fixture())
        )
        let model = RequestTimelineModel()
        await model.load(sessionID: "fixture", query: query, source: source)
        let renders = [
            TimelineRenderConfiguration(name: "dark-system", width: 1_000, scheme: .dark, palette: .system),
            TimelineRenderConfiguration(name: "light-narrow-monochrome", width: 560, scheme: .light,
                                         palette: .monochrome)
        ]
        for render in renders {
            let axis = try XCTUnwrap(model.axis)
            let points = source.value.points
            let view = RequestTimelinePlot(points: points, axis: axis, timeZone: .gmt, width: render.width,
                                          palette: render.palette)
                .frame(width: render.width)
                .background(render.scheme == .dark ? Color.black : Color.white)
                .environment(\.colorScheme, render.scheme)
                .environment(\.locale, Locale(identifier: "en_US"))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, render.width, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = "SM-313-\(render.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Local-only evidence, never a raw production archive.
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("SM-313-\(render.name).png"))
        }
    }

    private func fixture() -> [RequestTimelinePoint] {
        let usage = (0..<581).map { index in
            point("usage-\(index)", index: index * 30, kind: .usageRequest,
                  cached: index == 213 ? 300_000 : Int64(80_000 + index * 100),
                  uncached: index == 337 ? 70_000 : 2_000)
        }
        let events = (0..<2_400).map { index in
            point("event-\(index)", index: index * 7, kind: index.isMultiple(of: 2) ? .tool : .unknown)
        }
        return (usage + events + [point("compact", index: 8_000, kind: .compaction)])
            .sorted { $0.timestamp < $1.timestamp }
    }

    private func point(_ id: String, index: Int, kind: TimelineEventKind,
                       cached: Int64? = nil, uncached: Int64? = nil) -> RequestTimelinePoint {
        RequestTimelinePoint(id: id, sessionID: "fixture", timestamp: date(index), kind: kind,
                             cachedInputTokens: cached, uncachedInputTokens: uncached)
    }

    private func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: 1_789_900_000 + Double(seconds))
    }
}

private struct TimelineRenderConfiguration {
    let name: String
    let width: Double
    let scheme: ColorScheme
    let palette: UsageChartPalette
}

private struct DensityTimelineSource: RequestTimelineSource {
    let value: RequestTimeline
    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline { value }
}
