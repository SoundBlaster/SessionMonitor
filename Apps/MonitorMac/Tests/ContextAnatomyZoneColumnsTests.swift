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
