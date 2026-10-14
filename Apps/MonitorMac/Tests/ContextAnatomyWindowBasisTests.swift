import MonitorCore
import XCTest
@testable import SessionMonitor

/// SM-727: every text that explains the column colours names the basis they are measured against.
final class ContextAnatomyWindowBasisTests: XCTestCase {
    func testSnapshotNamesTheWindowItMeasuresAgainst() throws {
        let anatomy = try anatomy([request("a", 0, input: 38_232, window: 258_400),
                                   request("b", 1, input: 38_600, window: 258_400)])
        let lines = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[1], in: anatomy, timeZone: .gmt)
        XCTAssertEqual(lines[1], "Context 38.6k (15% of 258.4k window, low) · +368 vs previous")
    }

    func testABorrowedWindowIsMarkedApproximate() throws {
        let anatomy = try anatomy([request("a", 0, input: 30_000, window: 258_400),
                                   request("b", 1, input: 30_200, window: nil)])
        let lines = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[1], in: anatomy, timeZone: .gmt)
        XCTAssertEqual(lines[1], "Context 30.2k (12% of ~258.4k window, low) · +200 vs previous")
    }

    func testWithoutAnyWindowTheSnapshotKeepsThePeakWording() throws {
        let anatomy = try anatomy([request("a", 0, input: 30_200, window: nil)])
        let lines = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[0], in: anatomy, timeZone: .gmt)
        XCTAssertEqual(lines[1], "Context 30.2k (100% of peak, critical) · first request")
    }

    func testCaptionLegendAndColumnCaptionNameTheBasis() {
        XCTAssertTrue(ContextAnatomyPresentation.caption(for: .modelWindow)
            .hasPrefix("Context size per request, as a share of the usable context window Codex reports."))
        XCTAssertTrue(ContextAnatomyPresentation.caption(for: .sessionPeak)
            .hasPrefix("Context size per request, relative to this session's peak: the logs report no context window."))
        XCTAssertEqual(ContextAnatomyPresentation.zoneLegend(for: .modelWindow).map(\.title),
                       ["< 50% of window", "50–75%", "75–90%", "≥ 90%"])
        XCTAssertEqual(ContextAnatomyPresentation.zoneLegend(for: .sessionPeak).map(\.title),
                       ["< 50% of peak", "50–75%", "75–90%", "≥ 90%"])
        XCTAssertEqual(ContextAnatomyPresentation.columnCaption(for: .modelWindow),
                       "column colour: share of the usable context window")
        XCTAssertEqual(ContextAnatomyPresentation.columnCaption(for: .sessionPeak),
                       "column colour: share of the session peak (no window reported)")
    }

    private func anatomy(_ points: [RequestTimelinePoint]) throws -> ContextAnatomy {
        ContextAnatomyBuilder.build(RequestTimeline(sessionID: "s", query: try UsageQuery(), points: points))
    }

    private func request(_ id: String, _ seconds: TimeInterval, input: Int64, window: Int64?) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: "s", timestamp: Date(timeIntervalSince1970: seconds), kind: .usageRequest,
            inputTokens: input, cachedInputTokens: 0, uncachedInputTokens: nil, outputTokens: 10,
            reasoningOutputTokens: 0, model: "m", contextWindowTokens: window
        )
    }
}
