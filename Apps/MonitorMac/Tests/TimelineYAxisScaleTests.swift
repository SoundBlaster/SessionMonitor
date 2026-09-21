import AppKit
import Foundation
import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

@MainActor
final class TimelineYAxisScaleTests: XCTestCase {
    func testOffscreenSessionPeakKeepsScaleStableWhileZoomingAndPanning() async throws {
        let query = try UsageQuery()
        let points = [
            point("early", seconds: 0, cached: 40_000, uncached: 10_000),
            point("middle", seconds: 5_000, cached: 60_000, uncached: 20_000),
            point("peak", seconds: 9_500, cached: 700_000, uncached: 300_000)
        ]
        let timeline = RequestTimeline(sessionID: "session", query: query, points: points)
        let model = RequestTimelineModel()
        await model.load(sessionID: timeline.sessionID, query: query, source: TimelineSource(value: timeline))

        let initialAxis = try XCTUnwrap(model.axis)
        let initialScale = TimelineYAxisScale(
            points: points, navigationDomain: initialAxis.navigationDomain, width: 560
        )
        XCTAssertGreaterThan(initialScale.maximumBucketTotal, 900_000)

        model.zoom(by: 0.5)
        let zoomedAxis = try XCTUnwrap(model.axis)
        XCTAssertFalse(zoomedAxis.visibleDomain.contains(date(9_500)))
        let zoomedScale = TimelineYAxisScale(
            points: points, navigationDomain: zoomedAxis.navigationDomain, width: 560
        )
        XCTAssertEqual(zoomedScale, initialScale)

        model.pan(by: 0.5)
        let pannedAxis = try XCTUnwrap(model.axis)
        XCTAssertTrue(pannedAxis.visibleDomain.contains(date(9_500)))
        let pannedScale = TimelineYAxisScale(
            points: points, navigationDomain: pannedAxis.navigationDomain, width: 560
        )
        XCTAssertEqual(pannedScale, initialScale)
    }

    func testScaleCoversVisibleBucketsAcrossViewportWidthsAndPositions() {
        let points = (0..<101).map { index in
            let peak = index == 54 ? 900_000 : 2_000 + index * 37
            return point("request-\(index)", seconds: index * 36,
                         cached: Int64(peak), uncached: Int64(peak / 4))
        }
        let navigation = DateInterval(start: date(0), end: date(3_600))

        for width in [300.0, 560.0, 1_000.0] {
            let scale = TimelineYAxisScale(points: points, navigationDomain: navigation, width: width)
            for visible in [
                navigation,
                DateInterval(start: date(420), end: date(1_620)),
                DateInterval(start: date(1_920), end: date(2_400)),
                DateInterval(start: date(2_400), end: date(3_180))
            ] {
                let aggregation = TimelineAggregation(points: points, domain: visible, width: width)
                let visibleMaximum = aggregation.buckets.map { $0.cached + $0.uncached }.max() ?? 0
                XCTAssertLessThanOrEqual(visibleMaximum, scale.maximumBucketTotal)
                XCTAssertLessThanOrEqual(visibleMaximum, scale.domain.upperBound)
            }
        }
    }

    func testEmptyUnknownAndZeroInputUseFiniteScale() {
        let navigation = DateInterval(start: date(0), end: date(600))
        let cases = [
            [],
            [point("unknown", seconds: 100, cached: nil, uncached: nil)],
            [point("zero", seconds: 200, cached: 0, uncached: 0)]
        ]

        for points in cases {
            let scale = TimelineYAxisScale(points: points, navigationDomain: navigation, width: 560)
            XCTAssertEqual(scale.domain.lowerBound, 0)
            XCTAssertEqual(scale.domain.upperBound, RequestTimelineChartLayout.minimumYAxisUpperBound)
            XCTAssertTrue(scale.domain.upperBound.isFinite)
        }
    }

    func testRenderFitAndZoomWithTheSameSessionYAxis() throws {
        let query = try UsageQuery()
        let points = (0..<80).map { index in
            let peak = index == 74 ? 900_000 : 30_000 + index * 500
            return point("render-\(index)", seconds: index * 120,
                         cached: Int64(peak), uncached: Int64(peak / 5))
        }
        let fitAxis = try XCTUnwrap(RequestTimelineAxis(points: points, query: query, mode: .fitToData))
        let zoomAxis = try XCTUnwrap(RequestTimelineAxis(
            points: points,
            query: query,
            mode: .custom,
            customDomain: DateInterval(start: date(2_000), end: date(6_000))
        ))
        XCTAssertFalse(zoomAxis.visibleDomain.contains(date(74 * 120)))

        let configurations = [
            TimelineRenderConfiguration(name: "fit-dark", axis: fitAxis, colorScheme: .dark, palette: .system),
            TimelineRenderConfiguration(name: "zoom-dark", axis: zoomAxis, colorScheme: .dark, palette: .system),
            TimelineRenderConfiguration(name: "fit-light", axis: fitAxis, colorScheme: .light,
                                        palette: .monochrome),
            TimelineRenderConfiguration(name: "zoom-light", axis: zoomAxis, colorScheme: .light,
                                        palette: .monochrome)
        ]

        for configuration in configurations {
            let view = RequestTimelinePlot(points: points, axis: configuration.axis, timeZone: .gmt,
                                           width: 560, palette: configuration.palette)
                .frame(width: 560)
                .background(configuration.colorScheme == .dark ? Color.black : Color.white)
                .environment(\.colorScheme, configuration.colorScheme)
                .environment(\.locale, Locale(identifier: "en_US"))
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "SM-314-\(configuration.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            let bitmap = try XCTUnwrap(image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)))
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent("SM-314-\(configuration.name).png"))
        }
    }

    private func point(_ id: String, seconds: Int, cached: Int64?, uncached: Int64?) -> RequestTimelinePoint {
        RequestTimelinePoint(id: id, sessionID: "session", timestamp: date(seconds), kind: .usageRequest,
                             cachedInputTokens: cached, uncachedInputTokens: uncached)
    }

    private func date(_ seconds: Int) -> Date {
        Date(timeIntervalSince1970: 1_789_900_000 + Double(seconds))
    }
}

private struct TimelineSource: RequestTimelineSource {
    let value: RequestTimeline
    func timeline(sessionID: String, query: UsageQuery) async throws -> RequestTimeline { value }
}

private struct TimelineRenderConfiguration {
    let name: String
    let axis: RequestTimelineAxis
    let colorScheme: ColorScheme
    let palette: UsageChartPalette
}
