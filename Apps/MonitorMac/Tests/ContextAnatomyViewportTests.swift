import Foundation
import XCTest
@testable import SessionMonitor

/// SM-722: the visible request window of the context-anatomy chart, capped by data density.
final class ContextAnatomyViewportTests: XCTestCase {
    private typealias Viewport = ContextAnatomyViewport

    // MARK: Density cap and initial window

    func testDensityCapLimitsTheRequestsPerPointOfPlotWidth() {
        XCTAssertEqual(Viewport.maxSpan(plotWidth: 700), 700 / Viewport.minPointsPerRequest)
        XCTAssertEqual(Viewport.maxSpan(plotWidth: 1), Viewport.minVisibleRequests,
                       "a tiny plot still shows the minimum window")
        XCTAssertEqual(Viewport.maxSpan(plotWidth: .nan), Viewport.minVisibleRequests)
    }

    func testShortSessionsShowEveryRequest() {
        let viewport = Viewport.initial(stepCount: 102, plotWidth: 700)
        XCTAssertEqual(viewport.domain, 0.5...102.5)
        XCTAssertEqual(viewport.visibleIndices(stepCount: 102), 1...102)
    }

    func testLongSessionsOpenOnTheLatestRequestsThatFitTheCap() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(viewport.span, 350)
        XCTAssertEqual(viewport.domain.upperBound, 7_196.5)
        XCTAssertEqual(viewport.domain.lowerBound, 6_846.5)
    }

    func testEmptySessionKeepsTheSingleSlotDomain() {
        XCTAssertEqual(Viewport.initial(stepCount: 0, plotWidth: 700).domain, 0.5...1.5)
        XCTAssertNil(Viewport.initial(stepCount: 0, plotWidth: 700).visibleIndices(stepCount: 0))
    }

    func testNarrowingThePlotKeepsTheRightEdgeAndRespectsTheCap() {
        let wide = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        let narrow = wide.clamped(stepCount: 7_196, plotWidth: 400)
        XCTAssertEqual(narrow.span, 200)
        XCTAssertEqual(narrow.domain.upperBound, wide.domain.upperBound)
    }

    // MARK: Zoom

    func testZoomInKeepsTheRequestUnderThePointerFixed() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        let anchorX = viewport.domain.lowerBound + 0.25 * viewport.span
        let zoomed = viewport.magnified(by: 2, anchor: 0.25, stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(zoomed.span, 175)
        XCTAssertEqual(zoomed.domain.lowerBound + 0.25 * zoomed.span, anchorX, accuracy: 1e-9)
    }

    func testZoomOutStopsAtTheDensityCapAndZoomInAtTheMinimumWindow() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(viewport.magnified(by: 0.1, anchor: 0.5, stepCount: 7_196, plotWidth: 700).span, 350)
        XCTAssertEqual(viewport.magnified(by: 1_000, anchor: 0.5, stepCount: 7_196, plotWidth: 700).span,
                       Viewport.minVisibleRequests)
    }

    func testInvalidZoomLeavesTheWindowUnchanged() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(viewport.magnified(by: 0, anchor: 0.5, stepCount: 7_196, plotWidth: 700), viewport)
        XCTAssertEqual(viewport.magnified(by: .nan, anchor: 0.5, stepCount: 7_196, plotWidth: 700), viewport)
    }

    func testCommandScrollUpZoomsInAndMouseWheelStepsMatchTrackpadPoints() {
        XCTAssertGreaterThan(Viewport.zoomFactor(forScrollDelta: 10, precise: true), 1)
        XCTAssertLessThan(Viewport.zoomFactor(forScrollDelta: -10, precise: true), 1)
        XCTAssertEqual(Viewport.zoomFactor(forScrollDelta: 0, precise: true), 1)
        XCTAssertEqual(Viewport.zoomFactor(forScrollDelta: 1, precise: false),
                       Viewport.zoomFactor(forScrollDelta: Viewport.wheelStep, precise: true), accuracy: 1e-12)
    }

    // MARK: Pan and reveal

    func testPanningRightRevealsEarlierRequestsAndClampsAtBothEnds() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        let earlier = viewport.panned(byPoints: 70, stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(earlier.domain.lowerBound, viewport.domain.lowerBound - 35, accuracy: 1e-9)
        XCTAssertEqual(earlier.span, viewport.span)
        XCTAssertEqual(viewport.panned(byPoints: -700, stepCount: 7_196, plotWidth: 700), viewport,
                       "already at the latest request")
        XCTAssertEqual(viewport.panned(byPoints: 1_000_000, stepCount: 7_196, plotWidth: 700).domain.lowerBound, 0.5)
    }

    func testRevealMovesTheSmallestDistanceToShowARequest() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(viewport.revealing(7_000, stepCount: 7_196, plotWidth: 700), viewport, "already visible")
        let revealed = viewport.revealing(6_000, stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(revealed.domain.lowerBound, 5_999.5)
        XCTAssertEqual(revealed.span, viewport.span)
    }

    // MARK: Live sessions

    func testAWindowOnTheLatestRequestsFollowsNewOnes() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        let grown = viewport.following(growthFrom: 7_196, to: 7_200, plotWidth: 700)
        XCTAssertEqual(grown.domain.upperBound, 7_200.5)
        XCTAssertEqual(grown.span, viewport.span)
    }

    func testAWholeSessionStaysWholeWhileItFitsTheCap() {
        let viewport = Viewport.initial(stepCount: 102, plotWidth: 700)
        XCTAssertEqual(viewport.following(growthFrom: 102, to: 110, plotWidth: 700).domain, 0.5...110.5)
    }

    func testAWindowInThePastStaysPutWhenTheSessionGrows() {
        let past = Viewport.initial(stepCount: 7_196, plotWidth: 700).panned(byPoints: 700, stepCount: 7_196,
                                                                             plotWidth: 700)
        XCTAssertEqual(past.following(growthFrom: 7_196, to: 7_200, plotWidth: 700), past)
    }

    func testAShorterSessionStartsOver() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(viewport.following(growthFrom: 7_196, to: 35, plotWidth: 700),
                       Viewport.initial(stepCount: 35, plotWidth: 700))
    }

    // MARK: Drawing range and ticks

    func testVisibleIndicesIncludeOneNeighbourOnEachSideForStepLines() {
        let viewport = Viewport.initial(stepCount: 7_196, plotWidth: 700)
        XCTAssertEqual(viewport.visibleIndices(stepCount: 7_196), 6_846...7_196)
        let middle = viewport.panned(byPoints: 7_000, stepCount: 7_196, plotWidth: 700)
        guard let range = middle.visibleIndices(stepCount: 7_196) else { return XCTFail("expected a range") }
        XCTAssertEqual(range.lowerBound, Int(middle.domain.lowerBound.rounded(.down)))
        XCTAssertEqual(range.upperBound, Int(middle.domain.upperBound.rounded(.up)))
    }

    func testWindowLabelNamesTheVisibleRequestsOnlyWhenThereIsMore() {
        XCTAssertNil(ContextAnatomyPresentation.windowLabel(for: 0.5...102.5, stepCount: 102))
        XCTAssertEqual(ContextAnatomyPresentation.windowLabel(for: 6_846.5...7_196.5, stepCount: 7_196),
                       "Requests 6847–7196 of 7196 · pinch or ⌘-scroll to zoom, scroll sideways or drag to move")
    }

    func testTickStrideDependsOnTheWindowSpanNotOnHowManyRequestsItEncloses() {
        // The same 240.2-request window encloses 240 or 241 whole requests depending on where it sits.
        let encloses240 = ContextAnatomyPresentation.xTicks(in: 100.4...340.6, stepCount: 7_196)
        let encloses241 = ContextAnatomyPresentation.xTicks(in: 100.9...341.1, stepCount: 7_196)
        XCTAssertEqual(encloses240[1] - encloses240[0], encloses241[1] - encloses241[0],
                       "panning must not change the tick stride")
    }

    func testWindowTicksAreStableMultiplesInsideTheWindow() {
        let ticks = ContextAnatomyPresentation.xTicks(in: 6_846.5...7_196.5, stepCount: 7_196)
        XCTAssertLessThanOrEqual(ticks.count, ContextAnatomyPresentation.maxTickCount + 1)
        XCTAssertTrue(ticks.allSatisfy { (6_847...7_196).contains($0) })
        let stride = ticks[1] - ticks[0]
        XCTAssertTrue(ticks.allSatisfy { $0.isMultiple(of: stride) }, "panning must not make labels jitter")
        XCTAssertEqual(ContextAnatomyPresentation.xTicks(in: 0.5...5.5, stepCount: 5), [1, 2, 3, 4, 5])
        XCTAssertEqual(ContextAnatomyPresentation.xTicks(in: 0.5...102.5, stepCount: 102).first, 1,
                       "the first request stays labelled when the window starts at it")
    }
}
