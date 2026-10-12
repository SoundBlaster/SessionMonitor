import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

/// SM-722: the whole-session overview slider under the context-anatomy chart.
final class ContextAnatomyOverviewTests: XCTestCase {
    private typealias Overview = ContextAnatomyOverview

    // MARK: Downsampled preview

    func testEachRequestGetsItsOwnBucketWhenTheyFit() {
        let anatomy = anatomy(inputs: [10, 20, 40])
        let buckets = Overview.buckets(of: anatomy.steps, count: 10)
        XCTAssertEqual(buckets.map(\.firstIndex), [1, 2, 3])
        XCTAssertEqual(buckets.map(\.peakContext), [10, 20, 40])
        XCTAssertEqual(buckets.map(\.zone), anatomy.steps.map(\.zone))
    }

    func testBucketsKeepTheLargestContextSoPeaksAndDropsStayVisible() {
        let anatomy = anatomy(inputs: [10, 90, 30, 100, 5, 7])
        let buckets = Overview.buckets(of: anatomy.steps, count: 3)
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets.map(\.firstIndex), [1, 3, 5])
        XCTAssertEqual(buckets.map(\.lastIndex), [2, 4, 6])
        XCTAssertEqual(buckets.map(\.peakContext), [90, 100, 7])
        XCTAssertEqual(buckets[1].zone, anatomy.steps[3].zone, "the zone follows the largest request")
    }

    func testBucketsCoverEveryRequestExactlyOnce() {
        let anatomy = anatomy(inputs: (1...1_000).map { Int64($0) })
        let buckets = Overview.buckets(of: anatomy.steps, count: 333)
        XCTAssertLessThanOrEqual(buckets.count, 333)
        XCTAssertEqual(buckets.first?.firstIndex, 1)
        XCTAssertEqual(buckets.last?.lastIndex, 1_000)
        for (previous, next) in zip(buckets, buckets.dropFirst()) {
            XCTAssertEqual(previous.lastIndex + 1, next.firstIndex)
        }
    }

    func testNoStepsOrNoRoomMeansNoBuckets() {
        XCTAssertEqual(Overview.buckets(of: [], count: 10), [])
        XCTAssertEqual(Overview.buckets(of: anatomy(inputs: [1, 2]).steps, count: 0), [])
    }

    // MARK: Window frame and pointer mapping

    func testWindowFrameMapsTheVisibleDomainOntoTheOverviewWidth() {
        let frame = Overview.windowFrame(for: 6_846.5...7_196.5, stepCount: 7_196, width: 719.6)
        XCTAssertEqual(frame.lowerBound, 684.6, accuracy: 1e-6)
        XCTAssertEqual(frame.upperBound, 719.6, accuracy: 1e-6)
        XCTAssertEqual(Overview.windowFrame(for: 0.5...102.5, stepCount: 102, width: 600), 0...600)
    }

    func testAnOverviewPointMapsBackToTheRequestAxis() {
        XCTAssertEqual(Overview.axisPosition(atX: 0, stepCount: 100, width: 500), 0.5)
        XCTAssertEqual(Overview.axisPosition(atX: 500, stepCount: 100, width: 500), 100.5)
        XCTAssertEqual(Overview.axisPosition(atX: 250, stepCount: 100, width: 500), 50.5)
        XCTAssertEqual(Overview.axisPosition(atX: -40, stepCount: 100, width: 500), 0.5, "clamped to the session")
    }

    // MARK: Moving the window from the overview

    func testCenteringMovesTheWindowWithoutChangingItsSpan() {
        let viewport = ContextAnatomyViewport.initial(stepCount: 7_196, plotWidth: 700)
        let centered = viewport.centered(on: 1_000.5, stepCount: 7_196)
        XCTAssertEqual(centered.span, viewport.span)
        XCTAssertEqual(centered.domain.lowerBound + centered.span / 2, 1_000.5, accuracy: 1e-9)
        XCTAssertEqual(viewport.centered(on: 0, stepCount: 7_196).domain.lowerBound, 0.5, "clamped at the start")
        XCTAssertEqual(viewport.centered(on: 9_999, stepCount: 7_196), viewport, "clamped at the end")
    }

    // MARK: VoiceOver paging

    func testAdjustingTheOverviewPagesTheWindowByItsOwnWidth() {
        let domain = 6_846.5...7_196.5
        XCTAssertEqual(Overview.pagedCenter(for: domain, by: -1), 6_671.5)
        XCTAssertEqual(Overview.pagedCenter(for: domain, by: 1), 7_371.5,
                       "the viewport clamps a page past the end")
        XCTAssertEqual(Overview.pagedCenter(for: domain, by: 0), 7_021.5)
    }

    // MARK: Fixtures

    private func anatomy(inputs: [Int64]) -> ContextAnatomy {
        guard let query = try? UsageQuery(since: nil, until: nil) else {
            preconditionFailure("UsageQuery without bounds must be valid")
        }
        let points = inputs.enumerated().map { offset, input in
            RequestTimelinePoint(
                id: "r\(offset)", sessionID: "s", timestamp: Date(timeIntervalSince1970: Double(offset)),
                kind: .usageRequest, inputTokens: input, cachedInputTokens: nil, uncachedInputTokens: nil,
                outputTokens: nil, reasoningOutputTokens: nil, model: nil
            )
        }
        return ContextAnatomyBuilder.build(RequestTimeline(sessionID: "s", query: query, points: points))
    }
}
