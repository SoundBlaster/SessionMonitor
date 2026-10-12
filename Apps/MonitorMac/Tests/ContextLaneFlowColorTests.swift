import SwiftUI
import XCTest
@testable import SessionMonitor

/// SM-726: lane flows use palette roles — green user input, blue model output, purple everything else.
final class ContextLaneFlowColorTests: XCTestCase {
    func testLaneSegmentsMapToTheirFlows() {
        XCTAssertEqual(ContextLaneSegments.Kind.newInput.flow, .input)
        XCTAssertEqual(ContextLaneSegments.Kind.output.flow, .output)
        XCTAssertEqual(ContextLaneSegments.Kind.reasoning.flow, .output, "reasoning is part of the model output")
        XCTAssertEqual(ContextLaneSegments.Kind.toolsOrWaits.flow, .other)
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
}
