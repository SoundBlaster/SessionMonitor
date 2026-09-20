import AppKit
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class RequestTimelineDensityTests: XCTestCase {
    func testSemanticFloodCannotEvictUsageOrPeaks() {
        let points = fixture()
        let chart = RequestTimelineChartLayout.chartPoints(from: points)
        XCTAssertLessThanOrEqual(chart.count, 256)
        XCTAssertEqual(chart.filter { $0.kind == .usageRequest }.count, 192)
        XCTAssertTrue(chart.contains { $0.id == "usage-213" })
        XCTAssertTrue(chart.contains { $0.id == "usage-337" })
        XCTAssertTrue(chart.contains { $0.id == "usage-0" })
        XCTAssertTrue(chart.contains { $0.id == "usage-580" })
        XCTAssertTrue(chart.contains { $0.kind == .compaction })
        XCTAssertEqual(points.count, 2_982)
    }

    func testLastEventsSamplesOnlyVisibleWindow() {
        let points = fixture()
        let domain = DateInterval(start: date(16_000), end: date(18_000))
        let projected = RequestTimelineChartLayout.chartPoints(from: points, visibleDomain: domain)
        XCTAssertFalse(projected.isEmpty)
        XCTAssertTrue(projected.allSatisfy { domain.contains($0.timestamp) })
        XCTAssertGreaterThan(projected.filter { $0.kind == .usageRequest }.count, 30)
        XCTAssertFalse(projected.contains { $0.id == "usage-213" })
    }

    func testSparseAndEmptyRetainUnknownAndObservedZero() {
        let unknown = point("unknown", index: 0, kind: .usageRequest)
        let zero = point("zero", index: 1, kind: .usageRequest, cached: 0, uncached: 0)
        XCTAssertEqual(RequestTimelineChartLayout.chartPoints(from: [unknown, zero]), [unknown, zero])
        XCTAssertTrue(RequestTimelineChartLayout.chartPoints(from: []).isEmpty)
        XCTAssertTrue(RequestTimelineChartLayout.chartPoints(
            from: [zero], visibleDomain: DateInterval(start: date(100), end: date(200))
        ).isEmpty)
    }

    func testEventOnlyProjectionRemainsBoundedAndKeepsRareKinds() {
        let events = fixture().filter { $0.kind != .usageRequest }
        let chart = RequestTimelineChartLayout.chartPoints(from: events)
        XCTAssertLessThanOrEqual(chart.count, 256)
        XCTAssertEqual(Set(chart.map(\.kind)), Set(events.map(\.kind)))
        XCTAssertEqual(chart, RequestTimelineChartLayout.chartPoints(from: events.reversed()))
    }

    func testRenderDenseTimelineInLightDarkAndNarrowWidth() async throws {
        let query = try UsageQuery(timeZoneIdentifier: "UTC")
        let source = DensityTimelineSource(
            value: RequestTimeline(sessionID: "fixture", query: query, points: fixture())
        )
        let model = RequestTimelineModel()
        await model.load(sessionID: "fixture", query: query, source: source)
        for (name, width, scheme) in [("dark", 1_000.0, ColorScheme.dark), ("light-narrow", 560.0, .light)] {
            let axis = try XCTUnwrap(model.axis)
            let points = RequestTimelineChartLayout.chartPoints(from: source.value.points)
            let view = RequestTimelinePlot(points: points, axis: axis, timeZone: .gmt, width: width)
                .frame(width: width + 8)
                .background(scheme == .dark ? Color.black : Color.white)
                .environment(\.colorScheme, scheme)
                .environment(\.locale, Locale(identifier: "en_US"))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            XCTAssertEqual(image.size.width, width + 8, accuracy: 1)
            let attachment = XCTAttachment(image: image)
            attachment.name = "SM-312-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            // Local-only evidence, never a raw production archive.
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SM-312-\(name).png"))
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

private struct DensityTimelineSource: RequestTimelineSource {
    let value: RequestTimeline
    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline { value }
}
