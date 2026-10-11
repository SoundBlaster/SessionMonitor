import Foundation
import MonitorCore
import XCTest
@testable import SessionMonitor

final class ContextAnatomyPresentationTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC") ?? .gmt

    // MARK: Geometry

    func testStepIndexRoundsAndClampsToRequestRange() {
        XCTAssertEqual(ContextAnatomyPresentation.stepIndex(forX: 3.4, stepCount: 10), 3)
        XCTAssertEqual(ContextAnatomyPresentation.stepIndex(forX: 3.6, stepCount: 10), 4)
        XCTAssertEqual(ContextAnatomyPresentation.stepIndex(forX: 0.5, stepCount: 10), 1)
        XCTAssertEqual(ContextAnatomyPresentation.stepIndex(forX: -4, stepCount: 10), 1)
        XCTAssertEqual(ContextAnatomyPresentation.stepIndex(forX: 99, stepCount: 10), 10)
        XCTAssertEqual(ContextAnatomyPresentation.stepIndex(forX: 10.5, stepCount: 10), 10)
    }

    func testStepIndexIsNilWithoutStepsOrFiniteInput() {
        XCTAssertNil(ContextAnatomyPresentation.stepIndex(forX: 1, stepCount: 0))
        XCTAssertNil(ContextAnatomyPresentation.stepIndex(forX: .nan, stepCount: 5))
        XCTAssertNil(ContextAnatomyPresentation.stepIndex(forX: .infinity, stepCount: 5))
    }

    func testTicksAreIntegersAndThinDenseSessions() {
        XCTAssertEqual(ContextAnatomyPresentation.xTicks(stepCount: 0), [])
        XCTAssertEqual(ContextAnatomyPresentation.xTicks(stepCount: 1), [1])
        XCTAssertEqual(ContextAnatomyPresentation.xTicks(stepCount: 5), [1, 2, 3, 4, 5])
        let dense = ContextAnatomyPresentation.xTicks(stepCount: 500)
        XCTAssertLessThanOrEqual(dense.count, ContextAnatomyPresentation.maxTickCount + 1)
        XCTAssertEqual(dense.first, 1)
        XCTAssertTrue(dense.allSatisfy { (1...500).contains($0) })
    }

    func testDomainsHandleSingleRequestAndZeroPeak() {
        XCTAssertEqual(ContextAnatomyPresentation.xDomain(stepCount: 1), 0.5...1.5)
        XCTAssertEqual(ContextAnatomyPresentation.xDomain(stepCount: 0), 0.5...1.5)
        XCTAssertEqual(ContextAnatomyPresentation.yDomain(peak: 0), 0...1)
        XCTAssertEqual(ContextAnatomyPresentation.yDomain(peak: 200), 0...200)
    }

    func testZoneBandsTileTheRangeAndMatchCoreZones() {
        let bands = ContextZoneBand.all
        XCTAssertEqual(bands.first?.lowerFraction, 0)
        XCTAssertEqual(bands.last?.upperFraction, 1)
        for (previous, next) in zip(bands, bands.dropFirst()) {
            XCTAssertEqual(previous.upperFraction, next.lowerFraction)
        }
        for band in bands {
            XCTAssertEqual(ContextAnatomyBuilder.zone(forFraction: band.lowerFraction), band.zone)
        }
    }

    // MARK: Snapshot text

    func testSnapshotForFullyKnownRequest() {
        let anatomy = anatomy([
            point("a", 0, input: 100_000, cached: 80_000, output: 1_000, reasoning: 200),
            point("b", 10, input: 182_400, cached: 160_000, output: 3_200, reasoning: 1_100, model: "gpt-5")
        ])
        let lines = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[1], in: anatomy, timeZone: utc)
        XCTAssertEqual(lines, [
            "Request 2 of 2 · 00:00:10 · gpt-5",
            "Context 182.4k (100% of peak, critical) · +82.4k vs previous",
            "Cached 160.0k · new 22.4k",
            "Output 3.2k (reasoning 1.1k)",
            "Cumulative 286.6k",
            "no events since previous request"
        ])
    }

    func testFirstRequestHasNoDeltaAndUnknownCacheIsExplicit() {
        let anatomy = anatomy([point("a", 3_661, input: 500)])
        let lines = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[0], in: anatomy, timeZone: utc)
        XCTAssertEqual(lines[0], "Request 1 of 1 · 01:01:01")
        XCTAssertEqual(lines[1], "Context 500 (100% of peak, critical) · first request")
        XCTAssertEqual(lines[2], "cache split unknown")
        XCTAssertEqual(lines[3], "Output unknown")
        XCTAssertEqual(lines[4], "cumulative unknown (a request has unknown output)")
        XCTAssertEqual(lines[5], "no events before first request")
    }

    func testUnknownReasoningAndNegativeDelta() {
        let anatomy = anatomy([
            point("a", 0, input: 200_000, cached: 0, output: 10),
            point("b", 5, input: 50_000, cached: 40_000, output: 20)
        ])
        let lines = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[1], in: anatomy, timeZone: utc)
        XCTAssertEqual(lines[1], "Context 50.0k (25% of peak, low) · \u{2212}150.0k vs previous")
        XCTAssertEqual(lines[3], "Output 20 (reasoning unknown)")
    }

    func testCumulativeStaysUnknownAfterAnUnknownOutput() {
        let anatomy = anatomy([
            point("a", 0, input: 10, output: 1),
            point("b", 1, input: 10),
            point("c", 2, input: 10, output: 1)
        ])
        XCTAssertNotNil(anatomy.steps[0].cumulativeTokens)
        for step in anatomy.steps.dropFirst() {
            let lines = ContextAnatomyPresentation.snapshotLines(for: step, in: anatomy, timeZone: utc)
            XCTAssertEqual(lines[4], "cumulative unknown (a request has unknown output)")
        }
    }

    func testActivityTextListsEveryKindWithPlurals() {
        let events: [RequestTimelinePoint] = [
            event("t1", 1, .tool), event("t2", 2, .tool), event("t3", 3, .tool), event("w", 4, .wait),
            event("h", 5, .humanTurn), event("g", 6, .goalTurn), event("c", 7, .compaction), event("u", 8, .unknown)
        ]
        let timeline = [point("a", 0, input: 10)] + events + [point("b", 9, input: 20)]
        let anatomy = anatomy(timeline)
        let line = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[1], in: anatomy, timeZone: utc)[5]
        XCTAssertEqual(line, "Since previous request: 3 tools, 1 wait, 1 human turn, 1 goal turn, "
                       + "compaction, 1 other event")
    }

    func testMultipleCompactionsAreCounted() {
        let timeline = [point("a", 0, input: 10), event("c1", 1, .compaction), event("c2", 2, .compaction),
                        point("b", 3, input: 5)]
        let anatomy = anatomy(timeline)
        let line = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[1], in: anatomy, timeZone: utc)[5]
        XCTAssertEqual(line, "Since previous request: 2 compactions")
    }

    func testClockTimeUsesTheGivenTimeZone() throws {
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let anatomy = anatomy([point("a", 0, input: 10)])
        let line = ContextAnatomyPresentation.snapshotLines(for: anatomy.steps[0], in: anatomy, timeZone: tokyo)[0]
        XCTAssertEqual(line, "Request 1 of 1 · 09:00:00")
    }

    // MARK: Accessible snapshot (SM-720 review)

    func testAccessibleSnapshotReadsTheCardLinesOrTheInspectionHint() {
        let anatomy = anatomy([point("a", 0, input: 100, cached: 40, output: 10, reasoning: 2, model: "m")])
        let step = anatomy.steps[0]
        XCTAssertEqual(
            ContextAnatomyPresentation.snapshotAccessibilityValue(for: step, in: anatomy, timeZone: utc),
            ContextAnatomyPresentation.snapshotLines(for: step, in: anatomy, timeZone: utc).joined(separator: ". ")
        )
        XCTAssertEqual(ContextAnatomyPresentation.snapshotAccessibilityValue(for: nil, in: anatomy, timeZone: utc),
                       ContextAnatomyPresentation.inspectionHint)
    }

    // MARK: Formatting and accessibility

    func testCompactTokensFormatting() {
        let cases: [(Int64, String)] = [
            (0, "0"), (950, "950"), (999, "999"), (1_000, "1.0k"), (182_400, "182.4k"),
            (999_949, "999.9k"), (999_950, "1.0M"), (2_100_000, "2.1M"), (1_300_000_000, "1.3B"), (-1_500, "-1.5k")
        ]
        for (value, expected) in cases {
            XCTAssertEqual(ContextAnatomyPresentation.compactTokens(value), expected, "\(value)")
        }
    }

    func testAccessibilitySummary() {
        let timeline = [
            point("a", 0, input: 1_000), event("c", 1, .compaction), point("b", 2, input: 2_500),
            point("skipped", 3, input: nil), event("c2", 4, .compaction)
        ]
        XCTAssertEqual(
            ContextAnatomyPresentation.accessibilitySummary(anatomy(timeline)),
            "Context anatomy: 2 requests, peak 2.5k tokens, final context 2.5k tokens, 2 compactions. "
                + "1 request skipped for unknown input."
        )
        XCTAssertEqual(
            ContextAnatomyPresentation.accessibilitySummary(anatomy([point("a", 0, input: 7)])),
            "Context anatomy: 1 request, peak 7 tokens, final context 7 tokens, 0 compactions."
        )
        XCTAssertEqual(ContextAnatomyPresentation.accessibilitySummary(anatomy([])),
                       "Context anatomy: no requests with known input.")
    }

    // MARK: Lane

    func testLaneSplitsInputOutputAndReasoningWithinOneColumn() {
        let anatomy = anatomy([
            point("a", 0, input: 1_000, cached: 400, output: 400, reasoning: 100)
        ])
        let lane = ContextLaneSegments(step: anatomy.steps[0])
        XCTAssertEqual(lane.inputFraction, 0.6, accuracy: 1e-9)
        XCTAssertEqual(lane.outputFraction, 0.4, accuracy: 1e-9)
        XCTAssertEqual(lane.reasoningFraction, 0.1, accuracy: 1e-9)
        XCTAssertTrue(lane.inputKnown)
        XCTAssertTrue(lane.outputKnown)
        XCTAssertTrue(lane.reasoningKnown)
        XCTAssertFalse(lane.hasToolsOrWaits)
    }

    func testLaneTreatsUnknownCacheAsWholeInputNotZero() {
        let anatomy = anatomy([point("a", 0, input: 900, output: 100)])
        let lane = ContextLaneSegments(step: anatomy.steps[0])
        XCTAssertFalse(lane.inputKnown)
        XCTAssertEqual(lane.inputFraction, 0.9, accuracy: 1e-9)
        XCTAssertEqual(lane.outputFraction, 0.1, accuracy: 1e-9)
        XCTAssertEqual(lane.reasoningFraction, 0)
        XCTAssertFalse(lane.reasoningKnown)
    }

    func testLaneDistinguishesExplicitZeroReasoningFromUnknown() {
        let explicitZero = anatomy([point("a", 0, input: 900, cached: 0, output: 100, reasoning: 0)])
        let zeroLane = ContextLaneSegments(step: explicitZero.steps[0])
        XCTAssertTrue(zeroLane.reasoningKnown)
        XCTAssertEqual(zeroLane.reasoningFraction, 0)

        let unknown = anatomy([point("b", 0, input: 900, cached: 0, output: 100)])
        let unknownLane = ContextLaneSegments(step: unknown.steps[0])
        XCTAssertFalse(unknownLane.reasoningKnown)
        XCTAssertEqual(unknownLane.reasoningFraction, 0)

        let noOutput = anatomy([point("c", 0, input: 900, cached: 0)])
        XCTAssertTrue(ContextLaneSegments(step: noOutput.steps[0]).reasoningKnown)
    }

    func testLaneWithUnknownOutputAndZeroTokens() {
        let unknownOutput = anatomy([point("a", 0, input: 500, cached: 100)])
        let lane = ContextLaneSegments(step: unknownOutput.steps[0])
        XCTAssertFalse(lane.outputKnown)
        XCTAssertEqual(lane.inputFraction, 1)
        XCTAssertEqual(lane.outputFraction, 0)

        let zero = anatomy([point("z", 0, input: 0, cached: 0, output: 0)])
        let empty = ContextLaneSegments(step: zero.steps[0])
        XCTAssertEqual(empty.inputFraction, 0)
        XCTAssertEqual(empty.outputFraction, 0)
        XCTAssertEqual(empty.reasoningFraction, 0)
    }

    func testLaneClampsReasoningToOutputAndMarksToolsAndWaits() {
        let timeline = [event("w", 0, .wait), point("a", 1, input: 100, cached: 0, output: 100, reasoning: 999)]
        let lane = ContextLaneSegments(step: anatomy(timeline).steps[0])
        XCTAssertEqual(lane.reasoningFraction, lane.outputFraction, accuracy: 1e-9)
        XCTAssertTrue(lane.hasToolsOrWaits)

        let humanOnly = ContextLaneSegments(step: anatomy([event("h", 0, .humanTurn),
                                                           point("b", 1, input: 1)]).steps[0])
        XCTAssertFalse(humanOnly.hasToolsOrWaits)
    }

    // MARK: Fixtures

    private func anatomy(_ points: [RequestTimelinePoint]) -> ContextAnatomy {
        guard let query = try? UsageQuery(since: nil, until: nil) else {
            preconditionFailure("UsageQuery without bounds must be valid")
        }
        return ContextAnatomyBuilder.build(RequestTimeline(sessionID: "s", query: query, points: points))
    }

    private func point(_ id: String, _ seconds: TimeInterval, input: Int64?, cached: Int64? = nil,
                       output: Int64? = nil, reasoning: Int64? = nil, model: String? = nil) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: "s", timestamp: Date(timeIntervalSince1970: seconds), kind: .usageRequest,
            inputTokens: input, cachedInputTokens: cached, uncachedInputTokens: nil,
            outputTokens: output, reasoningOutputTokens: reasoning, model: model
        )
    }

    private func event(_ id: String, _ seconds: TimeInterval, _ kind: TimelineEventKind) -> RequestTimelinePoint {
        RequestTimelinePoint(id: id, sessionID: "s", timestamp: Date(timeIntervalSince1970: seconds), kind: kind)
    }
}
