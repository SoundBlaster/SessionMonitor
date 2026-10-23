import AppKit
import SwiftUI
import MonitorCore
import Foundation
import XCTest
@testable import SessionMonitor

/// Pointer-free rules of the Context anatomy chart: where the floating snapshot card sits and how keyboard
/// or VoiceOver stepping moves the inspected request.
final class ContextAnatomyInteractionTests: XCTestCase {
    @MainActor
    func testSnapshotHeightIsStableAcrossSignalsFirstRequestAndInferredWindow() throws {
        let query = try UsageQuery(since: nil, until: nil)
        let points = (0..<3).map { index in
            RequestTimelinePoint(id: "request-\(index)", sessionID: "fixture",
                                 timestamp: Date(timeIntervalSince1970: Double(index)), kind: .usageRequest,
                                 inputTokens: 145_500, cachedInputTokens: 18_200, outputTokens: 964,
                                 contextWindowTokens: index == 1 ? nil : 258_400)
        }
        let anatomy = ContextAnatomyBuilder.build(RequestTimeline(sessionID: "fixture", query: query, points: points))
        XCTAssertTrue(anatomy.steps[1].contextWindowInferred)
        for width in [340.0, 240.0, 160.0] {
            for scheme in [ColorScheme.light, .dark] {
                for typeSize in [DynamicTypeSize.large, .accessibility1] {
                    var baseline: CGFloat?
                    for step in anatomy.steps {
                        for count in [0, 1, 12] {
                            let content = ContextAnatomySnapshotCard(
                                step: step, requestCount: 9_419, timeZone: .gmt,
                                palette: .system, insightCount: count
                            )
                            .environment(\.colorScheme, scheme)
                            .environment(\.dynamicTypeSize, typeSize)
                            .frame(width: width)
                            let host = NSHostingView(rootView: content)
                            let height = host.fittingSize.height
                            XCTAssertGreaterThan(height, 0)
                            if let baseline {
                                XCTAssertEqual(height, baseline, accuracy: 1,
                                               "Width \(width), count \(count), request \(step.index)")
                            } else {
                                baseline = height
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Snapshot card placement (SM-720)

    func testSnapshotCardGoesRightOfTheRuleWhenItFits() {
        let placement = ContextAnatomyPresentation.snapshotCardPlacement(anchorX: 100, plotWidth: 650)
        XCTAssertEqual(placement.side, .right)
        XCTAssertEqual(placement.width, ContextAnatomyPresentation.snapshotCardWidth)
    }

    func testSnapshotCardStaysRightAtTheMiddleOfAWidePlot() {
        // 360 pt of plot on each side minus the gap still holds the 340 pt card.
        let placement = ContextAnatomyPresentation.snapshotCardPlacement(anchorX: 360, plotWidth: 720)
        XCTAssertEqual(placement.side, .right)
        XCTAssertEqual(placement.width, ContextAnatomyPresentation.snapshotCardWidth)
    }

    func testSnapshotCardFlipsLeftNearTheRightEdge() {
        let placement = ContextAnatomyPresentation.snapshotCardPlacement(anchorX: 600, plotWidth: 650)
        XCTAssertEqual(placement.side, .left)
        XCTAssertEqual(placement.width, ContextAnatomyPresentation.snapshotCardWidth)
    }

    func testSnapshotCardShrinksIntoTheRoomierSideOfANarrowPlot() {
        let tie = ContextAnatomyPresentation.snapshotCardPlacement(anchorX: 200, plotWidth: 400)
        XCTAssertEqual(tie.side, .right, "a tie reads left to right")
        XCTAssertEqual(tie.width, 200 - ContextAnatomyPresentation.snapshotCardGap, accuracy: 1e-9)

        let nearRight = ContextAnatomyPresentation.snapshotCardPlacement(anchorX: 250, plotWidth: 400)
        XCTAssertEqual(nearRight.side, .left)
        XCTAssertEqual(nearRight.width, 250 - ContextAnatomyPresentation.snapshotCardGap, accuracy: 1e-9)
    }

    func testSnapshotCardNeverShrinksBelowItsMinimumWidth() {
        let placement = ContextAnatomyPresentation.snapshotCardPlacement(anchorX: 100, plotWidth: 200)
        XCTAssertEqual(placement.width, ContextAnatomyPresentation.snapshotCardMinWidth)
        let degenerate = ContextAnatomyPresentation.snapshotCardPlacement(anchorX: .nan, plotWidth: 0)
        XCTAssertEqual(degenerate.side, .right)
        XCTAssertEqual(degenerate.width, ContextAnatomyPresentation.snapshotCardMinWidth)
    }

    // MARK: Inspection without a pointer (SM-720 review)

    func testSteppingStartsAtAnEdgeAndClampsToTheRequestRange() {
        XCTAssertEqual(ContextAnatomyPresentation.steppedIndex(from: nil, by: 1, stepCount: 5), 1)
        XCTAssertEqual(ContextAnatomyPresentation.steppedIndex(from: nil, by: -1, stepCount: 5), 5)
        XCTAssertEqual(ContextAnatomyPresentation.steppedIndex(from: 3, by: 1, stepCount: 5), 4)
        XCTAssertEqual(ContextAnatomyPresentation.steppedIndex(from: 5, by: 1, stepCount: 5), 5)
        XCTAssertEqual(ContextAnatomyPresentation.steppedIndex(from: 1, by: -1, stepCount: 5), 1)
        XCTAssertEqual(ContextAnatomyPresentation.steppedIndex(from: 9, by: -1, stepCount: 5), 5,
                       "an index from a longer session clamps into range")
    }

    func testSteppingWithoutRequestsOrMovementInspectsNothing() {
        XCTAssertNil(ContextAnatomyPresentation.steppedIndex(from: nil, by: 1, stepCount: 0))
        XCTAssertNil(ContextAnatomyPresentation.steppedIndex(from: nil, by: 0, stepCount: 5))
    }
}
