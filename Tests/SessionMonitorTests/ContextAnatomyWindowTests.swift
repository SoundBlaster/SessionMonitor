import Foundation
import MonitorCore
import Testing

/// SM-727: context zones are a share of the usable window Codex reports, not of the session's own peak.
struct ContextAnatomyWindowTests {
    private func request(_ id: String, at second: Double, input: Int64, window: Int64?) -> RequestTimelinePoint {
        RequestTimelinePoint(
            id: id, sessionID: "S", timestamp: Date(timeIntervalSince1970: second), kind: .usageRequest,
            inputTokens: input, outputTokens: 10, model: "m", contextWindowTokens: window
        )
    }

    private func build(_ points: [RequestTimelinePoint]) throws -> ContextAnatomy {
        ContextAnatomyBuilder.build(RequestTimeline(sessionID: "S", query: try UsageQuery(), points: points))
    }

    @Test func zonesFollowTheReportedWindowRatherThanThePeak() throws {
        let anatomy = try build([request("a", at: 1, input: 30_000, window: 258_400),
                                 request("b", at: 2, input: 38_600, window: 258_400)])
        #expect(anatomy.basis == .modelWindow)
        #expect(anatomy.steps.map(\.zone) == [.low, .low])
        #expect(abs(anatomy.steps[1].fillFraction - 38_600.0 / 258_400.0) < 1e-9)
        #expect(anatomy.steps.map(\.contextWindowTokens) == [258_400, 258_400])
        #expect(anatomy.steps.map(\.contextWindowInferred) == [false, false])
    }

    @Test func aSingleRequestIsCriticalOnlyAgainstItsOwnPeak() throws {
        let withWindow = try build([request("a", at: 1, input: 30_200, window: 258_400)])
        #expect(withWindow.steps[0].zone == .low)

        let withoutWindow = try build([request("a", at: 1, input: 30_200, window: nil)])
        #expect(withoutWindow.basis == .sessionPeak)
        #expect(withoutWindow.steps[0].zone == .critical)
        #expect(withoutWindow.steps[0].contextWindowTokens == nil)
    }

    @Test func zoneEdgesApplyToTheWindowShare() throws {
        let anatomy = try build([request("a", at: 1, input: 129_199, window: 258_400),
                                 request("b", at: 2, input: 129_200, window: 258_400),
                                 request("c", at: 3, input: 193_800, window: 258_400),
                                 request("d", at: 4, input: 232_560, window: 258_400)])
        #expect(anatomy.steps.map(\.zone) == [.low, .moderate, .high, .critical])
    }

    /// A request whose own report is missing borrows the nearest earlier window of the session, or the
    /// nearest later one before any window is known, and says so.
    @Test func requestsWithoutTheirOwnWindowBorrowTheNearestKnownOne() throws {
        let anatomy = try build([request("a", at: 1, input: 50_000, window: nil),
                                 request("b", at: 2, input: 60_000, window: 200_000),
                                 request("c", at: 3, input: 70_000, window: nil),
                                 request("d", at: 4, input: 80_000, window: 100_000)])
        #expect(anatomy.basis == .modelWindow)
        #expect(anatomy.steps.map(\.contextWindowTokens) == [200_000, 200_000, 200_000, 100_000])
        #expect(anatomy.steps.map(\.contextWindowInferred) == [true, false, true, false])
        #expect(anatomy.steps.map(\.zone) == [.low, .low, .low, .high])
    }
}
