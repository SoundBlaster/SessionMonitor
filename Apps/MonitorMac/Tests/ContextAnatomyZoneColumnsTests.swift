import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

/// SM-725: context-size zones as one coloured column per request under the line, not horizontal bands.
final class ContextAnatomyZoneColumnsTests: XCTestCase {
    func testEachRequestGetsAColumnAsWideAsItsLaneSlotAndAsTallAsItsContext() {
        let anatomy = anatomy(inputs: [40, 100])
        let column = ContextAnatomyPresentation.zoneColumn(for: anatomy.steps[0])
        XCTAssertEqual(column.xStart, 0.5)
        XCTAssertEqual(column.xEnd, 1.5)
        XCTAssertEqual(column.top, 40)
        XCTAssertEqual(column.zone, .low, "40 of a 100 peak is below half")
        XCTAssertEqual(ContextAnatomyPresentation.zoneColumn(for: anatomy.steps[1]).zone, .critical)
    }

    func testColumnColourFollowsTheRequestZoneAtEveryEdge() {
        let anatomy = anatomy(inputs: [49, 50, 75, 90, 100])
        XCTAssertEqual(anatomy.steps.map { ContextAnatomyPresentation.zoneColumn(for: $0).zone },
                       [.low, .moderate, .high, .critical, .critical])
    }

    func testLegendNamesEveryZoneWithItsShareOfThePeak() {
        XCTAssertEqual(ContextAnatomyPresentation.zoneLegend.map(\.zone), [.low, .moderate, .high, .critical])
        XCTAssertEqual(ContextAnatomyPresentation.zoneLegend.map(\.title),
                       ["< 50% of peak", "50–75%", "75–90%", "≥ 90%"])
    }

    func testTheLineCoversTheFirstAndLastColumnsCompletely() {
        let anatomy = anatomy(inputs: [10, 20, 30])
        let points = ContextAnatomyPresentation.linePoints(for: anatomy.steps, stepCount: 3)
        XCTAssertEqual(points.map(\.x), [0.5, 1, 2, 3, 3.5])
        XCTAssertEqual(points.map(\.y), [10, 10, 20, 30, 30])
        XCTAssertEqual(points.map(\.stepIndex), [nil, 1, 2, 3, nil], "edge points are not requests")
    }

    func testASingleRequestStillGetsALineAcrossItsColumn() {
        let points = ContextAnatomyPresentation.linePoints(for: anatomy(inputs: [42]).steps, stepCount: 1)
        XCTAssertEqual(points.map(\.x), [0.5, 1, 1.5])
        XCTAssertEqual(Set(points.map(\.y)), [42])
    }

    func testAZoomedWindowAddsNoEdgePointsInsideTheSession() {
        let anatomy = anatomy(inputs: [10, 20, 30, 40, 50])
        let middle = Array(anatomy.steps[1...3])
        XCTAssertEqual(ContextAnatomyPresentation.linePoints(for: middle, stepCount: 5).map(\.x), [2, 3, 4])
    }

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
