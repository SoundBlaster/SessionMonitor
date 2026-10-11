import Foundation
import MonitorCore
import Testing

struct ContextAnatomyTests {
    private func request(_ id: String, at second: Double, input: Int64?, cached: Int64? = nil,
                         output: Int64? = 10) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: "S", timestamp: Date(timeIntervalSince1970: second), kind: .usageRequest,
            inputTokens: input, cachedInputTokens: cached, outputTokens: output, model: "m"
        )
    }

    private func event(_ kind: TimelineEventKind, at second: Double) -> RequestTimelinePoint {
        RequestTimelinePoint(id: "e:\(second):\(kind.rawValue)", sessionID: "S",
                             timestamp: Date(timeIntervalSince1970: second), kind: kind)
    }

    private func build(_ points: [RequestTimelinePoint]) throws -> ContextAnatomy {
        ContextAnatomyBuilder.build(RequestTimeline(sessionID: "S", query: try UsageQuery(), points: points))
    }

    @Test func stepsKeepOrderAndOneBasedIndexes() throws {
        let anatomy = try build([request("a", at: 1, input: 10), request("b", at: 2, input: 20)])
        #expect(anatomy.steps.map(\.id) == ["a", "b"])
        #expect(anatomy.steps.map(\.index) == [1, 2])
        #expect(anatomy.steps[0].model == "m")
        #expect(anatomy.basis == .sessionPeak)
    }

    @Test func newInputIsNilWhenCacheUnknown() throws {
        let anatomy = try build([request("a", at: 1, input: 100, cached: 80), request("b", at: 2, input: 50)])
        #expect(anatomy.steps[0].newInputTokens == 20)
        #expect(anatomy.steps[1].newInputTokens == nil)
        #expect(anatomy.steps[1].cachedInputTokens == nil)
    }

    @Test func deltaIsNilFirstAndNegativeAfterCompaction() throws {
        let anatomy = try build([request("a", at: 1, input: 100), request("b", at: 2, input: 300),
                                 event(.compaction, at: 3), request("c", at: 4, input: 120)])
        #expect(anatomy.steps.map(\.deltaFromPrevious) == [nil, 200, -180])
    }

    @Test func cumulativeSumsInputAndOutputAndPropagatesUnknown() throws {
        let anatomy = try build([
            request("a", at: 1, input: 100, output: 10), request("b", at: 2, input: 200, output: nil),
            request("c", at: 3, input: 300, output: 5)
        ])
        #expect(anatomy.steps.map(\.cumulativeTokens) == [110, nil, nil])
    }

    @Test func fillFractionAndZoneBoundaries() throws {
        let anatomy = try build([request("a", at: 1, input: 50), request("b", at: 2, input: 75),
                                 request("c", at: 3, input: 90), request("d", at: 4, input: 100),
                                 request("e", at: 5, input: 49)])
        #expect(anatomy.peakContextTokens == 100)
        #expect(anatomy.steps.map(\.zone) == [.moderate, .high, .critical, .critical, .low])
        #expect(anatomy.steps[3].fillFraction == 1)
        #expect(ContextAnatomyBuilder.zone(forFraction: 0.4999) == .low)
        #expect(ContextAnatomyBuilder.zone(forFraction: 0.7499) == .moderate)
        #expect(ContextAnatomyBuilder.zone(forFraction: 0.8999) == .high)
    }

    @Test func activityIsGroupedBetweenRequestsAndTrailing() throws {
        let anatomy = try build([
            event(.humanTurn, at: 0), event(.goalTurn, at: 0), request("a", at: 1, input: 10),
            event(.tool, at: 2), event(.tool, at: 2), event(.wait, at: 2), event(.compaction, at: 2),
            event(.unknown, at: 2), request("b", at: 3, input: 20), event(.tool, at: 4)
        ])
        #expect(anatomy.steps[0].activityBefore == ContextActivitySummary(humanTurns: 1, goalTurns: 1))
        #expect(anatomy.steps[1].activityBefore
                == ContextActivitySummary(tools: 2, waits: 1, compactions: 1, other: 1))
        #expect(anatomy.trailingActivity == ContextActivitySummary(tools: 1))
        #expect(ContextActivitySummary.none.isEmpty)
        #expect(!anatomy.trailingActivity.isEmpty)
    }

    @Test func unknownInputRequestIsSkippedAndCounted() throws {
        let anatomy = try build([request("a", at: 1, input: 10), request("x", at: 2, input: nil),
                                 request("b", at: 3, input: 30)])
        #expect(anatomy.steps.map(\.id) == ["a", "b"])
        #expect(anatomy.steps[1].deltaFromPrevious == 20)
        #expect(anatomy.requestsWithUnknownInput == 1)
    }

    @Test func emptyTimelineAndZeroPeak() throws {
        let empty = try build([])
        #expect(empty.isEmpty)
        #expect(empty.peakContextTokens == 0)
        #expect(empty.trailingActivity.isEmpty)
        let zero = try build([request("a", at: 1, input: 0)])
        #expect(zero.steps[0].fillFraction == 0)
        #expect(zero.steps[0].zone == .low)
    }
}
