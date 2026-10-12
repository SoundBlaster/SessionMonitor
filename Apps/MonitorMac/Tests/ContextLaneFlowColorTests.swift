import MonitorCore
import SwiftUI
import XCTest
@testable import SessionMonitor

/// SM-726: lane flows use palette roles — green user input, blue model output, purple everything else.
final class ContextLaneFlowColorTests: XCTestCase {
    func testLaneSegmentsMapToTheirFlows() {
        XCTAssertEqual(ContextLaneSegments.Kind.newInput.flow, .input)
        XCTAssertEqual(ContextLaneSegments.Kind.output.flow, .output)
        XCTAssertEqual(ContextLaneSegments.Kind.reasoning.flow, .output, "reasoning is part of the model output")
        XCTAssertEqual(ContextLaneSegments.Kind.otherActivity.flow, .other)
    }

    /// Purple covers everything before a request that has no marker of its own: human turns and compactions
    /// are drawn on the main chart, so only they stay out of the lane's other-activity tick.
    func testOtherActivityTickCoversEveryUnmarkedEventKind() {
        for kind in [TimelineEventKind.tool, .wait, .goalTurn, .unknown] {
            XCTAssertTrue(lane(after: kind).hasOtherActivity, "\(kind)")
        }
        for kind in [TimelineEventKind.humanTurn, .compaction] {
            XCTAssertFalse(lane(after: kind).hasOtherActivity, "\(kind)")
        }
    }

    func testSystemPaletteUsesAdaptiveGreenBlueAndPurple() {
        let palette = UsageChartPalette.system
        XCTAssertEqual(palette.color(for: UsageChartPalette.Flow.input), .green)
        XCTAssertEqual(palette.color(for: UsageChartPalette.Flow.output), .blue)
        XCTAssertEqual(palette.color(for: UsageChartPalette.Flow.other), .purple)
    }

    func testEveryPaletteKeepsTheThreeFlowsDistinct() {
        for selection in UsageChartPaletteSelection.allCases {
            let colors = UsageChartPalette.Flow.allCases.map { selection.palette.color(for: $0) }
            XCTAssertEqual(Set(colors.map(String.init(describing:))).count, 3, "\(selection) palette")
        }
    }

    private func lane(after kind: TimelineEventKind) -> ContextLaneSegments {
        guard let query = try? UsageQuery(since: nil, until: nil) else {
            preconditionFailure("UsageQuery without bounds must be valid")
        }
        let points = [
            RequestTimelinePoint(id: "e", sessionID: "s", timestamp: Date(timeIntervalSince1970: 0), kind: kind),
            RequestTimelinePoint(
                id: "r", sessionID: "s", timestamp: Date(timeIntervalSince1970: 1), kind: .usageRequest,
                inputTokens: 100, cachedInputTokens: 0, uncachedInputTokens: nil,
                outputTokens: 10, reasoningOutputTokens: nil, model: nil
            )
        ]
        let anatomy = ContextAnatomyBuilder.build(RequestTimeline(sessionID: "s", query: query, points: points))
        return ContextLaneSegments(step: anatomy.steps[0])
    }
}
